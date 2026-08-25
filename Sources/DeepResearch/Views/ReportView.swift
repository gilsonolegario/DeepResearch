import SwiftUI
import AppKit

/// View de relatório que mostra o source/texto cru (invertido da visualização anterior).
struct ReportView: View {
    let session: ResearchSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source — raw report text")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.vertical, showsIndicators: true) {
                Text(session.reportText ?? "")
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 200, maxHeight: .infinity)

            Divider()

            HStack(spacing: 6) {
                PillButton(systemImage: "square.on.square") {
                    copyMarkdown()
                }

                PillButton(systemImage: "square.and.arrow.up") {
                    exportToFile()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.10), radius: 4, y: 1)
        }
        .navigationTitle(session.question)
    }

    // MARK: - Actions

    private func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.reportText ?? "", forType: .string)
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.title = String(localized: "report.export.savePanel", bundle: .module)
        panel.nameFieldStringValue = "relatorio.md"
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let directory = url.deletingLastPathComponent()
        _ = try? ExportService.export(
            text: session.reportText ?? "",
            images: session.images,
            to: directory
        )
    }
}

// MARK: - PillButton

/// Botão pill compacto no estilo do ProjetosWiki.
struct PillButton: View {
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                // Sem contentShape, o clique só registra nos pixels desenhados
                // do glifo; aqui a área clicável vira a cápsula inteira.
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        // Camadas decorativas POR CIMA do botão: sem allowsHitTesting(false) elas
        // interceptavam o clique e a ação nunca disparava (hover acendia, clique
        // morria). Transparência NÃO desativa hit-testing em SwiftUI.
        .overlay(Capsule().foregroundColor(Color.primary.opacity(isHovering ? 0.10 : 0)).allowsHitTesting(false))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)).allowsHitTesting(false))
        .onHover { isHovering = $0 }
    }
}