import SwiftUI
import SwiftData

/// Log ao vivo de uma pesquisa: banner de estado + lista de etapas + barra de progresso.
struct LiveLogView: View {
    let session: ResearchSession
    let coordinator: ResearchCoordinator

    /// Ticker a cada segundo para atualizar a barra de progresso.
    @State private var now = Date()
    @State private var showReport = false

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

            // Lista de etapas
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(session.stepLog.enumerated()), id: \.offset) { index, entry in
                            StepRow(entry: entry)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .onChange(of: session.stepLog.count) { _, newCount in
                    guard newCount > 0 else { return }
                    withAnimation { proxy.scrollTo(newCount - 1, anchor: .bottom) }
                }
            }

            // Barra de progresso determinada com tempo decorrido e countdown
            if session.status == .running {
                ProgressFooterView(
                    startedAt: session.startedAt,
                    agent: session.agent,
                    now: now
                )
            }
        }
        .navigationTitle(session.question)
        .navigationSubtitle(subtitle)
        .toolbar {
            if session.status == .completed && session.reportText != nil {
                Button {
                    showReport = true
                } label: {
                    Label("Report", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .sheet(isPresented: $showReport) {
            NavigationStack {
                ReportView(session: session)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            PillButton(systemImage: "checkmark") { showReport = false }
                        }
                    }
            }
        }
        .onAppear {
            now = Date()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { firedAt in
            now = firedAt
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
    let now: Date

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

            Text(entry.text)
                .font(.callout)
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
