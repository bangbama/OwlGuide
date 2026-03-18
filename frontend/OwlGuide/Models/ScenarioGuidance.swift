import Foundation

enum OwlGuideScenarioSkill: String, Codable {
    case medicalPortal
    case banking
    case governmentBenefits
    case caregiverProxy
    case general

    var displayName: String {
        switch self {
        case .medicalPortal:
            return "Medical Portal / Hospital"
        case .banking:
            return "Banking"
        case .governmentBenefits:
            return "Government Benefits"
        case .caregiverProxy:
            return "Caregiver / Proxy"
        case .general:
            return "General / Unknown"
        }
    }
}

enum OwlGuideScenarioConfidence: String, Codable {
    case high
    case medium
    case low

    var displayName: String {
        rawValue.capitalized
    }
}

struct OwlGuideScenarioContext: Codable {
    let userRequest: String?
    let appName: String
    let bundleIdentifier: String
    let windowTitle: String
    let browserHostname: String?
    let likelyPageType: String
    let selectedSkill: OwlGuideScenarioSkill
    let confidence: OwlGuideScenarioConfidence
    let matchedSignals: [String]
    let likelyPrimaryTask: String
    let likelyBackupTask: String
}

struct OwlGuideFirstResponse {
    let contextRecognition: String
    let primaryLikelyTask: String
    let backupLikelyTask: String
    let safeFirstStep: String
    let clarificationQuestion: String?
}

enum OwlGuideUserIntent: String, Codable, CaseIterable, Identifiable {
    case signIn
    case recoverAccount
    case bookAppointment
    case checkResults
    case sendMessage
    case payBill
    case learnServices
    case findResources
    case accessMedicalImages
    case findDoctor
    case continueApplication
    case checkStatus
    case confirmProfile
    case understandPage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .signIn:
            return "Sign in"
        case .recoverAccount:
            return "Recover account"
        case .bookAppointment:
            return "Book appointment"
        case .checkResults:
            return "Check results"
        case .sendMessage:
            return "Send message"
        case .payBill:
            return "Pay bill"
        case .learnServices:
            return "Learn about services"
        case .findResources:
            return "Find patient resources"
        case .accessMedicalImages:
            return "Access medical images"
        case .findDoctor:
            return "Find care options"
        case .continueApplication:
            return "Continue application"
        case .checkStatus:
            return "Check status"
        case .confirmProfile:
            return "Confirm profile"
        case .understandPage:
            return "Understand this page"
        }
    }

    var shortSummary: String {
        switch self {
        case .signIn:
            return "Use the main sign-in path."
        case .recoverAccount:
            return "Recover access safely."
        case .bookAppointment:
            return "Find scheduling or booking."
        case .checkResults:
            return "Look for results or updates."
        case .sendMessage:
            return "Open the message area."
        case .payBill:
            return "Review billing before paying."
        case .learnServices:
            return "Understand the main service options."
        case .findResources:
            return "Find instructions or patient resources."
        case .accessMedicalImages:
            return "Reach the image-access entry point."
        case .findDoctor:
            return "Compare care or provider options."
        case .continueApplication:
            return "Continue the current form or application."
        case .checkStatus:
            return "Review current status or account updates."
        case .confirmProfile:
            return "Make sure the correct person is selected."
        case .understandPage:
            return "Orient yourself before taking action."
        }
    }
}

struct OwlGuideIntentOption: Identifiable {
    let intent: OwlGuideUserIntent
    let title: String
    let summary: String
    let isPrimary: Bool

    var id: String {
        intent.rawValue
    }
}

struct OwlGuideTaskThread {
    let selectedSkill: OwlGuideScenarioSkill
    let confidence: OwlGuideScenarioConfidence
    let chosenIntent: OwlGuideUserIntent
    let currentPageType: String
    let currentSuggestedNextStep: String
    let isConfirmed: Bool
    let appName: String
    let bundleIdentifier: String
    let browserHostname: String?
    let continuationSummary: String
}

enum OwlGuideGuidedStepGroundingStatus {
    case axGroundedPreciseTarget
    case regionLevelFallback
    case textOnlyFallback

    var displayName: String {
        switch self {
        case .axGroundedPreciseTarget:
            return "AX-grounded precise target"
        case .regionLevelFallback:
            return "Region-level fallback"
        case .textOnlyFallback:
            return "Text-only fallback"
        }
    }
}

enum OwlGuideRelayPresentationMode {
    case preciseTargetOverlay
    case regionLevelGuidanceOverlay
    case clarificationCardOnly

    var displayName: String {
        switch self {
        case .preciseTargetOverlay:
            return "Precise target overlay"
        case .regionLevelGuidanceOverlay:
            return "Region-level guidance overlay"
        case .clarificationCardOnly:
            return "Clarification card only"
        }
    }
}

enum OwlGuideGuidedStepTargetType {
    case control
    case contentArea

    var displayName: String {
        switch self {
        case .control:
            return "Control"
        case .contentArea:
            return "Content area"
        }
    }
}

enum OwlGuideGuidedTargetOrigin: String {
    case recommendedTarget = "recommended-target"
    case axLocalCandidate = "ax-local-candidate"
    case screenRegionCandidate = "screen-region-candidate"
    case derivedContentAnchor = "derived-content-anchor"
    case unknown = "unknown"

    var displayName: String {
        rawValue
    }
}

struct OwlGuideGuidedStepGrounding {
    let primaryTargetLocalElementID: String?
    let fallbackTargetLocalElementID: String?
    let status: OwlGuideGuidedStepGroundingStatus
    let origin: OwlGuideGuidedTargetOrigin
    let targetType: OwlGuideGuidedStepTargetType?
    let reason: String
    let confidenceNote: String
    let downgradeReason: String?

    var relayPresentationMode: OwlGuideRelayPresentationMode {
        switch status {
        case .axGroundedPreciseTarget:
            return .preciseTargetOverlay
        case .regionLevelFallback:
            return .regionLevelGuidanceOverlay
        case .textOnlyFallback:
            return .clarificationCardOnly
        }
    }

    var hasConcreteLocalTarget: Bool {
        primaryTargetLocalElementID != nil && status != .textOnlyFallback
    }
}

struct OwlGuideGuidedStep {
    let title: String
    let nextStep: String
    let safetyNote: String?
    let clarificationQuestion: String?
    let grounding: OwlGuideGuidedStepGrounding
}

struct OwlGuideScenarioGuidance {
    let context: OwlGuideScenarioContext
    let firstResponse: OwlGuideFirstResponse
}
