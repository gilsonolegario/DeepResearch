import SwiftUI
import SwiftData

/// Tela de nova pesquisa: TextEditor, toggle Padrão/Max, seletor de pasta, botão Pesquisar.
struct NewResearchView: View {
    let coordinator: ResearchCoordinator
    @Binding var selectedSessionID: PersistentIdentifier?
    @Binding var showingNewResearch: Bool

    @State private var question: String = ""
    @State private var contextURL: URL? = nil
    @AppStorage("agentKind") private var agentKind: AgentKind = .regular
    @AppStorage(AppPreferences.defaultContextFolderPath) private var defaultContextFolderPath: String = ""
    @AppStorage(AppPreferences.defaultDeadlineSeconds) private var defaultDeadlineSeconds: Int = AppPreferences.defaultDeadlineSecondsValue
    @State private var deadlineSeconds: Int? = nil
    @FocusState private var isFocused: Bool
    @Environment(\.modelContext) private var modelContext

    /// Aplica a pasta padrão salva em Preferences quando a view aparece
    /// (se existir em disco e ainda não houver contexto escolhido).
    private func applyDefaultContextIfNeeded() {
        guard contextURL == nil, !defaultContextFolderPath.isEmpty else { return }
        let url = URL(fileURLWithPath: defaultContextFolderPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        contextURL = url
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                appIcon
                    .frame(width: 96, height: 96)

                Text(String(localized: "newResearch.title", bundle: .module))
                    .font(.title2.bold())

                Text(String(localized: "newResearch.subtitle", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextEditor(text: $question)
                    .scrollContentBackground(.visible)
                    .font(.body)
                    .padding(8)
                    .frame(minHeight: 120, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .focused($isFocused)
                    .overlay(alignment: .topLeading) {
                        if question.isEmpty && !isFocused {
                            Text(String(localized: "newResearch.placeholder", bundle: .module))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }

                // Context folder picker
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    if let url = contextURL {
                        Text(url.lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            contextURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(String(localized: "newResearch.addContext", bundle: .module))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button {
                            pickFolder()
                        } label: {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 500)

                HStack(spacing: 12) {
                    Label("Deadline", systemImage: "timer")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $deadlineSeconds) {
                        Text("Default (15m)").tag(nil as Int?)
                        Text("5 min").tag(300 as Int?)
                        Text("15 min").tag(900 as Int?)
                        Text("30 min").tag(1800 as Int?)
                        Text("1 hour").tag(3600 as Int?)
                        Text("No timeout").tag(0 as Int?)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                    Spacer()
                }
                .frame(maxWidth: 500)

                HStack {
                    Toggle(String(localized: "newResearch.agentMax", bundle: .module), isOn: Binding(
                        get: { agentKind == .max },
                        set: { agentKind = $0 ? .max : .regular }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Spacer()

                    Button {
                        Task { await startResearch() }
                    } label: {
                        Label(String(localized: "newResearch.start", bundle: .module), systemImage: "arrow.up.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .frame(maxWidth: 500)
            }
            .padding(32)

            Spacer()
        }
        .onAppear { applyDefaultContextIfNeeded() }
        .onChange(of: defaultContextFolderPath) { _, _ in applyDefaultContextIfNeeded() }
    }

    @ViewBuilder private var appIcon: some View {
        if let url = Bundle.module.url(forResource: "AppIconInternal", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        } else {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "newResearch.pickFolder", bundle: .module)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        contextURL = url
    }

    private func startResearch() async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Read folder context if selected.
        let context: String? = contextURL.map { FolderReader.readFolder($0) }
        // nil in picker = "Default" → respect Preferences default
        let effectiveDeadline: Int? = deadlineSeconds ?? defaultDeadlineSeconds

        await coordinator.start(question: trimmed, agent: agentKind, context: context, deadlineSeconds: effectiveDeadline)
        question = ""
        contextURL = nil

        // Navega para a sessão mais recente recém-criada.
        let descriptor = FetchDescriptor<ResearchSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        if let latest = try? modelContext.fetch(descriptor).first {
            selectedSessionID = latest.persistentModelID
            showingNewResearch = false
        }
    }
}
