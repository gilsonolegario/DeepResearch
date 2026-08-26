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
