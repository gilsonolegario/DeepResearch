import Foundation

/// Lê a API key do Google do auth.json do opencode.
/// A key JAMAIS aparece em descrições de erro/logs — os casos de erro são
/// simbólicos e não carregam payload da key (testado em APIKeyStoreTests).
struct APIKeyStore {
    enum KeyStoreError: Error {
        /// Arquivo ausente, JSON ilegível ou campo google.key vazio/faltando.
        case keyMissing
    }

    private let authFileURL: URL

    init(authFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/opencode/auth.json")) {
        self.authFileURL = authFileURL
    }

    func loadKey() throws -> String {
        guard let data = try? Data(contentsOf: authFileURL),
              let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let google = auth["google"] as? [String: Any],
              let key = google["key"] as? String,
              !key.isEmpty
        else {
            // Sem detalhes do motivo de propósito: qualquer mensagem citaria o
            // arquivo/conteúdo e poderia vazar material sensível em logs.
            throw KeyStoreError.keyMissing
        }
        return key
    }
}
