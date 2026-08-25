import Foundation

/// Status de uma Interaction conforme o contrato (8 valores conhecidos).
/// A API pode acrescentar valores novos a qualquer momento — qualquer string
/// não reconhecida vira `.unknown` em vez de quebrar o parse.
enum InteractionStatus: Equatable {
    case queued
    case inProgress
    case requiresAction
    case completed
    case failed
    case cancelled
    case incomplete
    case budgetExceeded
    /// Valor vindo da API que este app ainda não conhece.
    case unknown

    init(apiValue: String?) {
        switch apiValue {
        case "queued": self = .queued
        case "in_progress": self = .inProgress
        case "requires_action": self = .requiresAction
        case "completed": self = .completed
        case "failed": self = .failed
        case "cancelled": self = .cancelled
        case "incomplete": self = .incomplete
        case "budget_exceeded": self = .budgetExceeded
        default: self = .unknown
        }
    }

    /// Valor cru esperado pela API (para debug/logs do app).
    var apiValue: String? {
        switch self {
        case .queued: "queued"
        case .inProgress: "in_progress"
        case .requiresAction: "requires_action"
        case .completed: "completed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        case .incomplete: "incomplete"
        case .budgetExceeded: "budget_exceeded"
        case .unknown: nil
        }
    }
}

/// Um passo do raciocínio/ação do agente — union discriminada pelo campo `type`.
/// Só os tipos que o app consome são mapeados; todo o resto cai em `.other`
/// preservando o nome do tipo (a API lista mais uma dúzia de variantes).
enum Step: Equatable {
    case modelOutput([Content])
    case thought(summary: [Content])
    case functionCall(name: String, id: String?, arguments: String?)
    case functionResult(callID: String?, result: [Content], isError: Bool)
    case googleSearchCall
    case googleSearchResult
    case userInput([Content])
    /// Tipo não mapeado (ex.: `google_maps`, `code_execution`).
    case other(type: String)

    var typeName: String {
        switch self {
        case .modelOutput: "model_output"
        case .thought: "thought"
        case .functionCall: "function_call"
        case .functionResult: "function_result"
        case .googleSearchCall: "google_search"
        case .googleSearchResult: "google_search_result"
        case .userInput: "user_input"
        case .other(let type): type
        }
    }
}

/// Conteúdo de um step — texto ou imagem base64 (as modalidades que o app mostra).
enum Content: Equatable {
    case text(String)
    case image(base64Data: String, mimeType: String)
}

/// Resource devolvido por create/get/cancel da Interactions API.
struct Interaction: Equatable {
    var id: String
    var status: InteractionStatus
    var agent: String?
    var model: String?
    var steps: [Step]
}

extension Interaction: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, status, agent, model, steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        // Tolerante: status pode faltar ou trazer valor novo (contrato §2 + INCERTO).
        status = InteractionStatus(apiValue: try? container.decode(String.self, forKey: .status))
        agent = try? container.decode(String.self, forKey: .agent)
        model = try? container.decode(String.self, forKey: .model)
        steps = (try? container.decode([Step].self, forKey: .steps)) ?? []
    }
}

extension Step: Decodable {
    private enum StepCodingKeys: String, CodingKey {
        case type, content, summary, name, id, arguments, callID = "call_id", result, isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StepCodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "model_output":
            self = .modelOutput((try? container.decode([Content].self, forKey: .content)) ?? [])
        case "thought":
            self = .thought(summary: (try? container.decode([Content].self, forKey: .summary)) ?? [])
        case "function_call":
            self = .functionCall(
                name: (try? container.decode(String.self, forKey: .name)) ?? "",
                id: try? container.decode(String.self, forKey: .id),
                arguments: try? container.decode(String.self, forKey: .arguments)
            )
        case "function_result":
            self = .functionResult(
                callID: try? container.decode(String.self, forKey: .callID),
                result: (try? container.decode([Content].self, forKey: .result)) ?? [],
                isError: (try? container.decode(Bool.self, forKey: .isError)) ?? false
            )
        case "google_search":
            self = .googleSearchCall
        case "google_search_result":
            self = .googleSearchResult
        case "user_input":
            self = .userInput((try? container.decode([Content].self, forKey: .content)) ?? [])
        default:
            // Contrato lista ~14 tipos de step; mapear todos seria overengineering —
            // tipos novos/não consumidos caem aqui sem quebrar o resto do payload.
            self = .other(type: type)
        }
    }
}

extension Content: Decodable {
    private enum ContentCodingKeys: String, CodingKey {
        case type, text, data, mimeType = "mime_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ContentCodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image":
            self = .image(
                base64Data: try container.decode(String.self, forKey: .data),
                mimeType: (try? container.decode(String.self, forKey: .mimeType)) ?? ""
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "tipo de content não suportado"
            )
        }
    }
}
