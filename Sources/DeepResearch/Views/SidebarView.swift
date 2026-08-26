import SwiftUI
import SwiftData

/// Sidebar: seção Ativas (indicador animado) + Histórico com busca.
struct SidebarView: View {
    @Binding var selectedSessionID: PersistentIdentifier?
    @Binding var showingNewResearch: Bool
    let coordinator: ResearchCoordinator

    @Query(sort: \ResearchSession.startedAt, order: .reverse)
    private var allSessions: [ResearchSession]

    @Environment(\.modelContext) private var modelContext

    private var activeSessions: [ResearchSession] {
        allSessions.filter { !$0.status.isTerminal }
    }

    @State private var searchText = ""

    private var filteredHistory: [ResearchSession] {
        let finished = allSessions.filter { $0.status.isTerminal }
        guard !searchText.isEmpty else { return finished }
        return finished.filter {
            $0.question.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(selection: $selectedSessionID) {
            // Nova pesquisa
            Button {
                selectedSessionID = nil
                showingNewResearch = true
            } label: {
                Label(String(localized: "sidebar.newResearch", bundle: .module), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .listRowBackground(
                showingNewResearch
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )

            // Ativas
            if !activeSessions.isEmpty {
                Section(String(localized: "sidebar.section.active", bundle: .module)) {
                    ForEach(activeSessions) { session in
                        ActiveSessionRow(session: session)
                            .tag(session.persistentModelID)
                            .contextMenu {
                                deleteButton(for: session)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                deleteButton(for: session)
                            }
                    }
                }
            }

            // Histórico
            if !filteredHistory.isEmpty {
                Section(String(localized: "sidebar.section.history", bundle: .module)) {
                    ForEach(filteredHistory) { session in
                        HistorySessionRow(session: session)
                            .tag(session.persistentModelID)
                            .contextMenu {
                                deleteButton(for: session)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                deleteButton(for: session)
                            }
                    }
                }
            }
        }
        .onChange(of: selectedSessionID) { _, newValue in
            // O próprio List cuida da seleção (fonte única de verdade).
            // Havia .onTapGesture nas linhas competindo com ele: o 1º clique
            // era consumido pela seleção do List e o gesto só passava no 2º,
            // deixando o detalhe preso na Nova Pesquisa.
            if newValue != nil {
                showingNewResearch = false
            }
        }
        .navigationTitle(String(localized: "app.name", bundle: .module))
        .searchable(text: $searchText, prompt: String(localized: "sidebar.search.placeholder", bundle: .module))
    }

    // MARK: - Exclusão de sessão

    private func deleteButton(for session: ResearchSession) -> some View {
        Button(role: .destructive) {
            deleteSession(session)
        } label: {
            Label(String(localized: "sidebar.delete", bundle: .module), systemImage: "trash")
        }
    }

    private func deleteSession(_ session: ResearchSession) {
        if coordinator.isMonitoring(for: session) {
            coordinator.stopMonitoring(session: session)
        }
        if selectedSessionID == session.persistentModelID {
            selectedSessionID = nil
        }
        modelContext.delete(session)
        try? modelContext.save()
    }
}

// MARK: - ActiveSessionRow

/// Linha de sessão ativa com indicador de fase animado.
private struct ActiveSessionRow: View {
    let session: ResearchSession

    @State private var phaseOpacity: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 8, height: 8)
                    .opacity(phaseOpacity)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: phaseOpacity
                    )
                    .onAppear { phaseOpacity = 1.0 }

                Text(session.question)
                    .lineLimit(1)
                    .font(.body)
            }

            if let phase = session.phase {
                Text(phase.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var phaseColor: Color {
        switch session.phase {
        case .planning: .orange
        case .researching: .blue
        case .synthesizing: .purple
        case .none: .gray
        }
    }
}

// MARK: - HistorySessionRow

/// Linha de sessão no histórico com ícone de status.
private struct HistorySessionRow: View {
    let session: ResearchSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.caption)

                Text(session.question)
                    .lineLimit(1)
                    .font(.body)
            }

            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: String {
        switch session.status {
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .completed: .green
        case .cancelled: .orange
        case .failed: .red
        default: .gray
        }
    }
}

// MARK: - Phase helpers

extension Phase {
    var label: String {
        switch self {
        case .planning: String(localized: "phase.planning", bundle: .module)
        case .researching: String(localized: "phase.researching", bundle: .module)
        case .synthesizing: String(localized: "phase.synthesizing", bundle: .module)
        }
    }
}
