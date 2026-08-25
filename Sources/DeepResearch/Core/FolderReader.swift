import Foundation

/// Lê arquivos de texto de uma pasta para usar como contexto em pesquisa.
enum FolderReader {
    /// Extensões de texto aceitas (para não enviar binários).
    private static let textExtensions: Set<String> = [
        "swift", "m", "h", "cpp", "c", "rs", "py", "js", "ts", "tsx", "jsx",
        "html", "css", "scss", "json", "yaml", "yml", "toml", "xml",
        "md", "txt", "rst", "csv", "tsv", "log", "sh", "bash", "zsh",
        "fish", "sql", "graphql", "proto", "env", "gitignore", "dockerignore",
        "makefile", "cmake", "gradle", "sbt", "cabal",
    ]

    /// Tamanho máximo por arquivo (bytes). Arquivos maiores são truncados.
    private static let maxFileSize: Int = 50_000

    /// Tamanho total máximo do contexto (bytes).
    private static let maxTotalSize: Int = 200_000

    /// Máximo de arquivos lidos.
    private static let maxFileCount = 50

    /// Diretórios ignorados.
    private static let ignoredDirs: Set<String> = [
        ".git", ".build", "build", "DerivedData", "node_modules",
        ".DS_Store", "__pycache__", ".swiftformat", ".vscode",
    ]

    /// Lê o conteúdo de texto de uma pasta recursivamente.
    /// Retorna uma string formatada com o caminho relativo e conteúdo de cada arquivo.
    static func readFolder(_ url: URL) -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return "" }

        var contextParts: [String] = []
        var totalSize = 0
        var fileCount = 0

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileCount < maxFileCount else { break }

            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let dirName = fileURL.lastPathComponent
                if ignoredDirs.contains(dirName) {
                    enumerator.skipDescendants()
                }
                continue
            }

            let fileName = fileURL.lastPathComponent
            let ext = fileURL.pathExtension.lowercased()

            // Pular arquivos binários/irrelevantes.
            guard textExtensions.contains(ext) || fileName.lowercased() == "makefile" || fileName.lowercased() == "dockerfile" else {
                continue
            }

            // Ler conteúdo.
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }

            let fileSize = data.count
            guard fileSize > 0 else { continue }

            // Truncar se muito grande.
            let truncated: String
            if fileSize > maxFileSize {
                truncated = String(text.prefix(maxFileSize)) + "\n... [truncado]"
            } else {
                truncated = text
            }

            // Caminho relativo à pasta raiz.
            let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")

            totalSize += fileSize
            fileCount += 1

            contextParts.append("### \(relativePath)\n\(truncated)")

            if totalSize >= maxTotalSize {
                contextParts.append("\n... [contexto truncado: limite de \(maxTotalSize / 1000)KB atingido]")
                break
            }
        }

        return contextParts.joined(separator: "\n\n")
    }
}
