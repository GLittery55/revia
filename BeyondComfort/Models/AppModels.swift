import Foundation

enum ReflectionStage: String, Codable, CaseIterable {
    case orient, contextGathering, contextConfirmation, tenderGrounding
    case cardDraw, cardInterpretation, tenderExploration, affirmationReadiness
    case candidInquiry, actionComposer, reviewClose, safetyInterrupt
}

enum ExperimentalCondition: String, Codable, CaseIterable {
    case cardMediated, modelAsserted
}

enum MessageRole: String, Codable { case assistant, user, system }

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct ContextCanvas: Codable, Equatable {
    var eventDate = Date()
    var event = ""
    var experience = ""
    var meaning = ""
    var constraints = ""
    var agencyAndUncertainty = ""
    var reflectiveIntention = ""
    var contextualFactors = ""

    var reported: String {
        [event, experience, meaning, constraints, agencyAndUncertainty, reflectiveIntention]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    var uncertainty: String { agencyAndUncertainty }
}

enum TrackingSource: String, Codable { case healthSleep, healthHeartRate, healthHRV, calendarLoad }

struct TrackingCue: Identifiable, Codable, Equatable {
    let id: UUID
    let source: TrackingSource
    let observation: String
    var included: Bool

    init(id: UUID = UUID(), source: TrackingSource, observation: String, included: Bool = true) {
        self.id = id; self.source = source; self.observation = observation; self.included = included
    }
}

struct ReflectionCard: Identifiable, Codable, Equatable {
    let id: Int
    let neutralLabel: String
    let imageName: String
}

struct StudyEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let stage: ReflectionStage
    let action: String

    init(id: UUID = UUID(), timestamp: Date = .now, stage: ReflectionStage, action: String) {
        self.id = id; self.timestamp = timestamp; self.stage = stage; self.action = action
    }
}

struct StudyMeasures: Codable, Equatable {
    var feltUnderstood = 4.0
    var compassionateCandor = 4.0
    var reactance = 4.0
    var responsibilityClarity = 4.0
    var interpretationOwnership = 4.0
    var cardFamiliarity = 1.0
}

enum HypothesisStatus: String, Codable { case pending, kept, revised, setAside }

struct Hypothesis: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var status: HypothesisStatus

    init(id: UUID = UUID(), text: String, status: HypothesisStatus = .pending) {
        self.id = id; self.text = text; self.status = status
    }
}

enum ActionType: String, Codable, CaseIterable {
    case care, repair, protection, change, notReady

    var title: String {
        switch self {
        case .care: "Care"
        case .repair: "Repair"
        case .protection: "Protection"
        case .change: "Change"
        case .notReady: "Not ready"
        }
    }
}

struct ReflectionAction: Codable, Equatable {
    var type: ActionType = .care
    var text = ""
    var feasibility = ""
}

struct ActionSuggestion: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ActionType
    let text: String
    let rationale: String

    init(id: UUID = UUID(), type: ActionType, text: String, rationale: String) {
        self.id = id; self.type = type; self.text = text; self.rationale = rationale
    }
}

struct ReflectionSession: Identifiable, Codable {
    var id = UUID()
    var createdAt = Date()
    var stage: ReflectionStage = .orient
    var condition: ExperimentalCondition = .cardMediated
    var messages: [ChatMessage] = []
    var canvas = ContextCanvas()
    var trackingCues: [TrackingCue] = []
    var card: ReflectionCard?
    var cardInterpretation = ""
    var hypotheses: [Hypothesis] = []
    var actionSuggestions: [ActionSuggestion] = []
    var action = ReflectionAction()
    var studyEvents: [StudyEvent] = []
    var studyMeasures = StudyMeasures()
}

struct LLMActionSuggestion: Codable {
    let type: String
    let text: String
    let rationale: String
}

struct LLMResponse: Codable {
    let reflectiveSummary: String
    let uncertaintyStatement: String
    let question: String
    let hypotheses: [String]
    let actionSuggestions: [LLMActionSuggestion]
}
