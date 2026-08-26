import Foundation
import SwiftData

/// Modo de transporte ativo para monitoramento de uma sessão.
enum TransportMode: Sendable {
    case streaming
    case polling
}

/// Orquestrador ponta-a-ponta: cria pesquisa, acompanha por streaming/polling,
/// cancela, re-adota ao abrir. Streaming com fallback automático para polling.
@MainActor
final class ResearchCoordinator {
    private let modelContext: ModelContext
    private let client: any InteractionsClientProtocol

    // MARK: - Handle de monitoramento

    /// Task ativa de polling/streaming para uma sessão — cancelar encerra o monitoramento.
    private struct TaskHandle {
        let task: Task<Void, Never>
    }

    private var monitoringTasks: [PersistentIdentifier: TaskHandle] = [:]

    /// Intervalo de polling (20 s conforme contrato).
    private let pollInterval: Duration

    /// Sem progresso por este tempo → marca como falha (evita loop infinito).
    /// Deep-research normal completa em ~9m; 15m só com `user_input` é fila travada.
    private let stallTimeout: Duration

    /// Modo de transporte ativo por sessão (exposta para UI observável).
    private(set) var transportModes: [PersistentIdentifier: TransportMode] = [:]

    /// Mapeia índice do step (vindo do stream) → posição no stepLog.
    /// Usado para acumular deltas no entry correto de cada step.
    private var stepIndexToEntryIndex: [PersistentIdentifier: [Int: Int]] = [:]

    /// Modo de transporte ativo para a sessão dada (nil se sem monitoramento).
    func transportMode(for session: ResearchSession) -> TransportMode? {
        transportModes[session.persistentModelID]
    }

    // MARK: - Init

    init(
        client: any InteractionsClientProtocol,
        modelContext: ModelContext,
        pollInterval: Duration = .seconds(20),
        stallTimeout: Duration = .seconds(900)
    ) {
        self.client = client
        self.modelContext = modelContext
        self.pollInterval = pollInterval
        self.stallTimeout = stallTimeout
    }

    // MARK: - Ciclo de vida

    /// Dispara uma nova pesquisa: tenta streaming; se falhar, cria background + polling.
    /// deadlineSeconds: nil = usa default global (AppPreferences/stallTimeout); 0 = sem timeout.
    /// previousInteractionID/parentQuestion: encadeiam follow-up (api-contract: previous_interaction_id).
    func start(
        question: String,
        agent: AgentKind = .regular,
        context: String? = nil,
        deadlineSeconds: Int? = nil,
        previousInteractionID: String? = nil,
        parentQuestion: String? = nil
    ) async {
        let session = ResearchSession(
            question: question,
            agent: agent,
            status: .queued,
            deadlineSeconds: deadlineSeconds,
            parentInteractionID: previousInteractionID,
            parentQuestion: parentQuestion
        )
        modelContext.insert(session)
        do { try modelContext.save() } catch { return }

        // 1ª tentativa: streaming (stream:true, sem background).
        do {
            let stream = try await client.createStream(question: question, agent: agent, context: context, previousInteractionID: previousInteractionID)
            session.status = .running
            try modelContext.save()
            startStreamingMonitor(session: session, stream: stream)
            return
        } catch {
            // Streaming não suportado ou falhou imediatamente → fallback.
        }

        // Fallback: cria background + polling.
        do {
            let interaction = try await client.create(question: question, agent: agent, context: context, previousInteractionID: previousInteractionID)
            session.interactionID = interaction.id
            session.status = .running
            try modelContext.save()
            startMonitoring(session: session)
        } catch {
            session.status = .failed
            session.finishedAt = .now
            try? modelContext.save()
        }
    }

    /// Cria a sessão SEM chamar a API — para testes e re-adoção.
    func createSession(
        question: String,
        agent: AgentKind = .regular,
        status: Status = .queued,
        interactionID: String? = nil
    ) -> ResearchSession {
        let session = ResearchSession(
            question: question,
            agent: agent,
            status: status,
            interactionID: interactionID
        )
        modelContext.insert(session)
        try? modelContext.save()
        return session
    }

    /// Cancela uma pesquisa preservando tudo coletado.
    func cancel(session: ResearchSession) async {
        stopMonitoring(session: session)

        if let id = session.interactionID {
            if let interaction = try? await client.cancel(id: id) {
                session.status = .cancelled
                session.phase = nil
                mergeSteps(from: interaction, into: session)
            }
        } else {
            session.status = .cancelled
        }

        session.finishedAt = .now
        try? modelContext.save()
    }

    /// Se existe monitoramento ativo para a sessão dada.
    var isMonitoringActive: Bool {
        monitoringTasks.count > 0
    }

    /// Número de sessões com monitoramento ativo (para dock progress).
    var activeSessionCount: Int {
        monitoringTasks.count
    }

    /// Snapshot das sessões com interactionID e seus status atuais.
    /// Usado para detectar transições de terminal no PresenceManager.
    var terminalTransitions: [PersistentIdentifier: Status] {
        var result: [PersistentIdentifier: Status] = [:]
        let descriptor = FetchDescriptor<ResearchSession>(
            predicate: #Predicate<ResearchSession> { $0.interactionID != nil }
        )
        guard let sessions = try? modelContext.fetch(descriptor) else { return result }
        for session in sessions {
            result[session.persistentModelID] = session.status
        }
        return result
    }

    /// Verifica monitoramento para uma sessão específica.
    func isMonitoring(for session: ResearchSession) -> Bool {
        monitoringTasks[session.persistentModelID] != nil
    }

    // MARK: - Re-adoção (launch)

    /// Varre sessões não-terminal com interactionID → GET. Concluída extrai;
    /// rodando retoma Task de monitoramento.
    func adoptPendingSessions() async {
        let sessions = fetchPendingSessions()
        for session in sessions {
            guard let interactionID = session.interactionID else { continue }

            // Se o GET falhar (rede, API indisponível), inicia monitoramento
            // mesmo assim — o polling vai retryar e detectar quando a API voltar.
            if let interaction = try? await client.get(id: interactionID) {
                session.interactionID = interaction.id
                mergeSteps(from: interaction, into: session)

                if isTerminal(interaction.status) {
                    applyTerminalStatus(interaction.status, to: session)
                    try? modelContext.save()
                    continue
                }
            }

            // API indisponível ou interação ainda em andamento → monitora.
            session.status = .running
            startMonitoring(session: session)
            try? modelContext.save()
        }
    }

    // MARK: - Monitoramento (polling)

    private func startMonitoring(session: ResearchSession) {
        guard let interactionID = session.interactionID else { return }
        let sessionID = session.persistentModelID
        transportModes[sessionID] = .polling
        let task = Task { [weak self] in
            guard let self else { return }
            await self.pollLoop(sessionID: sessionID, interactionID: interactionID)
        }
        monitoringTasks[sessionID] = TaskHandle(task: task)
    }

    func stopMonitoring(session: ResearchSession) {
        if let handle = monitoringTasks.removeValue(forKey: session.persistentModelID) {
            handle.task.cancel()
        }
        transportModes.removeValue(forKey: session.persistentModelID)
    }

    private func pollLoop(sessionID: PersistentIdentifier, interactionID: String) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                break // Task.cancelled → sai
            }

            guard !Task.isCancelled else { break }

            // Watchdog: sem step novo além de `user_input` por stallTimeout → falha.
            // Evita ficar para sempre em `researching` quando a fila do servidor trava.
            if let session = modelContext.model(for: sessionID) as? ResearchSession,
               stallTimeout != .seconds(0),
               hasStalled(session: session)
            {
                session.status = .failed
                session.finishedAt = .now
                try? modelContext.save()
                break
            }

            do {
                let interaction = try await client.get(id: interactionID)
                guard let session = modelContext.model(for: sessionID) as? ResearchSession else { break }

                mergeSteps(from: interaction, into: session)
                session.phase = derivePhase(steps: interaction.steps)
                session.status = statusFromAPI(interaction.status)

                if isTerminal(interaction.status) {
                    applyTerminalStatus(interaction.status, to: session)
                    try? modelContext.save()
                    break
                }
                try? modelContext.save()
            } catch {
                // Erro de rede — mantém monitoramento ativo; retenta no próximo ciclo.
            }
        }
        // Limpa o handle do dicionário quando o loop termina.
        if let session = modelContext.model(for: sessionID) as? ResearchSession {
            monitoringTasks.removeValue(forKey: session.persistentModelID)
        }
        transportModes.removeValue(forKey: sessionID)
    }

    // MARK: - Monitoramento via SSE streaming

    private func startStreamingMonitor(session: ResearchSession, stream: AsyncStream<SSEEvent>) {
        let sessionID = session.persistentModelID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.streamMonitorLoop(sessionID: sessionID, stream: stream)
        }
        monitoringTasks[sessionID] = TaskHandle(task: task)
        transportModes[sessionID] = .streaming
    }

    /// Troca transparente de streaming → polling sem interromper o monitoramento.
    private func transitionToPolling(sessionID: PersistentIdentifier, interactionID: String) {
        transportModes[sessionID] = .polling
        let task = Task { [weak self] in
            guard let self else { return }
            await self.pollLoop(sessionID: sessionID, interactionID: interactionID)
        }
        monitoringTasks[sessionID] = TaskHandle(task: task)
    }

    private func streamMonitorLoop(sessionID: PersistentIdentifier, stream: AsyncStream<SSEEvent>) async {
        var interactionID: String?

        for await event in stream {
            guard !Task.isCancelled else { break }

            guard let session = modelContext.model(for: sessionID) as? ResearchSession else { break }

            switch event {
            case .interactionCreated(let id, _):
                interactionID = id
                session.interactionID = id

            case .stepStart(let index, let stepType):
                applyStepStart(index: index, stepType: stepType, to: session)

            case .stepDelta(let index, let delta):
                applyDelta(delta, at: index, to: session)

            case .stepStop:
                break

            case .interactionCompleted:
                if let id = interactionID,
                   let interaction = try? await client.get(id: id)
                {
                    mergeSteps(from: interaction, into: session)
                    session.phase = derivePhase(steps: interaction.steps)
                    if isTerminal(interaction.status) {
                        applyTerminalStatus(interaction.status, to: session)
                    }
                }

            case .done:
                if let id = interactionID {
                    // Validação final via GET (garante estado consistente).
                    if let interaction = try? await client.get(id: id) {
                        mergeSteps(from: interaction, into: session)
                        session.phase = derivePhase(steps: interaction.steps)
                        if isTerminal(interaction.status) {
                            applyTerminalStatus(interaction.status, to: session)
                        }
                    }
                }
                try? modelContext.save()
                monitoringTasks.removeValue(forKey: sessionID)
                transportModes.removeValue(forKey: sessionID)
                return
            }

            try? modelContext.save()
        }

        // Stream encerrou sem [DONE] — pode ser timeout/queda.
        // Fallback: se temos interactionID, continua via polling.
        guard let id = interactionID else {
            monitoringTasks.removeValue(forKey: sessionID)
            transportModes.removeValue(forKey: sessionID)
            return
        }
        transitionToPolling(sessionID: sessionID, interactionID: id)
    }

    // MARK: - Aplicação de deltas incrementalmente

    private func applyStepStart(index: Int, stepType: String, to session: ResearchSession) {
        session.phase = phaseFromStepType(stepType)
        // Registra a posição no stepLog para acumular deltas seguintes.
        let entryIndex = session.stepLog.count
        stepIndexToEntryIndex[session.persistentModelID, default: [:]][index] = entryIndex
        session.stepLog.append(StepEntry(timestamp: .now, type: stepType, text: ""))
    }

    private func applyDelta(_ delta: TextDelta, at index: Int, to session: ResearchSession) {
        guard !delta.text.isEmpty else { return }
        let sessionID = session.persistentModelID

        if let entryIndex = stepIndexToEntryIndex[sessionID]?[index],
           entryIndex < session.stepLog.count
        {
            session.stepLog[entryIndex].text += delta.text
        } else {
            // Delta sem step.start prévio — cria entry avulso.
            let stepType = stepTypeForIndex(index, session: session)
            session.stepLog.append(StepEntry(timestamp: .now, type: stepType, text: delta.text))
        }
    }

    private func stepTypeForIndex(_ index: Int, session: ResearchSession) -> String {
        // Heurística: índices menores tendem a ser thought; maior tende a ser model_output.
        // A phase corrente ajuda a discriminar.
        switch session.phase {
        case .planning: "thought"
        case .researching: "google_search"
        case .synthesizing, .none: "model_output"
        }
    }

    private func phaseFromStepType(_ stepType: String) -> Phase {
        switch stepType {
        case "thought": .planning
        case "google_search", "function_call", "google_search_result", "function_result": .researching
        case "model_output": .synthesizing
        default: .researching
        }
    }

    // MARK: - Mapeamento de status

    private func statusFromAPI(_ api: InteractionStatus) -> Status {
        switch api {
        case .completed: .completed
        case .failed, .incomplete, .budgetExceeded: .failed
        case .cancelled: .cancelled
        case .requiresAction: .requiresAction
        default: .running
        }
    }

    private func isTerminal(_ api: InteractionStatus) -> Bool {
        switch api {
        case .completed, .failed, .cancelled, .incomplete, .budgetExceeded: true
        default: false
        }
    }

    private func applyTerminalStatus(_ api: InteractionStatus, to session: ResearchSession) {
        switch api {
        case .completed:
            session.status = .completed
            session.reportText = extractReport(from: session.stepLog)
            session.images = extractImages(from: session.stepLog)
        case .failed, .incomplete, .budgetExceeded:
            session.status = .failed
        case .cancelled:
            session.status = .cancelled
        default:
            break
        }
        session.finishedAt = .now
    }

    // MARK: - Extração de relatório

    private func extractReport(from log: [StepEntry]) -> String? {
        let modelOutputEntries = log.filter { $0.type == "model_output" }
        return modelOutputEntries.last?.text.isEmpty == false ? modelOutputEntries.last?.text : nil
    }

    private func extractImages(from log: [StepEntry]) -> [Data] {
        // Por enquanto, imagens via base64 ainda não são decodificadas no stepLog.
        // O endurecimento de Content garante que imagens no JSON são preservadas.
        []
    }

    // MARK: - Heurística de fase

    private func derivePhase(steps: [Step]) -> Phase {
        // Último step com timestamp determina a fase.
        guard let last = steps.last else { return .planning }

        switch last {
        case .thought:
            return .planning
        case .googleSearchCall, .googleSearchResult, .functionCall, .functionResult:
            return .researching
        case .modelOutput:
            return .synthesizing
        default:
            return .researching
        }
    }

    // MARK: - Merge de steps

    private func mergeSteps(from interaction: Interaction, into session: ResearchSession) {
        // Deduplicação por tipo: se o step já foi registrado via streaming,
        // o GET não adiciona duplicata (texto do streaming é mais recente).
        let existingTypes = Set(session.stepLog.map(\.type))

        for step in interaction.steps {
            guard !existingTypes.contains(step.typeName) else { continue }
            let entry = StepEntry(
                timestamp: .now,
                type: step.typeName,
                text: textFromStep(step)
            )
            session.stepLog.append(entry)
        }
    }

    private func textFromStep(_ step: Step) -> String {
        switch step {
        case .modelOutput(let content), .thought(summary: let content), .userInput(let content):
            content.compactMap { if case .text(let t) = $0 { return t }; return nil }.joined(separator: "\n")
        case .functionCall(let name, _, _):
            "[\(name)]"
        case .functionResult(_, let result, _):
            result.compactMap { if case .text(let t) = $0 { return t }; return nil }.joined(separator: "\n")
        default:
            ""
        }
    }

    // MARK: - Stall detection

    /// Travou se: rodando há >= timeout efetivo E só tem `user_input` no log
    /// (nenhum `thought`/`google_search` produzido pelo servidor).
    /// deadlineSeconds da sessão tem precedência sobre o stallTimeout global.
    private func hasStalled(session: ResearchSession) -> Bool {
        guard session.status == .running else { return false }
        let effectiveTimeout: Duration
        if let ds = session.deadlineSeconds {
            if ds == 0 { return false } // sem timeout
            effectiveTimeout = .seconds(ds)
        } else {
            effectiveTimeout = stallTimeout
        }
        guard effectiveTimeout != .seconds(0) else { return false }
        let elapsed = Date.now.timeIntervalSince(session.startedAt)
        guard elapsed >= Double(effectiveTimeout.components.seconds) else { return false }
        // Se já produziu qualquer step além do user_input, não é stall.
        return session.stepLog.allSatisfy { $0.type == "user_input" }
    }

    // MARK: - Follow-up

    /// Cria uma pesquisa de follow-up vinculada à sessão pai via previous_interaction_id.
    func followUp(session: ResearchSession, question: String, context: String? = nil) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await start(
            question: trimmed,
            agent: session.agent,
            context: context,
            deadlineSeconds: session.deadlineSeconds,
            previousInteractionID: session.interactionID,
            parentQuestion: session.question
        )
    }

    // MARK: - Query SwiftData

    private func fetchPendingSessions() -> [ResearchSession] {
        // #Predicate não suporta enum literals diretamente — busca todas com
        // interactionID e filtra em Swift (volume esperado é pequeno).
        let descriptor = FetchDescriptor<ResearchSession>(
            predicate: #Predicate<ResearchSession> { session in
                session.interactionID != nil
            }
        )
        guard let all = try? modelContext.fetch(descriptor) else { return [] }
        return all.filter { session in
            session.status != .completed
                && session.status != .cancelled
                && session.status != .failed
        }
    }
}
