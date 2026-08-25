import XCTest
@testable import DeepResearch

final class ResearchSessionTests: XCTestCase {
    func testSessaoNovaComecaNaFilaSemInteractionID() {
        let session = ResearchSession(question: "pergunta de teste")

        XCTAssertEqual(session.status, .queued)
        XCTAssertNil(session.interactionID)
        XCTAssertNil(session.finishedAt)
        XCTAssertTrue(session.stepLog.isEmpty)
        XCTAssertTrue(session.images.isEmpty)
    }

    func testStepEntrySobreviveAoRoundTripDeJSON() throws {
        let entry = StepEntry(timestamp: .now, type: "search", text: "busca inicial")

        let data = try JSONEncoder().encode([entry])
        let decoded = try JSONDecoder().decode([StepEntry].self, from: data)

        XCTAssertEqual(decoded.first?.type, "search")
        XCTAssertEqual(decoded.first?.text, "busca inicial")
    }
}
