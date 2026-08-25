import SwiftData
import SwiftUI

@main
struct DeepResearchApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try AppEnvironment.makePersistentContainer()
        } catch {
            // Sem store persistente o app perde o propósito (regra: nenhuma falha descarta
            // estado) — melhor falhar alto aqui do que rodar escrevendo em memória volátil.
            // Tela de erro amigável entra junto com a janela principal (ticket 05).
            fatalError("Não foi possível abrir o banco SwiftData: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Text("DeepResearch")
                .frame(minWidth: 640, minHeight: 420)
        }
        .modelContainer(container)
    }
}
