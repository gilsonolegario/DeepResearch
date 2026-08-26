import Foundation
import SwiftData

/// Agente da API escolhido para a pesquisa.
enum AgentKind: String, Codable {
    case regular
    case max
}

/// Estado do ciclo de vida da pesquisa (nunca descartado: cancelada guarda o parcial).
enum Status: String, Codable {
    case queued
    case running
    case completed
    /// Cancelada pelo usuário com todo o acumulado preservado.
    case cancelled
    case failed
    /// Estava em aberto quando o app fechou; re-adotada no próximo launch.
    case interrupted

    /// Fim de linha para a UI: sai de "Ativas" e entra no "Histórico".
    /// `interrupted` NÃO é terminal — aguarda a re-adoção decidir o destino.
    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed: true
        case .queued, .running, .interrupted: false
        }
    }
}

/// Fase derivada por heurística dos tipos de step — rótulo do app, não vem da API.
enum Phase: String, Codable {
    case planning
    case researching
    case synthesizing
}

/// Uma linha do log ao vivo (step recebido do stream ou do GET).
struct StepEntry: Codable {
    var timestamp: Date
    var type: String
    var text: String
}

@Model
final class ResearchSession {
    /// ID devolvido pela Interactions API — chave da re-adoção e do acompanhamento.
    var interactionID: String?
    var question: String
    var agent: AgentKind
    var status: Status
    var phase: Phase?
    var startedAt: Date
    var finishedAt: Date?
    var stepLog: [StepEntry] = []
    var reportText: String?
    /// Infográficos do relatório; externalStorage evita inflar o store principal.
    @Attribute(.externalStorage) var images: [Data] = []
    /// Deadline por pergunta em segundos. nil = usa default global (stallTimeout).
    /// 0 = sem timeout (nunca auto-falha por stall).
    var deadlineSeconds: Int?
    /// Encadeamento follow-up: interactionID da pesquisa pai (se for continuação).
    var parentInteractionID: String?
    var parentQuestion: String?

    init(
        question: String,
        agent: AgentKind = .regular,
        status: Status = .queued,
        phase: Phase? = nil,
        interactionID: String? = nil,
        startedAt: Date = .now,
        finishedAt: Date? = nil,
        stepLog: [StepEntry] = [],
        reportText: String? = nil,
        images: [Data] = [],
        deadlineSeconds: Int? = nil,
        parentInteractionID: String? = nil,
        parentQuestion: String? = nil
    ) {
        self.question = question
        self.agent = agent
        self.status = status
        self.phase = phase
        self.interactionID = interactionID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.stepLog = stepLog
        self.reportText = reportText
        self.images = images
        self.deadlineSeconds = deadlineSeconds
        self.parentInteractionID = parentInteractionID
        self.parentQuestion = parentQuestion
    }
}
