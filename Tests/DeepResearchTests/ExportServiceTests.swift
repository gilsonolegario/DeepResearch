import XCTest
@testable import DeepResearch

/// Testes do ExportService: parse de blocos, exportação e geração de markdown.
final class ExportServiceTests: XCTestCase {

    // MARK: - buildBlocks

    func testTextoPuroSemImagens() {
        let markdown = "Primeiro parágrafo.\n\nSegundo parágrafo."
        let blocks = ExportService.buildBlocks(from: markdown, images: [])

        XCTAssertEqual(blocks.count, 2)
        if case .text(let text) = blocks[0] {
            XCTAssertEqual(text, "Primeiro parágrafo.")
        } else {
            XCTFail("Esperado bloco de texto")
        }
        if case .text(let text) = blocks[1] {
            XCTAssertEqual(text, "Segundo parágrafo.")
        } else {
            XCTFail("Esperado bloco de texto")
        }
    }

    func testMarkdownVazio() {
        let blocks = ExportService.buildBlocks(from: "", images: [])
        XCTAssertTrue(blocks.isEmpty)
    }

    func testImagemPorIndice() {
        let image1 = Data(repeating: 0xAA, count: 10)
        let image2 = Data(repeating: 0xBB, count: 20)
        let markdown = "Texto antes.\n\n![Image](image_1)\n\nTexto depois.\n\n![Image](image_2)"
        let blocks = ExportService.buildBlocks(from: markdown, images: [image1, image2])

        XCTAssertEqual(blocks.count, 4)

        if case .text(let t) = blocks[0] { XCTAssertEqual(t, "Texto antes.") }
        else { XCTFail("Bloco 0 deveria ser texto") }

        if case .image(let data) = blocks[1] { XCTAssertEqual(data, image1) }
        else { XCTFail("Bloco 1 deveria ser imagem") }

        if case .text(let t) = blocks[2] { XCTAssertEqual(t, "Texto depois.") }
        else { XCTFail("Bloco 2 deveria ser texto") }

        if case .image(let data) = blocks[3] { XCTAssertEqual(data, image2) }
        else { XCTFail("Bloco 3 deveria ser imagem") }
    }

    func testImagemDataUrl() {
        let imageData = Data(repeating: 0xCC, count: 5)
        let base64 = imageData.base64EncodedString()
        let markdown = "Antes.\n\n![Image](data:image/png;base64,\(base64))\n\nDepois."
        let blocks = ExportService.buildBlocks(from: markdown, images: [])

        XCTAssertEqual(blocks.count, 3)

        if case .text(let t) = blocks[0] { XCTAssertEqual(t, "Antes.") }
        else { XCTFail("Bloco 0 deveria ser texto") }

        if case .image(let data) = blocks[1] { XCTAssertEqual(data, imageData) }
        else { XCTFail("Bloco 1 deveria ser imagem data URL") }

        if case .text(let t) = blocks[2] { XCTAssertEqual(t, "Depois.") }
        else { XCTFail("Bloco 2 deveria ser texto") }
    }

    func testIndiceForaDoRangeIgnorado() {
        let markdown = "![Image](image_99)"
        let blocks = ExportService.buildBlocks(from: markdown, images: [Data([0xAA])])

        // image_99 não existe na array → fica como texto (sem correspondência)
        XCTAssertEqual(blocks.count, 1)
        if case .text(let t) = blocks[0] {
            XCTAssertTrue(t.contains("image_99"))
        } else {
            XCTFail("Índice fora do range deveria virar texto")
        }
    }

    // MARK: - safeImageFilename

    func testSafeImageFilename() {
        XCTAssertEqual(ExportService.safeImageFilename(index: 0), "image_1.png")
        XCTAssertEqual(ExportService.safeImageFilename(index: 4), "image_5.png")
    }

    // MARK: - fullMarkdown

    func testFullMarkdownSemImagens() {
        let text = "Relatório simples."
        let result = ExportService.fullMarkdown(text: text, images: [])
        XCTAssertEqual(result, text)
    }

    func testFullMarkdownComImagens() {
        let image1 = Data(repeating: 0xDD, count: 8)
        let text = "![Image](image_1)"
        let result = ExportService.fullMarkdown(text: text, images: [image1])

        XCTAssertTrue(result.contains("data:image/png;base64,"))
        XCTAssertFalse(result.contains("![Image](image_1)"), "Referência deveria ter sido substituída por data URL")
        XCTAssertFalse(result.contains("imagens/"))
    }

    func testFullMarkdownInsereReferenciaFaltante() {
        let image1 = Data(repeating: 0xEE, count: 4)
        let text = "Sem imagem referenciada."
        let result = ExportService.fullMarkdown(text: text, images: [image1])

        XCTAssertTrue(result.contains("data:image/png;base64,"))
        XCTAssertTrue(result.contains("![Image](data:image/png;base64,"))
        XCTAssertTrue(result.hasSuffix(")"))
    }

    // MARK: - export (disco)

    func testExportSemImagens() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let text = "Relatório de teste.\n\nSegundo parágrafo."
        let result = try ExportService.export(text: text, images: [], to: tmp)

        // relatorio.md existe
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.markdownPath.path))
        let content = try String(contentsOf: result.markdownPath, encoding: .utf8)
        XCTAssertEqual(content, text)

        // Sem subpasta imagens
        let imagensDir = tmp.appendingPathComponent("imagens")
        XCTAssertFalse(FileManager.default.fileExists(atPath: imagensDir.path))
    }

    func testExportComImagens() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-img-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let image1 = Data(repeating: 0xFF, count: 16)
        let image2 = Data(repeating: 0x00, count: 32)
        let text = "Primeira parte.\n\n![Image](image_1)\n\nSegunda parte.\n\n![Image](image_2)"
        let result = try ExportService.export(text: text, images: [image1, image2], to: tmp)

        // relatorio.md existe
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.markdownPath.path))

        // Subpasta imagens criada
        let imagensDir = tmp.appendingPathComponent("imagens")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagensDir.path))

        // Dois arquivos de imagem
        let image1URL = imagensDir.appendingPathComponent("image_1.png")
        let image2URL = imagensDir.appendingPathComponent("image_2.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: image1URL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: image2URL.path))

        // Conteúdo dos arquivos confere
        XCTAssertEqual(try Data(contentsOf: image1URL), image1)
        XCTAssertEqual(try Data(contentsOf: image2URL), image2)

        // Markdown referencia imagens como caminhos relativos
        let mdContent = try String(contentsOf: result.markdownPath, encoding: .utf8)
        XCTAssertTrue(mdContent.contains("![Image](imagens/image_1.png)"), "Referência deveria apontar para pasta imagens/")
        XCTAssertTrue(mdContent.contains("![Image](imagens/image_2.png)"), "Referência deveria apontar para pasta imagens/")
        XCTAssertFalse(mdContent.contains("base64"))
    }

    func testExportComImagensDataUrl() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-dataurl-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let imageData = Data(repeating: 0xAB, count: 12)
        let base64 = imageData.base64EncodedString()
        let text = "Texto.\n\n![Image](data:image/png;base64,\(base64))"
        let result = try ExportService.export(text: text, images: [imageData], to: tmp)

        // Imagem extraída
        let imagensDir = tmp.appendingPathComponent("imagens")
        let imageFile = imagensDir.appendingPathComponent("image_1.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageFile.path))
        XCTAssertEqual(try Data(contentsOf: imageFile), imageData)

        // Markdown não contém mais data URL
        let mdContent = try String(contentsOf: result.markdownPath, encoding: .utf8)
        XCTAssertFalse(mdContent.contains("base64"))
        XCTAssertTrue(mdContent.contains("imagens/image_1.png"))
    }
}
