import Foundation

// MARK: - Eventos SSE tipados

/// Evento SSE parseado do stream da Interactions API.
/// Tipos desconhecidos são ignorados; a sentinela [DONE] encerra o stream.
enum SSEEvent: Sendable, Equatable {
    /// `interaction.created` — interaction recém-criada com status e modelo.
    case interactionCreated(id: String, status: String?)
    /// `step.start` — início de uma etapa.
    case stepStart(index: Int, stepType: String)
    /// `step.delta` — conteúdo incremental de uma etapa (texto acumulado).
    case stepDelta(index: Int, delta: TextDelta)
    /// `step.stop` — fim de uma etapa.
    case stepStop(index: Int)
    /// `interaction.completed` — resultado final.
    case interactionCompleted
    /// `data: [DONE]` — sentinela de fim de stream.
    case done
}

/// Delta de texto incremental recebido via `step.delta`.
struct TextDelta: Sendable, Equatable {
    let text: String
}

// MARK: - Parser SSE tolerante

/// Parser de Server-Sent Events sobre um AsyncSequence de linhas.
/// Formato (contrato §5):
///   event: <tipo>\ndata: <json>\n\n
///
/// Regras:
/// - Evento desconhecido → ignorado (não quebra o stream).
/// - `data: [DONE]` → emite `.done` e encerra.
/// - JSON malformado → ignorado.
/// - Vazio = fim do stream (caller encerra o AsyncStream).
enum SSEParser {

    /// Faz parse de um evento SSE completo (já separado por linha em branco).
    /// `rawEventLines` contém as linhas de um único evento (sem a linha em branco final).
    static func parseEvent(_ rawEventLines: [String]) -> SSEEvent? {
        var eventType: String?
        var dataLines: [String] = []

        for line in rawEventLines {
            if line.hasPrefix("event:") {
                eventType = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
            }
            // Linhas que não começam com "event:" nem "data:" são ignoradas (comentários, campos desconhecidos).
        }

        let data = dataLines.joined(separator: "\n")

        // Sentinela [DONE] — pode vir com event: done ou sem event type.
        if data == "[DONE]" { return .done }

        guard let type = eventType else { return nil }
        guard !data.isEmpty else { return nil }

        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return nil }

        return decodeEvent(type: type, json: json)
    }

    // MARK: - Decodificação por tipo

    private static func decodeEvent(type: String, json: [String: Any]) -> SSEEvent? {
        switch type {
        case "interaction.created":
            guard let interaction = json["interaction"] as? [String: Any] else { return nil }
            let id = interaction["id"] as? String ?? ""
            let status = interaction["status"] as? String
            return .interactionCreated(id: id, status: status)

        case "step.start":
            guard let index = json["index"] as? Int,
                  let step = json["step"] as? [String: Any],
                  let stepType = step["type"] as? String
            else { return nil }
            return .stepStart(index: index, stepType: stepType)

        case "step.delta":
            guard let index = json["index"] as? Int,
                  let deltaDict = json["delta"] as? [String: Any]
            else { return nil }
            let text = deltaDict["text"] as? String ?? ""
            return .stepDelta(index: index, delta: TextDelta(text: text))

        case "step.stop":
            guard let index = json["index"] as? Int else { return nil }
            return .stepStop(index: index)

        case "interaction.completed":
            return .interactionCompleted

        default:
            return nil
        }
    }
}
