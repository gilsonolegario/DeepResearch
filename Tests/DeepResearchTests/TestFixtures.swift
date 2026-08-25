import Foundation
import XCTest
@testable import DeepResearch

/// Carrega fixtures JSON gravadas em Tests/Fixtures/.
enum TestFixtures {
    static func load(_ name: String) throws -> Data {
        let url = fixtureDirectory().appendingPathComponent("\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            struct Missing: LocalizedError {
                let errorDescription: String?
                init(_ name: String, _ path: String) {
                    errorDescription = "fixture \(name) não encontrada em \(path)"
                }
            }
            throw Missing(name, fixtureDirectory().path)
        }
        return try Data(contentsOf: url)
    }

    private static func fixtureDirectory() -> URL {
        // SPM copia recursos declarados para o bundle de teste; fixtures ficam
        // em Tests/Fixtures e são acessadas pelo caminho do repositório via
        // #filePath (sem precisar declarar resources no Package.swift).
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/DeepResearchTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Fixtures", isDirectory: true)
    }
}

final class TestFixtureAvailabilityTests: XCTestCase {
    func testFixturesExistentesSaoCarregaveis() throws {
        for name in ["interaction-get-steps", "error-quota", "error-invalid-key", "interaction-content-tolerant"] {
            XCTAssertNoThrow(try TestFixtures.load(name), "fixture ausente: \(name)")
        }
    }
}
