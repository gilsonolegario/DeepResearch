import SwiftUI
import AppKit

/// Relatório renderizado: markdown via AttributedString + barra de controles pill.
struct ReportView: View {
    let session: ResearchSession

    @AppStorage("reportFontSize") private var fontSize: Double = 16
    @State private var reportContent: String = ""

    /// Blocos parseados UMA vez — reparsar a cada render travava relatórios longos.
    @State private var blocks: [ReportBlock] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .heading(let level, let markdown):
                        inlineText(markdown)
                            .font(headingFont(level))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, level == 1 ? 8 : 4)

                    case .listItem(let text):
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.system(size: fontSize))
                            inlineText(text)
                        }
                        .font(.system(size: fontSize))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    case .blockquote(let text):
                        HStack(alignment: .top, spacing: 8) {
                            Rectangle()
                                .fill(.tertiary)
                                .frame(width: 3)
                            inlineText(text)
                        }
                        .font(.system(size: fontSize))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    case .text(let markdown):
                        inlineText(markdown)
                            .font(.system(size: fontSize))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                    case .table(let header, let rows):
                        tableRender(header: header, rows: rows)

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
            // Parse único na abertura — re-parsear por render causava beachball.
            blocks = parseBlocks(reportContent)
        }
    }

    /// Renderiza inline markdown (bold, italic, code) via AttributedString.
    private func inlineText(_ markdown: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(markdown)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title.bold()
        case 2: return .title2.bold()
        case 3: return .title3.bold()
        default: return .headline.bold()
        }
    }

    /// Parse do markdown em blocos tipados — chamado UMA vez por relatório.
    private func parseBlocks(_ content: String) -> [ReportBlock] {
        guard !content.isEmpty else { return [] }
        var result: [ReportBlock] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block: ```lang ... ```
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
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

            // Heading ATX válido: 1–6 '#' seguidos de espaço ou fim da linha.
            // (a checagem antiga exigia espaço no índice exato 6 e rejeitava
            // praticamente todo heading real — por isso nada renderizava)
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                let rest = trimmed.dropFirst(hashes)
                if hashes >= 1 && hashes <= 6, rest.isEmpty || rest.hasPrefix(" ") {
                    result.append(.heading(level: hashes, rest.trimmingCharacters(in: .whitespaces)))
                    i += 1
                    continue
                }
            }

            // List item: - ...  * ...  1. ...
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ||
               (trimmed.count > 2 && trimmed.first?.isNumber == true && trimmed[trimmed.index(trimmed.startIndex, offsetBy: 1)] == ".") {
                let text: String
                if trimmed.hasPrefix("- ") {
                    text = String(trimmed.dropFirst(2))
                } else if trimmed.hasPrefix("* ") {
                    text = String(trimmed.dropFirst(2))
                } else {
                    // "1. text" — drop "N. "
                    let dotIdx = trimmed.firstIndex(of: ".")!
                    text = String(trimmed[trimmed.index(after: dotIdx)...]).trimmingCharacters(in: .whitespaces)
                }
                result.append(.listItem(text))
                i += 1
                continue
            }

            // Blockquote: > text
            if trimmed.hasPrefix("> ") {
                let text = String(trimmed.dropFirst(2))
                result.append(.blockquote(text))
                i += 1
                continue
            }

            // Table: | header | ... | (with optional |---| separator)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                var tableLines: [String] = []
                tableLines.append(trimmed)
                i += 1
                if i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).contains("---") {
                    i += 1
                }
                while i < lines.count {
                    let tl = lines[i].trimmingCharacters(in: .whitespaces)
                    if tl.hasPrefix("|") && tl.hasSuffix("|") {
                        tableLines.append(tl)
                        i += 1
                    } else { break }
                }
                if tableLines.count >= 1 {
                    let parseCells: (String) -> [String] = { line in
                        String(line.dropFirst()).dropLast().components(separatedBy: "|").map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }
                    }
                    let hdr = parseCells(tableLines[0])
                    let rows = tableLines.dropFirst().map { parseCells($0) }
                    result.append(.table(header: hdr, rows: Array(rows)))
                }
                continue
            }
            // Blank line — skip
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Regular text: group consecutive non-special lines
            var textLines: [String] = []
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("```") ||
                   l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("> ") || (l.hasPrefix("|") && l.hasSuffix("|")) ||
                   (l.count > 2 && l.first?.isNumber == true && l[l.index(l.startIndex, offsetBy: 1)] == ".") { break }
                textLines.append(lines[i])
                i += 1
            }
            if !textLines.isEmpty {
                result.append(.text(textLines.joined(separator: "\n")))
            }
        }
        return result
    }

    private enum ReportBlock: Identifiable {
        case heading(level: Int, String)
        case listItem(String)
        case blockquote(String)
        case table(header: [String], rows: [[String]])
        case text(String)
        case code(String, language: String)

        var id: Int {
            switch self {
            case .heading(_, let s): s.hashValue
            case .listItem(let s): s.hashValue
            case .blockquote(let s): s.hashValue
            case .table(_, let rows): rows.description.hashValue
            case .text(let s): s.hashValue
            case .code(let s, _): s.hashValue
            }
        }
    }

    // MARK: - Table

    private func tableRender(header: [String], rows: [[String]]) -> some View {
        let cols = header.count
        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    ForEach(0..<cols, id: \.self) { col in
                        inlineText(col < header.count ? header[col] : "")
                            .font(.system(size: fontSize - 1, weight: .bold))
                            .gridColumnAlignment(.leading)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<cols, id: \.self) { col in
                            inlineText(col < row.count ? row[col] : "")
                                .font(.system(size: fontSize - 1))
                                .gridColumnAlignment(.leading)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
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
