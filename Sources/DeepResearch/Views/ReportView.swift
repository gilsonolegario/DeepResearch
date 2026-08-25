import SwiftUI
import AppKit
import MarkdownEngine

/// Relatório renderizado via MarkdownEngine (code blocks, tabelas, listas).
/// Toolbar: copiar markdown, exportar via NSSavePanel, e ajuste de tamanho de fonte.
struct ReportView: View {
    let session: ResearchSession

    @AppStorage("reportFontSize") private var fontSize: Double = 16
    @State private var reportContent: String = ""

    var body: some View {
        NativeTextViewWrapper(
            text: $reportContent,
            configuration: .default,
            fontSize: fontSize,
            isEditable: false,
            placeholder: NSAttributedString(string: "")
        )
        .navigationTitle(session.question)
        .toolbar {
            ToolbarItemGroup {
                // Ajuste de fonte
                Button {
                    fontSize = max(fontSize - 2, 10)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .help(String(localized: "report.fontSmaller", bundle: .module))

                Text("\(Int(fontSize))pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32)

                Button {
                    fontSize = min(fontSize + 2, 32)
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .help(String(localized: "report.fontLarger", bundle: .module))

                Divider()

                Button {
                    copyMarkdown()
                } label: {
                    Label(
                        String(localized: "report.copyMarkdown", bundle: .module),
                        systemImage: "doc.on.doc"
                    )
                }

                Button {
                    exportToFile()
                } label: {
                    Label(
                        String(localized: "report.export", bundle: .module),
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
        }
        .onAppear {
            reportContent = session.reportText ?? ""
        }
    }

    // MARK: - Actions

    private func copyMarkdown() {
        let md = ExportService.fullMarkdown(
            text: session.reportText ?? "",
            images: session.images
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
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
