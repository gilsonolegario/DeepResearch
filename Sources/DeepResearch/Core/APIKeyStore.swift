import Foundation

/// Lê a API key do Google em cadeia: Keychain → auth.json do opencode.
/// O Keychain é a fonte primária configurável em Preferences (⌘,); o arquivo
/// existe só para compatibilidade com quem já usa opencode na mesma máquina.
/// A key JAMAIS aparece em descrições de erro/logs — os casos de erro são
/// simbólicos e não carregam payload da key (testado em APIKeyStoreTests).
struct APIKeyStore {
    enum KeyStoreError: Error {
        /// Arquivo ausente, JSON ilegível ou campo google.key vazio/faltando.
        case keyMissing
    }

    /// Origem da key entregue por `loadKey()` — só para exibição na UI.
    enum KeySource: String {
        case keychain = "Keychain"
        case authFile = "auth.json"
    }

    static let keychainService = "local.issoeocio.DeepResearch"
    static let keychainAccount = "google-api-key"

    private let authFileURL: URL
    private let useKeychain: Bool

    init(authFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/opencode/auth.json"),
         useKeychain: Bool = true) {
        self.authFileURL = authFileURL
        self.useKeychain = useKeychain
    }

    /// Keychain primeiro; se não houver, tenta o arquivo. Ordem fixa e documentada.
    /// Quando `useKeychain == false` (testes), só o arquivo é consultado.
    func loadKey() throws -> String {
        if useKeychain,
           let fromKeychain = KeychainHelper.load(service: Self.keychainService, account: Self.keychainAccount),
           !fromKeychain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return fromKeychain
        }
        if let fromFile = try? loadKeyFromFile() { return fromFile }
        throw KeyStoreError.keyMissing
    }

    /// De onde a key veio (nil se não houver). Útil para o rodapé do Preferences.
    func resolvedSource() -> KeySource? {
        if useKeychain,
           let k = KeychainHelper.load(service: Self.keychainService, account: Self.keychainAccount),
           !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .keychain }
        if (try? loadKeyFromFile()) != nil { return .authFile }
        return nil
    }

    func hasKeyInKeychain() -> Bool {
        guard useKeychain else { return false }
        return KeychainHelper.load(service: Self.keychainService, account: Self.keychainAccount) != nil
    }

    @discardableResult
    func saveToKeychain(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return KeychainHelper.save(trimmed, service: Self.keychainService, account: Self.keychainAccount)
    }

    @discardableResult
    func deleteFromKeychain() -> Bool {
        KeychainHelper.delete(service: Self.keychainService, account: Self.keychainAccount)
    }

    // MARK: - Fallback de arquivo

    private func loadKeyFromFile() throws -> String {
        guard let data = try? Data(contentsOf: authFileURL),
              let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let google = auth["google"] as? [String: Any],
              let key = google["key"] as? String,
              !key.isEmpty
        else {
            throw KeyStoreError.keyMissing
        }
        return key
    }
}
