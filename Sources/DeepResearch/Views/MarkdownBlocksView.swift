import SwiftUI

/// Renderiza texto markdown em blocos (headings, listas, quotes, tabelas, código).
/// Compartilhado entre ReportView e as linhas do log ao vivo (StepRow).
/// Conforma Equatable: sem mudança em text/fontSize, o SwiftUI pula o body
/// e NÃO re-parseia o markdown inteiro (parse era refeito a cada render).
struct MarkdownBlocksView: View, Equatable {
    let text: String
    let fontSize: Double

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.fontSize == rhs.fontSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let markdown):
                    inlineText(markdown)
                        .font(headingFont(level))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, level == 1 ? 6 : 3)

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

                case .table(let header, let rows):
                    tableRender(header: header, rows: rows)

                case .code(let code, _):
                    Text(code)
                        .font(.system(size: fontSize - 2, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                case .text(let markdown):
                    inlineText(markdown)
                        .font(.system(size: fontSize))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Parsing

    private var blocks: [ReportBlock] {
        parseBlocks(text)
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
        // Usa o fontSize compartilhado se disponível; fallback para títulos do sistema
        if level == 1 { return .system(size: fontSize * 1.5, weight: .bold) }
        if level == 2 { return .system(size: fontSize * 1.3, weight: .bold) }
        if level == 3 { return .system(size: fontSize, weight: .bold) }
        return .system(size: fontSize * 0.85, weight: .bold)
    }

    /// Comprimento do prefixo "N. " (lista numerada) ou nil se não for.
    /// Aceita multi-dígito (10., 42.) — a checagem antiga só olhava o índice 1
    /// e tratava itens 10+ como parágrafo comum.
    private func numberedListPrefixLength(_ s: String) -> Int? {
        let digits = s.prefix(while: { $0.isNumber }).count
        guard digits >= 1, digits <= 3, s.count > digits + 1 else { return nil }
        let dotIndex = s.index(s.startIndex, offsetBy: digits)
        let spaceIndex = s.index(after: dotIndex)
        return s[dotIndex] == "." && s[spaceIndex] == " " ? digits + 2 : nil
    }

    /// Parse do markdown em blocos tipados.
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
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                let rest = trimmed.dropFirst(hashes)
                if hashes >= 1 && hashes <= 6, rest.isEmpty || rest.hasPrefix(" ") {
                    result.append(.heading(level: hashes, rest.trimmingCharacters(in: .whitespaces)))
                    i += 1
                    continue
                }
            }

            // List item numerado: "N. texto" (aceita multi-dígito: 10., 42., …)
            if let prefixLen = numberedListPrefixLength(trimmed) {
                result.append(.listItem(String(trimmed.dropFirst(prefixLen))))
                i += 1
                continue
            }

            // List item com marcador: - ou *
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                result.append(.listItem(String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            // Blockquote: > text
            if trimmed.hasPrefix("> ") {
                result.append(.blockquote(String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            // Table: | header | ... | (com separador |---| opcional)
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
                   numberedListPrefixLength(l) != nil { break }
                textLines.append(lines[i])
                i += 1
            }
            if !textLines.isEmpty {
                result.append(.text(textLines.joined(separator: "\n")))
            }
        }
        return result
    }

    private enum ReportBlock: Identifiable, Equatable {
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
}
