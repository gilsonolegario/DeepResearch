import Foundation

/// Gera o conteúdo Markdown de um relatório e exporta para disco.
/// Serviço puro (só Foundation) — testável sem AppKit.
enum ExportService {

    // MARK: - Modelos

    /// Bloco atomico do relatório renderizado.
    enum Block: Sendable {
        case text(String)
        case image(Data)
    }

    // MARK: - Parse

    /// Parse do relatório em blocos de texto e imagem.
    /// Referências `![Image](...)` são mapeadas para imagens reais (por índice ou data URL)
    /// e removidas do texto exibido.
    static func buildBlocks(from markdown: String, images: [Data]) -> [Block] {
        guard !markdown.isEmpty else { return [] }
        let paragraphs = markdown.components(separatedBy: "\n\n")
        var result: [Block] = []

        for paragraph in paragraphs {
            if let block = parseImageParagraph(paragraph, images: images) {
                result.append(block)
            } else if !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.text(paragraph))
            }
        }
        return result
    }

    /// Tenta interpretar um parágrafo como referência de imagem.
    /// Procura `![Image](ref)` e mapeia ref para dados reais.
    private static func parseImageParagraph(_ text: String, images: [Data]) -> Block? {
        let prefix = "![Image]("
        let suffix = ")"
        guard text.hasPrefix(prefix), text.hasSuffix(suffix) else { return nil }

        // Extrai o conteúdo entre os parênteses
        let start = text.index(text.startIndex, offsetBy: prefix.count)
        let end = text.index(text.endIndex, offsetBy: -suffix.count)
        guard start < end else { return nil }
        let ref = String(text[start..<end])

        // image_N (com ou sem extensão) → mapear pelo índice na array de imagens
        if ref.hasPrefix("image_") {
            // Pega tudo depois de "image_" como dígito
            let numPart = String(ref.dropFirst(6))
            // Remove extensão se houver (ex: "1.png" → "1")
            let numString = numPart.components(separatedBy: ".").first ?? numPart
            if let num = Int(numString), num >= 1, num <= images.count {
                return .image(images[num - 1])
            }
        }

        // data:image/...;base64,XXX → decodificar do próprio base64
        if ref.hasPrefix("data:image/"),
           let commaIndex = ref.firstIndex(of: ","),
           let data = Data(base64Encoded: String(ref[ref.index(after: commaIndex)...])) {
            return .image(data)
        }

        return nil
    }

    // MARK: - Export

    /// Resultado da exportação.
    struct ExportResult: Sendable {
        /// Caminho do arquivo .md gerado.
        public let markdownPath: URL
    }

    /// Exporta o relatório para a pasta escolhida.
    /// Gera `relatorio.md` + subpasta `imagens/` quando há infográficos.
    @discardableResult
    static func export(
        text: String,
        images: [Data],
        to directory: URL
    ) throws -> ExportResult {
        let mdURL = directory.appendingPathComponent("relatorio.md")

        if images.isEmpty {
            try text.write(to: mdURL, atomically: true, encoding: .utf8)
            return ExportResult(markdownPath: mdURL)
        }

        // Com imagens — extrair para subpasta imagens/
        let imagensDir = directory.appendingPathComponent("imagens")
        try FileManager.default.createDirectory(
            at: imagensDir,
            withIntermediateDirectories: true
        )

        var processedMarkdown = text
        for (index, imageData) in images.enumerated() {
            let filename = safeImageFilename(index: index)
            let fileURL = imagensDir.appendingPathComponent(filename)
            try imageData.write(to: fileURL)

            // Substitui data URL pelo caminho relativo (se houver)
            let dataRef = "data:image/png;base64,\(imageData.base64EncodedString())"
            if processedMarkdown.contains(dataRef) {
                processedMarkdown = processedMarkdown.replacingOccurrences(
                    of: dataRef,
                    with: "imagens/\(filename)"
                )
            } else {
                // Insere referência com caminho relativo à subpasta imagens/
                processedMarkdown += "\n\n![Image](imagens/\(filename))"
            }
        }

        try processedMarkdown.write(to: mdURL, atomically: true, encoding: .utf8)
        return ExportResult(markdownPath: mdURL)
    }

    // MARK: - Helpers

    /// Nome de arquivo seguro para imagem (1-indexed).
    static func safeImageFilename(index: Int) -> String {
        "image_\(index + 1).png"
    }

    /// Gera o Markdown completo para copiar — imagens embutidas como data URLs
    /// para portabilidade (colável em qualquer editor markdown).
    static func fullMarkdown(text: String, images: [Data]) -> String {
        guard !images.isEmpty else { return text }
        var result = text
        for (index, imageData) in images.enumerated() {
            let ref = "![Image](image_\(index + 1))"
            let dataRef = "![Image](data:image/png;base64,\(imageData.base64EncodedString()))"
            if result.contains(ref) {
                result = result.replacingOccurrences(of: ref, with: dataRef)
            } else {
                result += "\n\n\(dataRef)"
            }
        }
        return result
    }
}
