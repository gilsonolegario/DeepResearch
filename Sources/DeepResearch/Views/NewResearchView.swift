import SwiftUI

/// Tela de nova pesquisa: TextEditor, toggle Padrão/Max, botão Pesquisar.
struct NewResearchView: View {
    let coordinator: ResearchCoordinator

    @State private var question: String = ""
    @AppStorage("agentKind") private var agentKind: AgentKind = .regular

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text(String(localized: "newResearch.title", bundle: .module))
                    .font(.title2.bold())

                Text(String(localized: "newResearch.subtitle", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextEditor(text: $question)
                    .scrollContentBackground(.visible)
                    .font(.body)
                    .frame(minHeight: 120, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if question.isEmpty {
                            Text(String(localized: "newResearch.placeholder", bundle: .module))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }

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
    }

    private func startResearch() async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await coordinator.start(question: trimmed, agent: agentKind)
        question = ""
    }
}
