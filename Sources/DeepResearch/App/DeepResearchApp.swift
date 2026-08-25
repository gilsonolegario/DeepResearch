import SwiftData
import SwiftUI

@main
struct DeepResearchApp: App {
    private let container: ModelContainer
    /// Instância única: o coordinator guarda Tasks de monitoramento e estado
    /// observável — criar por view duplicaria tudo (bug evitado de propósito).
    private let coordinator: ResearchCoordinator
    @State private var presenceManager: PresenceManager
    @State private var dockTimer: Timer?

    init() {
        do {
            container = try AppEnvironment.makePersistentContainer()
        } catch {
            // Sem store persistente o app perde o propósito (regra: nenhuma falha descarta
            // estado) — melhor falhar alto aqui do que rodar escrevendo em memória volátil.
            fatalError("Não foi possível abrir o banco SwiftData: \(error)")
        }
        let keyStore = APIKeyStore()
        coordinator = ResearchCoordinator(
            client: URLSessionInteractionsClient(apiKeyProvider: { try keyStore.loadKey() }),
            modelContext: ModelContext(container)
        )
        presenceManager = PresenceManager(coordinator: coordinator)
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(coordinator: coordinator)
                .modelContainer(container)
                .onAppear {
                    dockTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                        Task { @MainActor in
                            presenceManager.tick()
                        }
                    }
                }
                .onDisappear {
                    dockTimer?.invalidate()
                    dockTimer = nil
                }
        }
        .defaultSize(width: 960, height: 640)
    }
}
