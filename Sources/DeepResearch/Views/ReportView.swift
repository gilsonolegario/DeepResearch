import SwiftUI
import AppKit

/// Relatório renderizado: markdown via AttributedString + barra de controles pill.
struct ReportView: View {
    let session: ResearchSession

    @AppStorage("reportFontSize") private var fontSize: Double = 16
    @State private var reportContent: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(reportBlocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let markdown):
                        Text(markdown)
                            .font(.system(size: fontSize))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                    case .code(let code, _):
                        Text(code)
                            .font(.system(size: fontSize - 2, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding()
            .padding(.bottom, 60)
        }
        .navigationTitle(session.question)
        .overlay(alignment: .bottom) {
            HStack(spacing: 6) {
                PillButton(systemImage: "textformat.size.smaller") {
                    fontSize = max(fontSize - 2, 10)
                }
                .disabled(fontSize <= 10)

                Text("\(Int(fontSize))pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32)

                PillButton(systemImage: "textformat.size.larger") {
                    fontSize = min(fontSize + 2, 32)
                }
                .disabled(fontSize >= 32)

                Divider()
                    .frame(height: 16)

                PillButton(systemImage: "doc.on.doc") {
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
        .onAppear {
            reportContent = session.reportText ?? ""
        }
    }

    /// Parse do markdown em blocos de texto e código.
    private var reportBlocks: [ReportBlock] {
        guard !reportContent.isEmpty else { return [] }
        var result: [ReportBlock] = []
        let lines = reportContent.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Code block: ```lang ... ```
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let lang = String(line.trimmingCharacters(in: .whitespaces).dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1 // skip closing ```
                result.append(.code(codeLines.joined(separator: "\n"), language: lang))
                continue
            }

            // Texto: agrupa linhas até blank line ou code block
            var textLines: [String] = []
            while i < lines.count {
                let l = lines[i]
                if l.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; break }
                if l.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
                textLines.append(l)
                i += 1
            }
            if !textLines.isEmpty {
                result.append(.text(textLines.joined(separator: "\n")))
            }
        }
        return result
    }

    private enum ReportBlock: Identifiable {
        case text(String)
        case code(String, language: String)

        var id: Int {
            switch self {
            case .text(let s): s.hashValue
            case .code(let s, _): s.hashValue
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
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().fill(Color.primary.opacity(isHovering ? 0.10 : 0)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .onHover { isHovering = $0 }
    }
}
