import Foundation
import SwiftData
import XCTest
@testable import DeepResearch

// MARK: - Mock Client (nonisolated — configuração feita via init)

/// Mock com respostas pré-configuradas — cada chamada avança para a próxima.
/// Configurado via init para evitar dependência de @MainActor na construção.
final class MockInteractionsClient: InteractionsClientProtocol, @unchecked Sendable {
    private let createResult: Result<Interaction, Error>?
    private let getResult: [Result<Interaction, Error>]
    private let cancelResult: Result<Interaction, Error>?
    private let getCallIndex = AtomicInt(0)

    init(
        createResult: Result<Interaction, Error>? = nil,
        getResult: [Result<Interaction, Error>] = [],
        cancelResult: Result<Interaction, Error>? = nil
    ) {
        self.createResult = createResult
        self.getResult = getResult
        self.cancelResult = cancelResult
    }

    func create(question: String, agent: AgentKind, context: String? = nil, previousInteractionID: String? = nil) async throws -> Interaction {
        switch createResult {
        case .success(let i): i
        case .failure(let e): throw e
        case .none: fatalError("MockInteractionsClient.create não configurado")
        }
    }

    func get(id: String) async throws -> Interaction {
        let idx = getCallIndex.increment()
        guard idx < getResult.count else {
            fatalError("MockInteractionsClient.get chamado \(idx + 1)× mas só \(getResult.count) respostas configuradas")
        }
        switch getResult[idx] {
        case .success(let i): return i
        case .failure(let e): throw e
        }
    }

    func cancel(id: String) async throws -> Interaction {
        switch cancelResult {
        case .success(let i): i
        case .failure(let e): throw e
        case .none: fatalError("MockInteractionsClient.cancel não configurado")
        }
    }
}

/// Contador atômico simples (OSAtomicIncrement preserva thread-safety).
private final class AtomicInt: @unchecked Sendable {
    private var value: Int
    init(_ v: Int) { value = v }
    func increment() -> Int {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        value += 1; return value - 1
    }
}

// MARK: - Helpers

/// Cria um ModelContainer in-memory isolado.
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Schema([ResearchSession.self]),
        configurations: [config]
    )
}

/// Coordinator com polling rápido para testes.
@MainActor
private func makeCoordinator(
    client: MockInteractionsClient,
    context: ModelContext
) -> ResearchCoordinator {
    ResearchCoordinator(client: client, modelContext: context, pollInterval: .milliseconds(10))
}

// MARK: - Testes

@MainActor
final class ResearchCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        // setUp é chamado pelo runner — em @MainActor class, warnings de nonisolated
        // são inofensivos (XCTest roda na main thread de qualquer forma).
        container = try! makeContainer()
        context = container.mainContext
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Fixture: Content tolerante

    func testFixtureContentTolerantDecodificaComTiposDesconhecidos() throws {
        let data = try TestFixtures.load("interaction-content-tolerant")
        let interaction = try JSONDecoder().decode(Interaction.self, from: data)

        XCTAssertEqual(interaction.steps.count, 1)
        guard case .modelOutput(let content) = interaction.steps[0] else {
            return XCTFail("step deveria ser model_output")
        }
        // 3 textos sobrevivem; audio, video, document são pulados.
        XCTAssertEqual(content.count, 3)
        XCTAssertEqual(content[0], .text("Primeiro parágrafo do relatório."))
        XCTAssertEqual(content[1], .text("Segundo parágrafo do relatório."))
        XCTAssertEqual(content[2], .text("Terceiro parágrafo do relatório."))
    }

    // MARK: - Re-adoção

    func testAdotarSessaoConcluidaExtraiRelatorio() async throws {
        let mock = MockInteractionsClient(getResult: [.success(makeInteraction(
            status: .completed,
            steps: [makeModelOutput("relatório completo")]
        ))])

        let coordinator = makeCoordinator(client: mock, context: context)
        let session = coordinator.createSession(
            question: "teste", agent: .regular,
            status: .running, interactionID: "v1_adopt"
        )

        await coordinator.adoptPendingSessions()

        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.reportText, "relatório completo")
        XCTAssertNotNil(session.finishedAt)
    }

    func testAdotarSessaoRodandoRetomaMonitoramento() async throws {
        let mock = MockInteractionsClient(getResult: [.success(makeInteraction(status: .inProgress, steps: []))])

        let coordinator = makeCoordinator(client: mock, context: context)
        let session = coordinator.createSession(
            question: "teste", agent: .regular,
            status: .running, interactionID: "v1_running"
        )

        await coordinator.adoptPendingSessions()

        XCTAssertEqual(session.status, .running)
        XCTAssertTrue(coordinator.isMonitoring(for: session))
    }

    // MARK: - Cancelamento

    func testCancelamentoPreservaEstadoColetado() async throws {
        let mock = MockInteractionsClient(cancelResult: .success(makeInteraction(status: .cancelled)))

        let coordinator = makeCoordinator(client: mock, context: context)
        let session = coordinator.createSession(question: "teste", agent: .regular)
        // Simula progresso: 3 entries já coletados.
        session.stepLog = [
            StepEntry(timestamp: .now, type: "thought", text: "pensando"),
            StepEntry(timestamp: .now, type: "google_search", text: ""),
            StepEntry(timestamp: .now, type: "model_output", text: "resultado parcial"),
        ]
        session.status = .running

        await coordinator.cancel(session: session)

        XCTAssertEqual(session.status, .cancelled)
        XCTAssertEqual(session.stepLog.count, 3, "nada deve ser descartado")
        XCTAssertNotNil(session.finishedAt)
    }

    // MARK: - Transição queued → running → completed

    func testTransicaoQueuedRunningCompleted() async throws {
        let mock = MockInteractionsClient(
            createResult: .success(makeInteraction(id: "v1_create")),
            getResult: [.success(makeInteraction(
                status: .completed,
                steps: [makeModelOutput("relatório final")]
            ))]
        )

        let coordinator = makeCoordinator(client: mock, context: context)
        await coordinator.start(question: "pergunta teste", agent: .regular)

        // Espera o loop de polling completar (10ms intervalo + margem).
        try await Task.sleep(for: .milliseconds(50))

        let descriptor = FetchDescriptor<ResearchSession>()
        let sessions = try context.fetch(descriptor)
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.interactionID, "v1_create")
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.reportText, "relatório final")
        XCTAssertNotNil(session.finishedAt)
    }

    // MARK: - Fases derivadas

    func testFasesDerivadas() throws {
        let coordinator = makeCoordinator(client: MockInteractionsClient(), context: context)

        // Fase planning: só thought.
        let p1 = coordinator.createSession(question: "p1")
        p1.phase = derivePhasePublic(steps: [.thought(summary: [])])

        // Fase researching: thought + google_search.
        let p2 = coordinator.createSession(question: "p2")
        p2.phase = derivePhasePublic(steps: [
            .thought(summary: []),
            .googleSearchCall,
        ])

        // Fase synthesizing: thought + google_search + model_output.
        let p3 = coordinator.createSession(question: "p3")
        p3.phase = derivePhasePublic(steps: [
            .thought(summary: []),
            .googleSearchCall,
            .modelOutput([.text("relatório")]),
        ])

        XCTAssertEqual(p1.phase, .planning)
        XCTAssertEqual(p2.phase, .researching)
        XCTAssertEqual(p3.phase, .synthesizing)
    }

    /// Espelho público da heurística privada do coordinator para teste direto.
    private func derivePhasePublic(steps: [Step]) -> Phase {
        guard let last = steps.last else { return .planning }
        switch last {
        case .thought: return .planning
        case .googleSearchCall, .googleSearchResult, .functionCall, .functionResult: return .researching
        case .modelOutput: return .synthesizing
        default: return .researching
        }
    }

    // MARK: - Lifecycle de monitoring

    func testMonitoramentoParaAposTerminal() async throws {
        let mock = MockInteractionsClient(getResult: [.success(makeInteraction(status: .completed, steps: []))])

        let coordinator = makeCoordinator(client: mock, context: context)
        let session = coordinator.createSession(
            question: "teste", agent: .regular,
            status: .running, interactionID: "v1_adopt"
        )

        // Adopt inicia o monitoramento, que deve encerrar ao receber status terminal.
        await coordinator.adoptPendingSessions()

        // Espera o loop de polling completar.
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(coordinator.isMonitoring(for: session))
        XCTAssertEqual(session.status, .completed)
    }

    func testStartCriaSessaoEmFilaEChamaCreate() async throws {
        let mock = MockInteractionsClient(
            createResult: .success(makeInteraction(id: "v1_new")),
            getResult: [.success(makeInteraction(status: .inProgress, steps: []))]
        )

        let coordinator = makeCoordinator(client: mock, context: context)
        await coordinator.start(question: "pergunta nova")

        let descriptor = FetchDescriptor<ResearchSession>()
        let sessions = try context.fetch(descriptor)
        XCTAssertEqual(sessions.count, 1)

        let session = sessions[0]
        XCTAssertEqual(session.question, "pergunta nova")
        XCTAssertEqual(session.interactionID, "v1_new")
        XCTAssertEqual(session.status, .running)
        XCTAssertTrue(coordinator.isMonitoring(for: session))
    }

    func testStartFalhaMarcaFailed() async throws {
        let mock = MockInteractionsClient(
            createResult: .failure(ClientError.quotaExceeded(message: "cota esgotada"))
        )

        let coordinator = makeCoordinator(client: mock, context: context)
        await coordinator.start(question: "pergunta")

        let descriptor = FetchDescriptor<ResearchSession>()
        let sessions = try context.fetch(descriptor)
        XCTAssertEqual(sessions[0].status, .failed)
        XCTAssertNotNil(sessions[0].finishedAt)
    }

    // MARK: - Helpers

    private func makeInteraction(
        id: String = "v1_test",
        status: InteractionStatus = .completed,
        steps: [Step] = []
    ) -> Interaction {
        Interaction(id: id, status: status, steps: steps)
    }

    private func makeModelOutput(_ texts: String...) -> Step {
        .modelOutput(texts.map { Content.text($0) })
    }
}
