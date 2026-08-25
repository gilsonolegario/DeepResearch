import Foundation

/// Erros do client mapeados para as situações que o app trata de forma distinta.
/// Os códigos exatos de erro da API são UNCERTAIN no contrato (só há `code` +
/// `message` no schema), então a discriminação usa o HTTP status — caminho
/// conservador — e a mensagem da API viaja junto para exibição.
enum ClientError: Error, Equatable {
    /// 429: cota esgotada.
    case quotaExceeded(message: String)
    /// 400/401/403 com mensagem de autenticação: key inválida ou ausente.
    case invalidAPIKey
    /// 404: interação não existe (ID errado ou expirada).
    case interactionNotFound(id: String)
    /// Qualquer outro status HTTP com corpo legível (ou não).
    case http(Int, message: String)
    /// Falha de rede/transporte sem resposta HTTP (offline, DNS, TLS).
    case transport(String)
}

@MainActor
protocol InteractionsClientProtocol {
    func create(question: String, agent: AgentKind) async throws -> Interaction
    func get(id: String) async throws -> Interaction
    func cancel(id: String) async throws -> Interaction
}

struct URLSessionInteractionsClient: InteractionsClientProtocol {
    private let session: URLSession
    private let apiKeyProvider: () throws -> String

    static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    init(
        sessionConfiguration: URLSessionConfiguration = .default,
        apiKeyProvider: @escaping () throws -> String
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.session = URLSession(configuration: sessionConfiguration)
    }

    func create(question: String, agent: AgentKind) async throws -> Interaction {
        let body: [String: Any] = [
            "input": question,
            "agent": Self.agentIdentifier(for: agent),
            // Sempre background: o fluxo do app é criar → acompanhar → cancelável.
            "background": true,
        ]
        guard JSONSerialization.isValidJSONObject(body) else {
            throw ClientError.http(0, message: "corpo de create inválido")
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("interactions"))
        request.httpMethod = "POST"
        return try await perform(request, jsonBody: body)
    }

    func get(id: String) async throws -> Interaction {
        try await perform(requestForInteraction(id: id))
    }

    func cancel(id: String) async throws -> Interaction {
        try await perform(requestForInteraction(id: id, action: "cancel"))
    }

    private func requestForInteraction(id: String, action: String? = nil) -> URLRequest {
        var url = Self.baseURL.appendingPathComponent("interactions").appendingPathComponent(id)
        if let action {
            url = url.appendingPathComponent(action)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            return request
        }
        return URLRequest(url: url)
    }

    private func perform(_ request: URLRequest, jsonBody: [String: Any]? = nil) async throws -> Interaction {
        var request = request
        request.setValue(try apiKeyProvider(), forHTTPHeaderField: "x-goog-api-key")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        // GET/cancel também recebem Content-Type por simetria; inofensivo.

        let (data, response) = try await session.data(for: request)
        let httpResponse = try Self.httpResponse(from: response)

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.clientError(statusCode: httpResponse.statusCode, body: data, interactionURLPath: request.url?.path)
        }
        do {
            return try JSONDecoder().decode(Interaction.self, from: data)
        } catch {
            // Resposta 2xx que não decodifica é bug de contrato: preservar o motivo.
            let preview = String(decoding: data.prefix(200), as: UTF8.self)
            throw ClientError.http(
                httpResponse.statusCode,
                message: "resposta ilegível: \(preview)"
            )
        }
    }

    private static func httpResponse(from response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.transport("resposta não-HTTP")
        }
        return http
    }

    private static func clientError(statusCode: Int, body: Data, interactionURLPath: String?) -> ClientError {
        let apiMessage = Self.errorMessage(in: body)
        let extractedID = interactionURLPath.flatMap { Self.extractInteractionID(from: $0) }

        switch statusCode {
        case 429:
            return .quotaExceeded(message: apiMessage ?? "cota esgotada")
        case 400, 401, 403:
            return .invalidAPIKey
        case 404:
            return .interactionNotFound(id: extractedID ?? "")
        default:
            return .http(statusCode, message: apiMessage ?? "(sem mensagem)")
        }
    }

    /// Extrai o ID de `/v1beta/interactions/{id}` ou `/v1beta/interactions/{id}/cancel`.
    private static func extractInteractionID(from path: String) -> String? {
        let segments = path.split(separator: "/").map(String.init)
        guard let idx = segments.firstIndex(of: "interactions"),
              idx + 1 < segments.count
        else { return nil }
        return segments[idx + 1]
    }

    /// Extrai `{"error": {"code": ..., "message": ...}}` do corpo de erro.
    private static func errorMessage(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = object["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }

    static func agentIdentifier(for agent: AgentKind) -> String {
        switch agent {
        case .regular: "deep-research-preview-04-2026"
        case .max: "deep-research-max-preview-04-2026"
        }
    }
}
