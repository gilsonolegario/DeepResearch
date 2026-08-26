import XCTest
@testable import DeepResearch

/// Stub de URLProtocol: devolve as respostas enfileiradas e captura as requests.
/// O estado vive num lock próprio porque URLProtocol carrega em threads da session.
final class URLProtocolStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [Result<(HTTPURLResponse, Data), Error>] = []
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        responses = []
        requests = []
    }

    static func queueResponse(
        status: Int,
        json: String,
        url: String = "https://generativelanguage.googleapis.com/v1beta/interactions"
    ) {
        let response = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        lock.lock()
        defer { lock.unlock() }
        responses.append(.success((response, json.data(using: .utf8)!)))
    }

    static func queueError(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        responses.append(.failure(error))
    }

    static func firstRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.first
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result: Result<(HTTPURLResponse, Data), Error>? = {
            Self.lock.lock()
            defer { Self.lock.unlock() }
            Self.requests.append(request)
            guard !Self.responses.isEmpty else { return nil }
            return Self.responses.removeFirst()
        }()

        guard let result else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch result {
        case .success(let (response, data)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Testes do client HTTP contra stubs de URLProtocol.
@MainActor
final class InteractionsClientTests: XCTestCase {
    private var client: URLSessionInteractionsClient!

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        client = URLSessionInteractionsClient(
            sessionConfiguration: configuration,
            apiKeyProvider: { "key-de-teste" }
        )
    }

    // MARK: - create

    func testCreateFelizMontaRequestEDecodificaInteracao() async throws {
        URLProtocolStub.queueResponse(status: 200, json: """
        {"id": "v1_novo", "status": "in_progress", "agent": "deep-research-preview-04-2026", "steps": []}
        """)

        let interaction = try await client.create(question: "capital do Brasil?", agent: .regular)

        XCTAssertEqual(interaction.id, "v1_novo")
        XCTAssertEqual(interaction.status, .inProgress)

        let sent = try XCTUnwrap(URLProtocolStub.firstRequest())
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.scheme, "https")
        XCTAssertEqual(sent.url?.host, "generativelanguage.googleapis.com")
        XCTAssertEqual(sent.url?.path, "/v1beta/interactions")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-goog-api-key"), "key-de-teste")

        let payload = try XCTUnwrap(Self.jsonBody(of: sent) as? [String: Any])
        let input = try XCTUnwrap(payload["input"] as? String)
        XCTAssertTrue(input.hasSuffix("capital do Brasil?"), "input deve terminar com a pergunta — prefixo de formato é interno")
        XCTAssertEqual(payload["agent"] as? String, "deep-research-preview-04-2026")
        XCTAssertEqual(payload["background"] as? Bool, true)
    }

    func testCreateComAgenteMaxMandaAgentCorreto() async throws {
        URLProtocolStub.queueResponse(status: 200, json: #"{"id": "v1_max", "steps": []}"#)

        _ = try await client.create(question: "pergunta", agent: .max)

        let body = try XCTUnwrap(Self.jsonBody(of: URLProtocolStub.firstRequest()) )
        let payload = try XCTUnwrap(body as? [String: Any])
        XCTAssertEqual(payload["agent"] as? String, "deep-research-max-preview-04-2026")
    }

    // MARK: - cancel

    func testCancelDevolveInteracaoCancelada() async throws {
        URLProtocolStub.queueResponse(
            status: 200,
            json: #"{"id": "v1_novo", "status": "cancelled", "steps": []}"#,
            url: "https://generativelanguage.googleapis.com/v1beta/interactions/v1_novo/cancel"
        )

        let interaction = try await client.cancel(id: "v1_novo")

        XCTAssertEqual(interaction.status, .cancelled)
        let sent = try XCTUnwrap(URLProtocolStub.firstRequest())
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.path, "/v1beta/interactions/v1_novo/cancel")
    }

    // MARK: - erros

    func testErroDeQuotaViraQuotaExceeded() async throws {
        let quota = String(decoding: try TestFixtures.load("error-quota"), as: UTF8.self)
        URLProtocolStub.queueResponse(status: 429, json: quota)

        do {
            _ = try await client.get(id: "v1_qualquer")
            XCTFail("deveria ter falhado")
        } catch let error as ClientError {
            guard case .quotaExceeded(let message) = error else {
                return XCTFail("erro inesperado: \(error)")
            }
            XCTAssertTrue(message.contains("exhausted"))
        }
    }

    func testErroDeKeyInvalidaViraInvalidAPIKey() async throws {
        let invalid = String(decoding: try TestFixtures.load("error-invalid-key"), as: UTF8.self)
        URLProtocolStub.queueResponse(status: 400, json: invalid)

        do {
            _ = try await client.get(id: "v1_qualquer")
            XCTFail("deveria ter falhado")
        } catch let error as ClientError {
            guard case .invalidAPIKey = error else {
                return XCTFail("erro inesperado: \(error)")
            }
        }
    }

    func testErroNotFoundViraInteractionNotFound() async throws {
        URLProtocolStub.queueResponse(
            status: 404,
            json: #"{"error": {"code": 404, "message": "The interaction could not be found."}}"#
        )

        do {
            _ = try await client.get(id: "v1_sumido")
            XCTFail("deveria ter falhado")
        } catch let error as ClientError {
            guard case .interactionNotFound(let id) = error else {
                return XCTFail("erro inesperado: \(error)")
            }
            XCTAssertEqual(id, "v1_sumido")
        }
    }

    func testErroHTTPGenericoPreservaStatusEMensagem() async throws {
        URLProtocolStub.queueResponse(status: 500, json: #"{"error": {"code": 500, "message": "backend boom"}}"#)

        do {
            _ = try await client.get(id: "v1_x")
            XCTFail("deveria ter falhado")
        } catch let error as ClientError {
            guard case .http(500, let message) = error else {
                return XCTFail("erro inesperado: \(error)")
            }
            XCTAssertEqual(message, "backend boom")
        }
    }

    func testRespostaSemCorpoJSONViraErroTipado() async throws {
        URLProtocolStub.queueResponse(status: 502, json: "<html>bad gateway</html>")

        do {
            _ = try await client.get(id: "v1_x")
            XCTFail("deveria ter falhado")
        } catch let error as ClientError {
            guard case .http(502, _) = error else {
                return XCTFail("erro inesperado: \(error)")
            }
        }
    }

    /// Lê o corpo de uma request tanto quando ficou em httpBody quanto em stream.
    private static func jsonBody(of request: URLRequest?) -> Any? {
        guard let request else { return nil }
        if let body = request.httpBody {
            return try? JSONSerialization.jsonObject(with: body)
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
