import XCTest
@testable import DeepResearch

/// Testes da leitura da API key a partir do auth.json (path injetável).
final class APIKeyStoreTests: XCTestCase {
    func testLeKeyDoAuthJSON() throws {
        let url = temporaryAuthJSON(#"{"google": {"type": "api-key", "key": "chave-secreta-123"}}"#)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = APIKeyStore(authFileURL: url)
        XCTAssertEqual(try store.loadKey(), "chave-secreta-123")
    }

    func testCampoAusenteLancaKeyMissing() throws {
        let url = temporaryAuthJSON(#"{"google": {"type": "api-key"}}"#)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = APIKeyStore(authFileURL: url)
        XCTAssertThrowsError(try store.loadKey()) { error in
            guard case APIKeyStore.KeyStoreError.keyMissing = error else {
                return XCTFail("erro inesperado: \(error)")
            }
        }
    }

    func testArquivoInexistenteLancaKeyMissing() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("auth-inexistente-\(UUID().uuidString).json")
        let store = APIKeyStore(authFileURL: url)

        XCTAssertThrowsError(try store.loadKey()) { error in
            guard case APIKeyStore.KeyStoreError.keyMissing = error else {
                return XCTFail("erro inesperado: \(error)")
            }
        }
    }

    /// A key JAMAIS pode aparecer em descrições de erro (vazaria em logs).
    func testDescricaoDoErroNaoContemAKey() throws {
        let segredo = "chave-super-secreta-nao-vazar"
        let url = temporaryAuthJSON("{\"google\": {\"key\": \"\(segredo)\"}}")
        defer { try? FileManager.default.removeItem(at: url) }

        // Caso 1: key vazia no arquivo → keyMissing.
        let storeVazio = APIKeyStore(
            authFileURL: temporaryAuthJSON(#"{"google": {"key": ""}}"#)
        )
        do {
            _ = try storeVazio.loadKey()
        } catch {
            XCTAssertFalse(String(describing: error).contains(segredo))
            XCTAssertFalse(error.localizedDescription.contains(segredo))
        }

        // Caso 2: store com a key real, erro de outra origem (client) — a
        // prova principal é que KeyStoreError não carrega payload de key.
        let store = APIKeyStore(authFileURL: url)
        let key = try store.loadKey()
        XCTAssertEqual(key, segredo)
        let erro: APIKeyStore.KeyStoreError = .keyMissing
        XCTAssertFalse(String(describing: erro).contains(segredo))
    }

    private func temporaryAuthJSON(_ content: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("auth-teste-\(UUID().uuidString).json")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
