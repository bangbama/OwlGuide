import CoreGraphics
import Foundation

enum BackendDataSourceMode: String, CaseIterable, Identifiable {
    case localSample = "local_sample"
    case localBackend = "local_backend"
    case cloudBackend = "cloud_backend"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localSample:
            return "Local Sample"
        case .localBackend:
            return "Local Backend"
        case .cloudBackend:
            return "Cloud Backend (Test Only)"
        }
    }

    var detail: String {
        switch self {
        case .localSample:
            return "Read a bundled mock JSON response without network."
        case .localBackend:
            return "Send requests to http://127.0.0.1:8000."
        case .cloudBackend:
            return "Send requests to the deployed Cloud Run backend."
        }
    }
}

struct BackendEnvironment {
    static let localBackendBaseURL = URL(string: "http://127.0.0.1:8000")!
    static let cloudBackendBaseURL = URL(string: "https://owlguide-backend-c53h2zrn2a-pd.a.run.app")!
    static let sampleResponseResourceName = "AnalyzeScreenSample"
}

struct BackendHealthResponse: Decodable {
    let ok: Bool
}

struct BackendAnalysisCandidate: Codable {
    let id: String
    let rank: Int
    let label: String
    let semanticHint: String
    let role: String
    let subrole: String?
    let bounds: ScreenUnderstandingBounds?
    let score: Int?
    let signals: [String]
}

struct AnalyzeScreenRequest: Encodable {
    let sessionID: String
    let userGoal: String
    let appName: String
    let windowTitle: String
    let screenshotBase64: String
    let actionableCandidates: [BackendAnalysisCandidate]
    let readableCandidates: [BackendAnalysisCandidate]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case userGoal = "user_goal"
        case appName = "app_name"
        case windowTitle = "window_title"
        case screenshotBase64 = "screenshot_base64"
        case actionableCandidates = "actionable_candidates"
        case readableCandidates = "readable_candidates"
    }
}

struct AnalyzeScreenResponse: Decodable {
    let context: String
    let likelyTask: String
    let safeFirstStep: String
    let confirmationQuestion: String
    let actionPlan: [ActionPlanItem]
    let guideCard: BackendGuideCard?
    let targetInfo: BackendTargetInfo?
    let meta: BackendMeta?

    enum CodingKeys: String, CodingKey {
        case context
        case likelyTask = "likely_task"
        case safeFirstStep = "safe_first_step"
        case confirmationQuestion = "confirmation_question"
        case actionPlan = "action_plan"
        case guideCard = "guide_card"
        case targetInfo = "target_info"
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        context = try container.decodeIfPresent(String.self, forKey: .context)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        likelyTask = try container.decodeIfPresent(String.self, forKey: .likelyTask)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        safeFirstStep = try container.decodeIfPresent(String.self, forKey: .safeFirstStep)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        confirmationQuestion = try container.decodeIfPresent(String.self, forKey: .confirmationQuestion)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        actionPlan = try container.decodeIfPresent([ActionPlanItem].self, forKey: .actionPlan) ?? []
        guideCard = try container.decodeIfPresent(BackendGuideCard.self, forKey: .guideCard)
        targetInfo = try container.decodeIfPresent(BackendTargetInfo.self, forKey: .targetInfo)
        meta = try container.decodeIfPresent(BackendMeta.self, forKey: .meta)
    }
}

struct ActionPlanItem: Decodable, Identifiable {
    let type: String
    let target: String?
    let text: String?
    let requiresConfirmation: Bool
    let value: String?
    let relatedLocalElement: String?
    let visualBoundingBox: [Int]?

    enum CodingKeys: String, CodingKey {
        case type
        case target
        case text
        case requiresConfirmation = "requires_confirmation"
        case value
        case input
        case content
        case actionValue = "action_value"
        case relatedLocalElement = "related_local_element"
        case candidateID = "candidate_id"
        case visualBoundingBox = "visual_bounding_box"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "instruction"
        target = try container.decodeIfPresent(String.self, forKey: .target)?.trimmingCharacters(in: .whitespacesAndNewlines)
        text = try container.decodeIfPresent(String.self, forKey: .text)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // 兼容布尔、字符串、数字三种格式的requires_confirmation
        if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) {
            requiresConfirmation = boolValue
        } else if let stringValue = try? container.decodeIfPresent(String.self, forKey: .requiresConfirmation) {
            requiresConfirmation = stringValue.lowercased() == "true"
        } else if let intValue = try? container.decodeIfPresent(Int.self, forKey: .requiresConfirmation) {
            requiresConfirmation = intValue != 0
        } else {
            requiresConfirmation = false
        }
        value =
            try container.decodeIfPresent(String.self, forKey: .value)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? container.decodeIfPresent(String.self, forKey: .input)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? container.decodeIfPresent(String.self, forKey: .content)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? container.decodeIfPresent(String.self, forKey: .actionValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
        relatedLocalElement =
            try container.decodeIfPresent(String.self, forKey: .relatedLocalElement)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? container.decodeIfPresent(String.self, forKey: .candidateID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // 确保视觉边界框有4个有效元素，否则返回nil
        if let boundingBox = try container.decodeIfPresent([Int].self, forKey: .visualBoundingBox), boundingBox.count == 4 {
            visualBoundingBox = boundingBox
        } else {
            visualBoundingBox = nil
        }
    }

    var id: String {
        [type, target ?? "", text ?? "", value ?? ""].joined(separator: "|")
    }
}

struct BackendGuideCard: Decodable {
    let title: String?
    let body: String?
    let tone: String?
    let primaryAction: String?

    enum CodingKeys: String, CodingKey {
        case title
        case body
        case tone
        case primaryAction = "primary_action"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)?.trimmingCharacters(in: .whitespacesAndNewlines)
        body = try container.decodeIfPresent(String.self, forKey: .body)?.trimmingCharacters(in: .whitespacesAndNewlines)
        tone = try container.decodeIfPresent(String.self, forKey: .tone)?.trimmingCharacters(in: .whitespacesAndNewlines)
        primaryAction = try container.decodeIfPresent(String.self, forKey: .primaryAction)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BackendTargetInfo: Decodable {
    let kind: String?
    let label: String?
    let rect: BackendRect?
    let accessibilityLabel: String?
    let localCandidateID: String?
    let visualBoundingBox: [Int]?

    enum CodingKeys: String, CodingKey {
        case kind
        case label
        case rect
        case accessibilityLabel = "accessibility_label"
        case localCandidateID = "local_candidate_id"
        case candidateID = "candidate_id"
        case visualBoundingBox = "visual_bounding_box"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)?.trimmingCharacters(in: .whitespacesAndNewlines)
        label = try container.decodeIfPresent(String.self, forKey: .label)?.trimmingCharacters(in: .whitespacesAndNewlines)
        rect = try container.decodeIfPresent(BackendRect.self, forKey: .rect)
        accessibilityLabel = try container.decodeIfPresent(String.self, forKey: .accessibilityLabel)?.trimmingCharacters(in: .whitespacesAndNewlines)
        localCandidateID =
            try container.decodeIfPresent(String.self, forKey: .localCandidateID)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? container.decodeIfPresent(String.self, forKey: .candidateID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // 确保视觉边界框有4个有效元素，否则返回nil
        if let boundingBox = try container.decodeIfPresent([Int].self, forKey: .visualBoundingBox), boundingBox.count == 4 {
            visualBoundingBox = boundingBox
        } else {
            visualBoundingBox = nil
        }
    }
}

struct BackendRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct BackendMeta: Decodable {
    let confidence: Double?
    let riskLevel: String?
    let estimatedSteps: Int?

    enum CodingKeys: String, CodingKey {
        case confidence
        case riskLevel = "risk_level"
        case estimatedSteps = "estimated_steps"
    }
}
