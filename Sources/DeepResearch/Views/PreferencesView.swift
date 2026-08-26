import SwiftUI

/// App preferences (⌘,): API key in Keychain, agent/models, font and default folder.
/// Mirrors the "Complete" scope chosen in brainstorming.
struct PreferencesView: View {
    // MARK: - API key (Keychain)

    @State private var apiKeyInput: String = ""
    @State private var showingKey: Bool = false
    @State private var keyStatus: String = ""
    @State private var keyIsError: Bool = false

    // MARK: - Model discovery

    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelsStatus: String = ""

    private var keyStore: APIKeyStore { APIKeyStore() }

    /// Sem key não há como descobrir modelos — só cache/fallback.
    private var hasAPIKey: Bool { keyStore.resolvedSource() != nil }

    /// Subgrupo válido para a API Interactions vem primeiro.
    private var deepResearchModels: [String] {
        availableModels.filter { $0.contains("deep-research") }.sorted()
    }

    private var otherModels: [String] {
        availableModels.filter { !$0.contains("deep-research") }.sorted()
    }

    // MARK: - Default research

    @AppStorage(AppPreferences.agentKind) private var agentKindRaw: String = AgentKind.regular.rawValue

    @AppStorage(AppPreferences.modelRegular) private var modelRegular: String = AppPreferences.defaultModelRegular
    @AppStorage(AppPreferences.modelMax) private var modelMax: String = AppPreferences.defaultModelMax

    // MARK: - Appearance

    @AppStorage(AppPreferences.logFontSize) private var logFontSize: Double = 13

    @AppStorage(AppPreferences.defaultDeadlineSeconds) private var defaultDeadlineSeconds: Int = AppPreferences.defaultDeadlineSecondsValue

    // MARK: - Default context

    @AppStorage(AppPreferences.defaultContextFolderPath) private var defaultContextFolderPath: String = ""

    var body: some View {
        Form {
            apiKeySection
            researchSection
            deadlineSection
            appearanceSection
            contextSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .onAppear {
            refreshKeyStatus()
            loadModelsIfNeeded()
        }
    }

    // MARK: - Sections

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
                    .help(showingKey ? "Hide" : "Show")
                }

                HStack(spacing: 8) {
                    Button("Save to Keychain") { saveKey() }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Remove from Keychain") { removeKey() }
                        .disabled(!keyStore.hasKeyInKeychain())

                    Spacer()
                }

                if !keyStatus.isEmpty {
                    Label(keyStatus, systemImage: keyIsError ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(keyIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }

                Text("Priority: Keychain → `~/.local/share/opencode/auth.json` (compatibility). The key never appears in logs.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            Label("API Key — Google Generative Language", systemImage: "key.fill")
        } footer: {
            if let source = keyStore.resolvedSource() {
                Text("Current source: \(source.rawValue).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No key configured — research will fail until you save a key or provide auth.json.")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var researchSection: some View {
        Section {
            Picker("Default agent", selection: Binding(
                get: { AgentKind(rawValue: agentKindRaw) ?? .regular },
                set: { agentKindRaw = $0.rawValue }
            )) {
                Text("Regular").tag(AgentKind.regular)
                Text("Max — more thorough").tag(AgentKind.max)
            }
            .pickerStyle(.radioGroup)

            VStack(alignment: .leading, spacing: 4) {
                Text("Model — Regular")
                    .font(.caption.bold())
                modelField(modelID: $modelRegular, defaultID: AppPreferences.defaultModelRegular)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model — Max")
                    .font(.caption.bold())
                modelField(modelID: $modelMax, defaultID: AppPreferences.defaultModelMax)
            }

            HStack(spacing: 8) {
                Button("Restore both to defaults") {
                    modelRegular = AppPreferences.defaultModelRegular
                    modelMax = AppPreferences.defaultModelMax
                }
                .disabled(modelRegular == AppPreferences.defaultModelRegular && modelMax == AppPreferences.defaultModelMax)

                Button {
                    fetchModels()
                } label: {
                    if isLoadingModels {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh models", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isLoadingModels || !hasAPIKey)

                if !modelsStatus.isEmpty {
                    Text(modelsStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Research", systemImage: "magnifyingglass")
        } footer: {
            Text("Empty restores the default. Identifiers are sent as `agent` to the Interactions API. Only deep-research* models work as agents; other entries are listed for reference.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Campo de modelo: TextField manual + Menu "Browse…" com os modelos descobertos.
    private func modelField(modelID: Binding<String>, defaultID: String) -> some View {
        HStack(spacing: 8) {
            TextField(defaultID, text: modelID)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
            badge(for: modelID.wrappedValue)

            Menu {
                Section("Deep research") {
                    ForEach(deepResearchModels, id: \.self) { id in
                        Button(id) { modelID.wrappedValue = id }
                    }
                }
                Section("Other models") {
                    ForEach(otherModels, id: \.self) { id in
                        Button(id) { modelID.wrappedValue = id }
                    }
                }
            } label: {
                Label("Browse…", systemImage: "list.bullet")
            }
            .fixedSize()
            .disabled(availableModels.isEmpty)

            Button("Restore") { modelID.wrappedValue = defaultID }
                .disabled(modelID.wrappedValue == defaultID)
        }
    }

    @ViewBuilder
    private func badge(for modelID: String) -> some View {
        let text = badgeText(for: modelID)
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(badgeColor(for: modelID).opacity(0.15)))
            .foregroundStyle(badgeColor(for: modelID))
            .help(text == "Limited" ? "Preview agent — may hit quota faster." : "")
    }

    private func badgeText(for modelID: String) -> String {
        if modelID.contains("deep-research") { return "Limited" }
        if modelID.contains("-flash-lite") || modelID.hasPrefix("gemma") { return "Free tier" }
        return "Billing"
    }

    private func badgeColor(for modelID: String) -> Color {
        switch badgeText(for: modelID) {
        case "Limited": return .orange
        case "Free tier": return .green
        default: return .gray
        }
    }

    private var deadlineSection: some View {
        Section {
            Picker("Default timeout", selection: $defaultDeadlineSeconds) {
                Text("5 min").tag(300)
                Text("15 min (recommended)").tag(900)
                Text("30 min").tag(1800)
                Text("1 hour").tag(3600)
                Text("No timeout").tag(0)
            }
            .pickerStyle(.segmented)
            // segmented Picker clips if too many items — keep 5, no Default label here (default IS 15m)
        } header: {
            Label("Default deadline", systemImage: "timer")
        } footer: {
            Text("Applies to new research when no per-question deadline is chosen. Watchdog only triggers when no progress beyond the question.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var appearanceSection: some View {
        Section {
            HStack {
                Text("Log font size")
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
            Label("Appearance", systemImage: "textformat.size")
        }
    }

    private var contextSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                if defaultContextFolderPath.isEmpty {
                    Text("None — choose per research")
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
                Button("Choose…") { pickDefaultFolder() }
            }

            if !defaultContextFolderPath.isEmpty, !FileManager.default.fileExists(atPath: defaultContextFolderPath) {
                Label("Folder not found on this Mac — will be ignored.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Label("Default context folder", systemImage: "folder.badge.plus")
        } footer: {
            Text("Pre-selected when opening New Research; you can still change or clear it per research.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if keyStore.saveToKeychain(trimmed) {
            apiKeyInput = ""
            showingKey = false
            keyStatus = "Saved to Keychain."
            keyIsError = false
        } else {
            keyStatus = "Failed to save to Keychain."
            keyIsError = true
        }
        refreshKeyStatus(silent: true)
    }

    private func removeKey() {
        keyStore.deleteFromKeychain()
        keyStatus = "Removed from Keychain."
        keyIsError = false
        refreshKeyStatus(silent: true)
    }

    private func refreshKeyStatus(silent: Bool = false) {
        if silent { return }
        if let source = keyStore.resolvedSource() {
            keyStatus = "Key present (\(source.rawValue))."
            keyIsError = false
        } else {
            keyStatus = ""
        }
    }

    // MARK: - Model discovery

    /// Carrega o cache na hora; se estiver velho (ou vazio) e houver key, busca na API.
    private func loadModelsIfNeeded() {
        availableModels = AppPreferences.cachedModels() ?? AppPreferences.fallbackModels
        guard AppPreferences.isCacheStale() else { return }
        fetchModels()
    }

    private func fetchModels() {
        guard hasAPIKey, !isLoadingModels else { return }
        isLoadingModels = true
        modelsStatus = ""
        let client = URLSessionInteractionsClient(apiKeyProvider: { try APIKeyStore().loadKey() })
        Task {
            do {
                let infos = try await client.listModels()
                let ids = infos.map(\.id)
                AppPreferences.saveCachedModels(ids)
                availableModels = ids
                // deep-research primeiro no Menu — se nenhum veio, mostra tudo como referência.
                modelsStatus = "\(infos.filter(\.isDeepResearch).count) research model(s) found."
            } catch {
                modelsStatus = "Could not load models (\(error.localizedDescription)). Showing cached/fallback list."
            }
            isLoadingModels = false
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
