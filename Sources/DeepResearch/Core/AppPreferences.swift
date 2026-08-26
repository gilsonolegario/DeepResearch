import Foundation

/// Chaves e defaults das preferências do app.
/// Fonte única da verdade — as Views usam `@AppStorage` com estas rawValues;
/// o `InteractionsClient` lê via `UserDefaults` para não depender de SwiftUI.
enum AppPreferences {
    /// Agente padrão nas novas pesquisas (@AppStorage key já existente).
    static let agentKind = "agentKind" // AgentKind.regular

    /// Tamanho de fonte do log (@AppStorage key já existente).
    static let logFontSize = "logFontSize" // Double 13

    /// Identificador do modelo regular (editável em Preferences).
    static let modelRegular = "modelRegularIdentifier"
    static let defaultModelRegular = "deep-research-preview-04-2026"

    /// Identificador do modelo max.
    static let modelMax = "modelMaxIdentifier"
    static let defaultModelMax = "deep-research-max-preview-04-2026"

    // MARK: - Descoberta de modelos (cache híbrido)

    /// JSON `[String]` com os ids descobertos via /models.
    static let modelsCache = "modelsCache"

    /// Timestamp (Double) da última descoberta bem-sucedida.
    static let modelsCacheDate = "modelsCacheDate"

    /// Cache é considerado velho após 24 h.
    private static let cacheStaleInterval: TimeInterval = 24 * 60 * 60

    /// Fallback quando não há cache nem rede — subgrupo deep-research conhecido.
    static let fallbackModels = [
        "deep-research-preview-04-2026",
        "deep-research-max-preview-04-2026",
        "deep-research-pro-preview-12-2025",
    ]

    /// Ids em cache; nil se ausente ou ilegível.
    static func cachedModels() -> [String]? {
        guard let data = UserDefaults.standard.data(forKey: modelsCache),
              let ids = try? JSONDecoder().decode([String].self, from: data),
              !ids.isEmpty
        else { return nil }
        return ids
    }

    /// Grava o cache de ids e renova o timestamp.
    static func saveCachedModels(_ ids: [String]) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        UserDefaults.standard.set(data, forKey: modelsCache)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: modelsCacheDate)
    }

    /// true quando nunca buscou ou o cache passou de 24 h.
    static func isCacheStale() -> Bool {
        let date = UserDefaults.standard.object(forKey: modelsCacheDate) as? Double
        guard let timestamp = date else { return true }
        return Date().timeIntervalSince1970 - timestamp > cacheStaleInterval
    }

    /// Caminho da pasta padrão de contexto (vazia = nenhuma).
    static let defaultContextFolderPath = "defaultContextFolderPath"

    /// Deadline padrão em segundos (nil/0 = desabilitado). Default 15 min.
    static let defaultDeadlineSeconds = "defaultDeadlineSeconds"
    static let defaultDeadlineSecondsValue: Int = 900

    /// Resolve o identificador de modelo para o agente, respeitando Overrides
    /// do usuário em UserDefaults e caindo para o default quando vazio.
    static func modelIdentifier(for agent: AgentKind) -> String {
        let key: String
        let fallback: String
        switch agent {
        case .regular:
            key = modelRegular
            fallback = defaultModelRegular
        case .max:
            key = modelMax
            fallback = defaultModelMax
        }
        if let custom = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty
        {
            return custom
        }
        return fallback
    }
}
