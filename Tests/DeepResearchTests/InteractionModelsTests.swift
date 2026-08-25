import XCTest
@testable import DeepResearch

/// Testes de parsing dos modelos de rede contra fixtures reais da API.
final class InteractionModelsTests: XCTestCase {
    private func fixtureData(_ name: String) throws -> Data {
        try TestFixtures.load(name)
    }

    func testParseGetComStepsVariados() throws {
        let data = try fixtureData("interaction-get-steps")
        let interaction = try JSONDecoder().decode(Interaction.self, from: data)

        XCTAssertEqual(interaction.id, "v1_abc123def456")
        XCTAssertEqual(interaction.status, .completed)
        XCTAssertEqual(interaction.agent, "deep-research-preview-04-2026")

        // Steps variados: um de cada tipo conhecido + um desconhecido (tolerância).
        XCTAssertEqual(interaction.steps.count, 7)

        guard case .modelOutput(let output) = interaction.steps[0] else {
            return XCTFail("step 0 deveria ser model_output, foi \(interaction.steps[0])")
        }
        XCTAssertTrue(output.contains {
            if case .text(let text) = $0 { return text == "Pesquisando o tema solicitado..." }
            return false
        })

        guard case .thought = interaction.steps[1] else {
            return XCTFail("step 1 deveria ser thought, foi \(interaction.steps[1])")
        }

        guard case .functionCall(let call) = interaction.steps[2] else {
            return XCTFail("step 2 deveria ser function_call, foi \(interaction.steps[2])")
        }
        XCTAssertEqual(call.name, "google_search")

        guard case .functionResult(let result) = interaction.steps[3] else {
            return XCTFail("step 3 deveria ser function_result, foi \(interaction.steps[3])")
        }
        XCTAssertFalse(result.isError)

        guard case .googleSearchCall = interaction.steps[4] else {
            return XCTFail("step 4 deveria ser google_search, foi \(interaction.steps[4])")
        }

        guard case .googleSearchResult = interaction.steps[5] else {
            return XCTFail("step 5 deveria ser google_search_result, foi \(interaction.steps[5])")
        }

        guard case .userInput(let input) = interaction.steps[6] else {
            return XCTFail("step 6 deveria ser user_input, foi \(interaction.steps[6])")
        }
        XCTAssertTrue(input.contains {
            if case .text(let text) = $0 { return text == "qual a capital do Brasil?" }
            return false
        })
    }

    func testParseStatusDesconhecidoCaiNoFallback() throws {
        let json = #"{"id": "v1_x", "status": "teleported", "steps": []}"#.data(using: .utf8)!
        let interaction = try JSONDecoder().decode(Interaction.self, from: json)

        XCTAssertEqual(interaction.status, .unknown)
    }

    func testParseStatusAusenteViraUnknown() throws {
        let json = #"{"id": "v1_x", "steps": []}"#.data(using: .utf8)!
        let interaction = try JSONDecoder().decode(Interaction.self, from: json)

        XCTAssertEqual(interaction.status, .unknown)
    }

    func testContentImagemBase64() throws {
        let json = #"""
        {"id": "v1_img", "status": "completed",
         "steps": [{"type": "model_output", "content": [
             {"type": "image", "data": "aW1n", "mime_type": "image/png"}
         ]}]}
        """#.data(using: .utf8)!
        let interaction = try JSONDecoder().decode(Interaction.self, from: json)

        guard case .modelOutput(let content) = interaction.steps[0],
              case .image(let image) = content.first
        else {
            return XCTFail("deveria decodificar imagem em model_output")
        }
        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertEqual(image.base64Data, "aW1n")
    }
}
