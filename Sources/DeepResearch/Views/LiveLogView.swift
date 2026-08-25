import SwiftUI
import SwiftData

/// Log ao vivo de uma pesquisa: banner de estado + lista de etapas + barra de progresso.
struct LiveLogView: View {
    let session: ResearchSession
    let coordinator: ResearchCoordinator

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

            // Barra de progresso indeterminada
            if session.status == .running {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }
        }
        .navigationTitle(session.question)
        .navigationSubtitle(subtitle)
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
