import SwiftUI
import AppKit

/// Relatório renderizado: blocos de markdown nativo intercalados com imagens inline.
/// Toolbar: copiar markdown e exportar via NSSavePanel.
struct ReportView: View {
    let session: ResearchSession

    private var reportBlocks: [ExportService.Block] {
        ExportService.buildBlocks(
            from: session.reportText ?? "",
            images: session.images
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Banner "concluída em X min"
                CompletionBanner(session: session)

                ForEach(Array(reportBlocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let markdown):
                        Text(.init(markdown))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                    case .image(let imageData):
                        if let nsImage = NSImage(data: imageData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 600)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(session.question)
        .toolbar {
            ToolbarItemGroup {
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

// MARK: - CompletionBanner

/// Banner compacto mostrando duração da pesquisa.
private struct CompletionBanner: View {
    let session: ResearchSession

    private var durationMinutes: Int {
        let start = session.startedAt
        let end = session.finishedAt ?? Date()
        return Int(end.timeIntervalSince(start) / 60)
    }

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(String(localized: "report.completedIn", defaultValue: "Concluída em \(durationMinutes) min", bundle: .module))
                .font(.subheadline.bold())

            Spacer()
        }
        .padding(10)
        .background(.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
