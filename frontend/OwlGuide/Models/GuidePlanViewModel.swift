import CoreGraphics
import Foundation

enum GuidePlanActionKind: String {
    case highlight
    case click
    case fillText
    case speak
    case instruction
    case unsupported
}

struct GuidePlanActionViewModel: Identifiable {
    let id: String
    let kind: GuidePlanActionKind
    let target: String?
    let text: String?
    let value: String?
    let relatedLocalElement: String?
    let visualBoundingBox: [Int]?
    let requiresConfirmation: Bool
    let isSupportedByFrontend: Bool
}

struct GuidePlanViewModel {
    let title: String
    let body: String
    let primaryActionText: String
    let confirmationQuestion: String
    let actions: [GuidePlanActionViewModel]
    let targetLabel: String?
    let targetRect: CGRect?
    let targetKind: String?
    let targetAccessibilityLabel: String?
    let confidence: Double?
    let riskLevel: String?
    let estimatedSteps: Int?
    let unsupportedActionTypes: [String]
}
