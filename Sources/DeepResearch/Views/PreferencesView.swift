import SwiftUI

/// Preferências do app (⌘,): API key no Keychain, agente/modelos, fonte e pasta padrão.
/// Espelho do escopo "Completo" escolhido no brainstorming.
struct PreferencesView: View {
    // MARK: - API key (Keychain)

    @State private var apiKeyInput: String = ""
    @State private var showingKey: Bool = false
    @State private var keyStatus: String = ""
    @State private var keyIsError: Bool = false

    private var keyStore: APIKeyStore { APIKeyStore() }

    // MARK: - Pesquisa padrão

    @AppStorage(AppPreferences.agentKind) private var agentKindRaw: String = AgentKind.regular.rawValue

    @AppStorage(AppPreferences.modelRegular) private var modelRegular: String = AppPreferences.defaultModelRegular
    @AppStorage(AppPreferences.modelMax) private var modelMax: String = AppPreferences.defaultModelMax

    // MARK: - Aparência

    @AppStorage(AppPreferences.logFontSize) private var logFontSize: Double = 13

    // MARK: - Contexto padrão

    @AppStorage(AppPreferences.defaultContextFolderPath) private var defaultContextFolderPath: String = ""

    var body: some View {
        Form {
            apiKeySection
            pesquisaSection
            aparenciaSection
            contextoSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 520)
        .onAppear { refreshKeyStatus() }
    }

    // MARK: - Seções

    private var apiKeySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Group {
                        if showingKey {
                            TextField("sk-… / AIza…", text: $apiKeyInput)
                        } else {
                            SecureField("sk-… / AIza…", text: $apiKeyInput)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button {
                        showingKey.toggle()
                    } label: {
                        Image(systemName: showingKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.bordered)
                    .help(showingKey ? "Ocultar" : "Mostrar")
                }

                HStack(spacing: 8) {
                    Button("Salvar no Keychain") { saveKey() }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Remover do Keychain") { removeKey() }
                        .disabled(!keyStore.hasKeyInKeychain())

                    Spacer()
                }

                if !keyStatus.isEmpty {
                    Label(keyStatus, systemImage: keyIsError ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(keyIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }

                Text("Prioridade: Keychain → `~/.local/share/opencode/auth.json` (compatibilidade). A key nunca aparece em logs.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            Label("API Key — Google Generative Language", systemImage: "key.fill")
        } footer: {
            if let source = keyStore.resolvedSource() {
                Text("Origem atual: \(source.rawValue).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nenhuma key configurada — pesquisas falharão até salvar uma key ou prover o auth.json.")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var pesquisaSection: some View {
        Section {
            Picker("Agente padrão", selection: Binding(
                get: { AgentKind(rawValue: agentKindRaw) ?? .regular },
                set: { agentKindRaw = $0.rawValue }
            )) {
                Text("Padrão").tag(AgentKind.regular)
                Text("Max — mais minucioso").tag(AgentKind.max)
            }
            .pickerStyle(.radioGroup)

            VStack(alignment: .leading, spacing: 4) {
                Text("Modelo — Padrão")
                    .font(.caption.bold())
                HStack(spacing: 8) {
                    TextField(AppPreferences.defaultModelRegular, text: $modelRegular)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                    Button("Restaurar") { modelRegular = AppPreferences.defaultModelRegular }
                        .disabled(modelRegular == AppPreferences.defaultModelRegular)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Modelo — Max")
                    .font(.caption.bold())
                HStack(spacing: 8) {
                    TextField(AppPreferences.defaultModelMax, text: $modelMax)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                    Button("Restaurar") { modelMax = AppPreferences.defaultModelMax }
                        .disabled(modelMax == AppPreferences.defaultModelMax)
                }
            }

            Button("Restaurar ambos aos padrões") {
                modelRegular = AppPreferences.defaultModelRegular
                modelMax = AppPreferences.defaultModelMax
            }
            .disabled(modelRegular == AppPreferences.defaultModelRegular && modelMax == AppPreferences.defaultModelMax)
        } header: {
            Label("Pesquisa", systemImage: "magnifyingglass")
        } footer: {
            Text("Vazio restaura o padrão. Identificadores são enviados como `agent` à Interactions API.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var aparenciaSection: some View {
        Section {
            HStack {
                Text("Tamanho do log")
                Spacer()
                Button { logFontSize = max(logFontSize - 1, 10) } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .disabled(logFontSize <= 10)
                Text("\(Int(logFontSize)) pt")
                    .font(.callout.monospacedDigit())
                    .frame(width: 56)
                Button { logFontSize = min(logFontSize + 1, 32) } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .disabled(logFontSize >= 32)
            }
            Slider(value: $logFontSize, in: 10...32, step: 1)
        } header: {
            Label("Aparência", systemImage: "textformat.size")
        }
    }

    private var contextoSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                if defaultContextFolderPath.isEmpty {
                    Text("Nenhuma — escolher a cada pesquisa")
                        .foregroundStyle(.tertiary)
                        .font(.callout)
                } else {
                    Text(URL(fileURLWithPath: defaultContextFolderPath).lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                        .help(defaultContextFolderPath)
                    Spacer()
                    Button { defaultContextFolderPath = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("Escolher…") { pickDefaultFolder() }
            }

            if !defaultContextFolderPath.isEmpty, !FileManager.default.fileExists(atPath: defaultContextFolderPath) {
                Label("Pasta não encontrada neste Mac — será ignorada.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Label("Pasta de contexto padrão", systemImage: "folder.badge.plus")
        } footer: {
            Text("Pré-selecionada ao abrir Nova pesquisa; ainda pode trocar ou remover por pesquisa.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Ações

    private func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if keyStore.saveToKeychain(trimmed) {
            apiKeyInput = ""
            showingKey = false
            keyStatus = "Salva no Keychain."
            keyIsError = false
        } else {
            keyStatus = "Falha ao salvar no Keychain."
            keyIsError = true
        }
        refreshKeyStatus(silent: true)
    }

    private func removeKey() {
        keyStore.deleteFromKeychain()
        keyStatus = "Removida do Keychain."
        keyIsError = false
        refreshKeyStatus(silent: true)
    }

    private func refreshKeyStatus(silent: Bool = false) {
        // Não sobrescreve mensagem de sucesso/erro recém-definida quando silent.
        if silent { return }
        if let source = keyStore.resolvedSource() {
            keyStatus = "Key presente (\(source.rawValue))."
            keyIsError = false
        } else {
            keyStatus = ""
        }
    }

    private func pickDefaultFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "newResearch.pickFolder", bundle: .module)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaultContextFolderPath = url.path
    }
}
