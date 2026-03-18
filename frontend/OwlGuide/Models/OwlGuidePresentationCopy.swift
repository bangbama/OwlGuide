import Foundation

enum OwlGuidePresentationLanguage: String {
    case english = "en"
}

struct OwlGuidePresentationCopy {
    let language: OwlGuidePresentationLanguage
    let needsConfirmationLabel: String
    let safeNextStepLabel: String
    let loadingPreparingLabel: String
    let loadingCapturingLabel: String
    let loadingGeminiLabel: String
    let loadingReadingLabel: String
    let defaultPageTitle: String
    let defaultUnderstandingTitle: String
    let loadingPreparingMessage: String
    let loadingPreparingDetail: String
    let loadingCapturingMessage: String
    let loadingCapturingDetail: String
    let loadingSendingMessage: String
    let loadingSendingDetail: String
    let loadingReadingMessage: String
    let loadingReadingDetail: String

    // MVP default is fixed to English for the product-facing reminder card.
    // Future multilingual support should extend this type instead of reintroducing inline strings.
    static let mvpDefault = OwlGuidePresentationCopy(
        language: .english,
        needsConfirmationLabel: "Needs confirmation",
        safeNextStepLabel: "Safe next step",
        loadingPreparingLabel: "Preparing context",
        loadingCapturingLabel: "Capturing window",
        loadingGeminiLabel: "Asking Gemini",
        loadingReadingLabel: "Finalizing guidance",
        defaultPageTitle: "I'm looking at this page",
        defaultUnderstandingTitle: "Understanding this page",
        loadingPreparingMessage: "I'm getting oriented before I suggest a safe first step.",
        loadingPreparingDetail: "Please stay on this window for a moment.",
        loadingCapturingMessage: "I'm capturing the current window so I can read what is on this page.",
        loadingCapturingDetail: "Please keep this window visible while I capture it.",
        loadingSendingMessage: "I'm organizing the main points and a safe place to begin.",
        loadingSendingDetail: "Please stay on this window. You do not need to act yet."
        ,
        loadingReadingMessage: "I'm turning the page into one clear next step for you.",
        loadingReadingDetail: "I'm almost ready."
    )
}
