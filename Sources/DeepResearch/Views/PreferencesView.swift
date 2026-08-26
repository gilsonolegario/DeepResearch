import SwiftUI

/// App preferences (⌘,): API key in Keychain, agent/models, font and default folder.
/// Mirrors the "Complete" scope chosen in brainstorming.
struct PreferencesView: View {
    // MARK: - API key (Keychain)

    @State private var apiKeyInput: String = ""
    @State private var showingKey: Bool = false
    @State private var keyStatus: String = ""
    @State private var keyIsError: Bool = false

    private var keyStore: APIKeyStore { APIKeyStore() }

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
        .onAppear { refreshKeyStatus() }
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
                HStack(spacing: 8) {
                    TextField(AppPreferences.defaultModelRegular, text: $modelRegular)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                    Button("Restore") { modelRegular = AppPreferences.defaultModelRegular }
                        .disabled(modelRegular == AppPreferences.defaultModelRegular)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model — Max")
                    .font(.caption.bold())
                HStack(spacing: 8) {
                    TextField(AppPreferences.defaultModelMax, text: $modelMax)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                    Button("Restore") { modelMax = AppPreferences.defaultModelMax }
                        .disabled(modelMax == AppPreferences.defaultModelMax)
                }
            }

            Button("Restore both to defaults") {
                modelRegular = AppPreferences.defaultModelRegular
                modelMax = AppPreferences.defaultModelMax
            }
            .disabled(modelRegular == AppPreferences.defaultModelRegular && modelMax == AppPreferences.defaultModelMax)
        } header: {
            Label("Research", systemImage: "magnifyingglass")
        } footer: {
            Text("Empty restores the default. Identifiers are sent as `agent` to the Interactions API.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
