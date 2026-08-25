import Foundation
import SwiftData

/// Monta o ambiente de dados do app (hoje: só o container SwiftData).
enum AppEnvironment {
    // Executável SwiftPM roda sem Info.plist, então não há Bundle.identifier confiável —
    // o caminho fica fixo para ser estável entre launches (a re-adoção depende disso).
    private static let bundleIdentifier = "local.issoeocio.DeepResearch"

    /// Container persistente em `~/Library/Application Support/<bundle id>/`.
    static func makePersistentContainer() throws -> ModelContainer {
        let directoryURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(bundleIdentifier, isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let storeURL = directoryURL.appendingPathComponent("DeepResearch.sqlite")
        let configuration = ModelConfiguration(url: storeURL)
        return try ModelContainer(
            for: Schema([ResearchSession.self]),
            configurations: [configuration]
        )
    }
}
