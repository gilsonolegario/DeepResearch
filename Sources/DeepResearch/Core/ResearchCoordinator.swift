import Foundation
import SwiftData

/// Orquestrador ponta-a-ponta: cria pesquisa, acompanha por polling,
/// cancela, re-adota ao abrir. Nenhuma dependência externa — usa o
/// InteractionsClientProtocol já existente.
@MainActor
final class ResearchCoordinator {
    private let modelContext: ModelContext
    private let client: any InteractionsClientProtocol

    // MARK: - Handle de monitoramento

    /// Task ativa de polling para uma sessão — cancelar encerra o monitoramento.
    private struct TaskHandle {
        let task: Task<Void, Never>
    }

    private var monitoringTasks: [PersistentIdentifier: TaskHandle] = [:]

    /// Intervalo de polling (20 s conforme contrato).
    private let pollInterval: Duration

    // MARK: - Init

    init(
        client: any InteractionsClientProtocol,
        modelContext: ModelContext,
        pollInterval: Duration = .seconds(20)
    ) {
        self.client = client
        self.modelContext = modelContext
        self.pollInterval = pollInterval
    }

    // MARK: - Ciclo de vida

    /// Dispara uma nova pesquisa: cria sessão, chama API, inicia monitoramento.
    func start(question: String, agent: AgentKind = .regular) async {
        let session = ResearchSession(question: question, agent: agent, status: .queued)
        modelContext.insert(session)
        do { try modelContext.save() } catch { return }

        do {
            let interaction = try await client.create(question: question, agent: agent)
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
            guard let interaction = try? await client.get(id: interactionID) else { continue }

            session.interactionID = interaction.id
            mergeSteps(from: interaction, into: session)

            if isTerminal(interaction.status) {
                applyTerminalStatus(interaction.status, to: session)
            } else {
                session.status = .running
                session.phase = derivePhase(steps: interaction.steps)
                startMonitoring(session: session)
            }
            try? modelContext.save()
        }
    }

    // MARK: - Monitoramento (polling)

    private func startMonitoring(session: ResearchSession) {
        guard let interactionID = session.interactionID else { return }
        let sessionID = session.persistentModelID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.pollLoop(sessionID: sessionID, interactionID: interactionID)
        }
        monitoringTasks[sessionID] = TaskHandle(task: task)
    }

    private func stopMonitoring(session: ResearchSession) {
        if let handle = monitoringTasks.removeValue(forKey: session.persistentModelID) {
            handle.task.cancel()
        }
    }

    private func pollLoop(sessionID: PersistentIdentifier, interactionID: String) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                break // Task.cancelled → sai
            }

            guard !Task.isCancelled else { break }
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
    }

    // MARK: - Mapeamento de status

    private func statusFromAPI(_ api: InteractionStatus) -> Status {
        switch api {
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
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
        let existing = Set(session.stepLog.map { "\($0.type):\($0.text)" })

        for step in interaction.steps {
            let entry = StepEntry(
                timestamp: .now,
                type: step.typeName,
                text: textFromStep(step)
            )
            let key = "\(entry.type):\(entry.text)"
            if !existing.contains(key) {
                session.stepLog.append(entry)
            }
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
