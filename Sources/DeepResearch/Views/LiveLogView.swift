import SwiftUI
import SwiftData

/// Log ao vivo de uma pesquisa: banner de estado + lista de etapas + barra de progresso.
struct LiveLogView: View {
    let session: ResearchSession
    let coordinator: ResearchCoordinator

    /// Ticker a cada segundo vive no ProgressFooterView (único consumidor),
    /// para sessões concluídas NÃO re-renderizarem a cada segundo.
    @State private var showReport = false
    @State private var pulse = false

    /// Tamanho da fonte no log (compartilhado com o StepRow)
    @AppStorage("logFontSize") private var fontSize: Double = 13

    var body: some View {
        VStack(spacing: 0) {
            // Banner para estados especiais
            if session.status == .cancelled || session.status == .failed {
                StatusBannerView(session: session, coordinator: coordinator)
            }

            // Trilha de fases (Planejando → Pesquisando → Escrevendo)
            if session.status == .running {
                PhaseTrailView(currentPhase: session.phase)
            }

            // Loading animation centralizada (apenas antes do 1º step chegar)
            if session.status == .running && session.stepLog.isEmpty {
                Spacer()
                loadingAnimation
                Spacer()
            } else {
                // Lista de etapas
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            // user_input chega como input montado pelo buildInput
                            // (instrução de formato + contexto + pergunta). Exibimos
                            // só o que interessa: pergunta como linha normal no topo,
                            // contexto de pasta como DisclosureGroup no FIM do log.
                            let displayEntries: [StepEntry] = session.stepLog.flatMap { entry -> [StepEntry] in
                                guard entry.type == "user_input" else { return [entry] }
                                let (question, context) = Self.splitUserInput(entry.text)
                                var rows: [StepEntry] = []
                                if let q = question {
                                    rows.append(StepEntry(timestamp: entry.timestamp, type: "user_input", text: q))
                                }
                                if let c = context {
                                    rows.append(StepEntry(timestamp: entry.timestamp, type: "folder_context", text: c))
                                }
                                if rows.isEmpty { rows.append(entry) }
                                return rows
                            }
                            let contextEntries = displayEntries.filter { $0.type == "folder_context" }
                            let otherEntries = displayEntries.filter { $0.type != "folder_context" }
                            ForEach(Array(otherEntries.enumerated()), id: \.offset) { index, entry in
                                StepRow(entry: entry, fontSize: fontSize)
                                    .id(index)
                            }
                            ForEach(Array(contextEntries.enumerated()), id: \.offset) { index, entry in
                                StepRow(entry: entry, fontSize: fontSize)
                                    .id(index + otherEntries.count)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: session.stepLog.count) { _, newCount in
                        guard newCount > 0 else { return }
                        withAnimation { proxy.scrollTo(newCount - 1, anchor: .bottom) }
                    }
                }
            }

            // Barra de progresso determinada com tempo decorrido e countdown
            if session.status == .running {
                ProgressFooterView(
                    startedAt: session.startedAt,
                    agent: session.agent
                )
            }
        }
        .navigationTitle(session.question)
        .navigationSubtitle(subtitle)
        .toolbar {
            if session.status == .completed && session.reportText != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showReport = true
                    } label: {
                        Label("Report", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            if session.status == .completed {
                // Pills de fonte centralizados (posição pedida pelo usuário).
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        PillButton(systemImage: "textformat.size.smaller") {
                            fontSize = max(fontSize - 2, 10)
                        }
                        .disabled(fontSize <= 10)

                        Text("\(Int(fontSize))pt")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 32)

                        PillButton(systemImage: "textformat.size.larger") {
                            fontSize = min(fontSize + 2, 32)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showReport) {
            NavigationStack {
                ReportView(session: session)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            // Fechar explícito pedido pelo usuário (Esc também fecha).
                            Button { showReport = false } label: {
                                Label("Fechar", systemImage: "xmark.circle.fill")
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            PillButton(systemImage: "checkmark") { showReport = false }
                        }
                    }
            }
        }
    }

    private var subtitle: String {
        switch session.status {
        case .running:
            String(localized: "liveLog.status.running", bundle: .module)
        case .completed:
            String(localized: "liveLog.status.completed", bundle: .module)
        case .cancelled:
            String(localized: "liveLog.status.cancelled", bundle: .module)
        case .failed:
            String(localized: "liveLog.status.failed", bundle: .module)
        case .queued, .interrupted:
            String(localized: "liveLog.status.queued", bundle: .module)
        }
    }

    // MARK: - Split do input montado

    /// Marcadores gerados por `InteractionsClient.buildInput` — fonte única
    /// da verdade do formato do input enviado à API.
    private static let contextStartMarker = "[Contexto de arquivos locais]"
    private static let contextEndMarker = "[/Contexto]"
    private static let questionMarker = "Pergunta do usuário: "
    private static let formatInstructionStart = "Responda SEMPRE em Markdown estruturado"
    private static let formatInstructionEnd = "para termos técnicos."

    /// Separa o input montado em (pergunta, contexto). A instrução de formato
    /// é ruído interno do app e some da exibição.
    static func splitUserInput(_ text: String) -> (question: String?, context: String?) {
        var body = text[...]
        var context: String? = nil

        if let start = body.range(of: contextStartMarker),
           let end = body.range(of: contextEndMarker) {
            context = String(body[start.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            body = body[end.upperBound...]
        }

        if let marker = body.range(of: questionMarker) {
            let question = String(body[marker.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (question.isEmpty ? nil : question, context)
        }

        // Sem marcador de pergunta (pesquisa sem pasta): tira a instrução do início.
        if let instrStart = body.range(of: formatInstructionStart),
           let instrEnd = body.range(of: formatInstructionEnd) {
            body = body[instrEnd.upperBound...]
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? nil : trimmed, context)
    }

    // MARK: - Loading Animation

    private var loadingAnimation: some View {
        VStack(spacing: 20) {
            // Anel de progresso pulsante
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 4)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(pulse ? 360 : 0))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: pulse)

                Image(systemName: phaseIcon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .scaleEffect(pulse ? 1.1 : 0.9)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
            }

            VStack(spacing: 6) {
                Text(phaseText)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(String(localized: "loading.pleaseWait", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true }
    }

    private var phaseIcon: String {
        switch session.phase {
        case .planning: "brain"
        case .researching: "magnifyingglass"
        case .synthesizing: "text.magnifyingglass"
        case .none: "sparkle"
        }
    }

    private var phaseText: String {
        switch session.phase {
        case .planning: String(localized: "loading.planning", bundle: .module)
        case .researching: String(localized: "loading.researching", bundle: .module)
        case .synthesizing: String(localized: "loading.synthesizing", bundle: .module)
        case .none: String(localized: "loading.starting", bundle: .module)
        }
    }

}

// MARK: - PhaseTrailView

/// Trilha horizontal das fases: Planejando → Pesquisando → Escrevendo.
/// Fase atual destacada, passadas esmaecidas com checkmark, futuras em terciária.
private struct PhaseTrailView: View {
    let currentPhase: Phase?

    private static let allPhases: [Phase] = [.planning, .researching, .synthesizing]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(Self.allPhases.enumerated()), id: \.offset) { index, phase in
                let state = phaseState(for: phase)

                HStack(spacing: 4) {
                    if state == .past {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: phaseIcon(phase))
                            .foregroundStyle(state == .current ? Color.accentColor : .secondary)
                    }

                    Text(phase.label)
                        .font(state == .current ? .headline : .subheadline)
                        .foregroundStyle(
                            state == .current ? Color.accentColor :
                            state == .past ? Color.secondary : Color(.tertiaryLabelColor)
                        )
                }

                if index < Self.allPhases.count - 1 {
                    Image(systemName: "chevron.forward")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func phaseState(for phase: Phase) -> PhaseState {
        guard let current = currentPhase else { return .future }
        let all = Self.allPhases
        guard let currentIndex = all.firstIndex(of: current),
              let phaseIndex = all.firstIndex(of: phase) else { return .future }
        if phaseIndex < currentIndex { return .past }
        if phaseIndex == currentIndex { return .current }
        return .future
    }

    private func phaseIcon(_ phase: Phase) -> String {
        switch phase {
        case .planning: "brain"
        case .researching: "magnifyingglass"
        case .synthesizing: "text.magnifyingglass"
        }
    }

    private enum PhaseState { case past, current, future }
}

// MARK: - ProgressFooterView

/// Barra de progresso determinada com tempo decorrido e contagem regressiva.
/// Duração estimada: regular ~3 min, max ~6 min (aproximação).
private struct ProgressFooterView: View {
    let startedAt: Date
    let agent: AgentKind

    /// Ticker local: re-renderiza SÓ este rodapé a cada segundo, não a view inteira.
    @State private var now = Date()

    /// Duração estimada total da pesquisa (em segundos).
    private var estimatedDuration: TimeInterval {
        switch agent {
        case .regular: 180  // ~3 min
        case .max: 360      // ~6 min
        }
    }

    /// Tempo decorrido desde o início.
    private var elapsed: TimeInterval {
        now.timeIntervalSince(startedAt)
    }

    /// Progresso 0…1 (sem exceder 1.0).
    private var progress: Double {
        min(elapsed / estimatedDuration, 1.0)
    }

    /// Tempo restante estimado (em segundos, nunca negativo).
    private var remaining: TimeInterval {
        max(estimatedDuration - elapsed, 0)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Barra de progresso
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(progressColor)

            // Linha de tempo: elapsed ... countdown
            HStack {
                Text(elapsedText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text(countdownText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .onAppear { now = Date() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { firedAt in
            now = firedAt
        }
    }

    /// Texto do tempo decorrido: "1:23" ou "12:34"
    private var elapsedText: String {
        let totalSeconds = Int(elapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Texto da contagem regressiva: "~2:37 restantes"
    private var countdownText: String {
        if remaining < 1 {
            return String(localized: "progress.finishing", bundle: .module)
        }
        let totalSeconds = Int(ceil(remaining))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let time = String(format: "%d:%02d", minutes, seconds)
        return "~\(time) \(String(localized: "progress.remaining", bundle: .module))"
    }

    /// Cor da barra muda conforme se aproxima do fim.
    private var progressColor: Color {
        if progress >= 0.9 { return .orange }
        if progress >= 0.7 { return .yellow }
        return .blue
    }
}

// MARK: - StepRow

/// Uma linha do log: hora · ícone · texto.
private struct StepRow: View {
    let entry: StepEntry
    let fontSize: Double

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 50, alignment: .leading)

            Image(systemName: stepIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            stepContent
        }
    }

    /// model_output renderiza markdown de verdade; user_input com dump de
    /// contexto de pasta vem colapsado (o JSON inteiro poluía o log).
    @ViewBuilder private var stepContent: some View {
        if entry.type == "model_output" {
            MarkdownBlocksView(text: entry.text, fontSize: fontSize)
        } else if entry.type == "folder_context" {
            DisclosureGroup("Contexto da pasta (\(entry.text.count) caracteres)") {
                ScrollView {
                    Text(entry.text)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(.tertiary.opacity(0.1))
                .cornerRadius(8)
            }
            .font(.callout)
        } else if entry.type == "user_input" {
            // A pergunta: destaque "título de seção" — maior e semibold que o
            // corpo markdown, escalando junto com os pills A−/A+.
            Text(entry.text)
                .font(.system(size: fontSize * 1.2, weight: .semibold))
                .textSelection(.enabled)
        } else {
            // Demais entradas (thought, function_call, ...): tamanho do corpo.
            Text(entry.text)
                .font(.system(size: fontSize))
                .textSelection(.enabled)
        }
    }

    private var stepIcon: String {
        switch entry.type {
        case "model_output": "text.alignleft"
        case "thought": "brain"
        case "function_call": "arrow.right.circle"
        case "function_result": "checkmark.circle"
        case "google_search": "magnifyingglass"
        case "google_search_result": "doc.text.magnifyingglass"
        case "user_input": "arrow.up.circle"
        case "folder_context": "folder"
        default: "ellipsis.circle"
        }
    }
}

// MARK: - StatusBannerView

/// Banner mínimo para estados terminais com ações.
private struct StatusBannerView: View {
    let session: ResearchSession
    let coordinator: ResearchCoordinator

    var body: some View {
        HStack {
            Image(systemName: bannerIcon)
                .foregroundStyle(bannerColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle)
                    .font(.subheadline.bold())
                Text(bannerMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if session.status == .failed {
                Button(String(localized: "banner.retry", bundle: .module)) {
                    Task {
                        await coordinator.start(
                            question: session.question,
                            agent: session.agent
                        )
                    }
                }
                .buttonStyle(.bordered)
            }

            Button(String(localized: "banner.newResearch", bundle: .module)) {
                // Navegação para nova pesquisa tratada pelo AppShell via selection
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(bannerColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var bannerIcon: String {
        switch session.status {
        case .cancelled: "xmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "info.circle.fill"
        }
    }

    private var bannerColor: Color {
        switch session.status {
        case .cancelled: .orange
        case .failed: .red
        default: .secondary
        }
    }

    private var bannerTitle: String {
        switch session.status {
        case .cancelled: String(localized: "banner.cancelled.title", bundle: .module)
        case .failed: String(localized: "banner.failed.title", bundle: .module)
        default: String(localized: "banner.interrupted.title", bundle: .module)
        }
    }

    private var bannerMessage: String {
        switch session.status {
        case .cancelled: String(localized: "banner.cancelled.message", bundle: .module)
        case .failed: String(localized: "banner.failed.message", bundle: .module)
        default: String(localized: "banner.interrupted.message", bundle: .module)
        }
    }
}
