import Foundation

enum FrontendActionKnowledge {
    static let clickActionValue = "click"
    static let typeActionValue = "type"

    static let fillAliases: Set<String> = ["fill", "fill_text", "input", "type"]
    static let instructionAliases: Set<String> = ["instruction", "focus_suggestion"]
    static let frontendSupportedActionTypes: Set<String> = [
        "highlight",
        "click",
        "fill",
        "fill_text",
        "input",
        "type",
        "speak",
        "instruction",
        "focus_suggestion"
    ]

    static let mappedResultFallbackPageSummary = "Owl Guide has one suggested next step."
    static let mappedResultFallbackLikelyTask = "Continue this task safely"
    static let mappedGuidePlanFallbackTitle = "Safe next step"
}
