import XCTest
@testable import DeepResearch

/// Parser SSE contra sequências de linhas do contrato §5.
final class SSEParserTests: XCTestCase {

    private func event(_ lines: [String]) -> SSEEvent? {
        SSEParser.parseEvent(lines)
    }

    func testSequenciaFelizProduzEventosNaOrdem() {
        let created = event([
            "event: interaction.created",
            #"data: {"interaction":{"id":"v1_abc","status":"in_progress"}}"#,
        ])
        guard case .interactionCreated(let id, let status)? = created else {
            return XCTFail("esperava interactionCreated, veio \(String(describing: created))")
        }
        XCTAssertEqual(id, "v1_abc")
        XCTAssertEqual(status, "in_progress")

        let start = event(["event: step.start", #"data: {"index":0,"step":{"type":"thought"}}"#])
        XCTAssertEqual(start, .stepStart(index: 0, stepType: "thought"))

        let delta = event(["event: step.delta", #"data: {"index":0,"delta":{"type":"text","text":"pesquisando fontes…"}}"#])
        XCTAssertEqual(delta, .stepDelta(index: 0, delta: TextDelta(text: "pesquisando fontes…")))

        let stop = event(["event: step.stop", #"data: {"index":0}"#])
        XCTAssertEqual(stop, .stepStop(index: 0))
    }

    func testEventoDesconhecidoEIgnorado() {
        XCTAssertNil(event(["event: mcp_server_tool.call", #"data: {"foo":1}"#]))
    }

    func testJSONMalformadoEIgnorado() {
        XCTAssertNil(event(["event: step.start", "data: {não é json"]))
    }

    func testSentinelaDONE() {
        XCTAssertEqual(event(["event: done", "data: [DONE]"]), .done)
        // Sem event type também é aceita — o contrato manda data: [DONE] nu.
        XCTAssertEqual(event(["data: [DONE]"]), .done)
    }

    func testLinhaSemTipoNemDataEIgnorada() {
        XCTAssertNil(event([": comentário de keep-alive"]))
    }

    func testThoughtSummaryViraTextDelta() {
        // ThoughtSummaryDelta chega como delta com texto; o app o trata como texto.
        let delta = event(["event: step.delta", #"data: {"index":2,"delta":{"type":"thought_summary","summary":[{"type":"text","text":"lendo 3 fontes"}]}}"#])
        guard case .stepDelta(let index, let deltaTexto)? = delta else {
            return XCTFail("esperava stepDelta")
        }
        XCTAssertEqual(index, 2)
        // Campo "text" ausente nesse formato vazio é tolerado sem quebrar o parse.
        _ = deltaTexto.text
    }
}
