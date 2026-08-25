import SwiftUI
import SwiftData

/// Shell principal: NavigationSplitView com sidebar + detalhe.
/// A seleção da sidebar alimenta a área de detalhe.
struct AppShellView: View {
    let coordinator: ResearchCoordinator
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSessionID: PersistentIdentifier?
    @State private var showingNewResearch = true

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedSessionID: $selectedSessionID,
                showingNewResearch: $showingNewResearch,
                coordinator: coordinator
            )
        } detail: {
            if showingNewResearch {
                NewResearchView(
                    coordinator: coordinator,
                    selectedSessionID: $selectedSessionID,
                    showingNewResearch: $showingNewResearch
                )
            } else if let id = selectedSessionID,
                      let session = modelContext.model(for: id) as? ResearchSession {
                LiveLogView(session: session, coordinator: coordinator)
            } else {
                ContentUnavailableView(
                    String(localized: "sidebar.selectSession", bundle: .module),
                    systemImage: "sidebar.left",
                    description: Text(String(localized: "sidebar.selectSession.description", bundle: .module))
                )
            }
        }
        .frame(minWidth: 740, minHeight: 480)
        .task {
            await coordinator.adoptPendingSessions()
        }
    }
}
