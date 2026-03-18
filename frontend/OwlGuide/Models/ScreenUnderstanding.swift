import Foundation

struct AppRuntimeIdentityDebugInfo {
    let bundleIdentifier: String
    let bundlePath: String
    let executablePath: String
    let signingState: String
    let signingDetail: String

    static let initial = AppRuntimeIdentityDebugInfo(
        bundleIdentifier: "Unavailable",
        bundlePath: "Unavailable",
        executablePath: "Unavailable",
        signingState: "Unknown",
        signingDetail: "Runtime app identity has not been inspected yet."
    )
}

enum OwlInvocationMode: String {
    case none = "No invocation yet"
    case manualPanelAnalysis = "Manual panel analysis"
    case explicitScreenReview = "Explicit screen review"
    case userRequestedHelp = "User request"
    case automaticAfterIdleTimeout = "Automatic after idle timeout"
}

enum OwlInteractionSessionState {
    case idle
    case awaitingUserIntent
    case capturingContext
    case analyzing
    case answered
    case needsClarification
    case fallbackShown
}

enum OwlReplyLanguageMode: String {
    case systemDefault = "System default"
    case matchedUserInput = "Match user input"
    case unknown = "Unknown"
}

enum ScreenUnderstandingState {
    case idle(String)
    case loading(String)
    case success(String)
    case failure(String)

    var statusTitle: String {
        switch self {
        case .idle:
            return "Idle"
        case .loading:
            return "Analyzing"
        case .success:
            return "Ready"
        case .failure:
            return "Error"
        }
    }

    var message: String {
        switch self {
        case .idle(let message), .loading(let message), .success(let message), .failure(let message):
            return message
        }
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }

        return false
    }
}

enum ScreenUnderstandingProgressStage {
    case idle
    case preparing
    case capturingScreenshot
    case sendingRequest
    case readingResponse
    case ready
    case failed

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .preparing:
            return "Preparing Analysis"
        case .capturingScreenshot:
            return "Capturing Window"
        case .sendingRequest:
            return "Asking Gemini"
        case .readingResponse:
            return "Building Guidance"
        case .ready:
            return "Ready"
        case .failed:
            return "Failed"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "Waiting for a new analysis request."
        case .preparing:
            return "Owl Guide is locking the current target window and local AX candidates for one grounded request."
        case .capturingScreenshot:
            return "Owl Guide is capturing the current target window image."
        case .sendingRequest:
            return "Owl Guide is sending the captured window plus grounded local candidates to Gemini."
        case .readingResponse:
            return "Owl Guide is decoding Gemini's response into structured guidance for this window."
        case .ready:
            return "The latest Gemini screen understanding result is ready for this target window."
        case .failed:
            return "The latest Gemini analysis did not complete successfully for this target window."
        }
    }
}

struct ScreenUnderstandingTargetSnapshot {
    let appName: String
    let bundleIdentifier: String
    let processIdentifier: String
    let windowTitle: String
    let windowRole: String
    let windowSubrole: String

    var displayWindowTitle: String {
        windowTitle == "Unavailable" ? "Untitled window" : windowTitle
    }
}

struct ScreenUnderstandingBounds: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct ScreenUnderstandingCandidate: Codable, Identifiable {
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

struct ScreenUnderstandingContext: Codable {
    let userRequest: String?
    let preferredResponseLanguageCode: String?
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let browserHostname: String?
    let browserContext: BrowserCaptureContext?
    let scenarioContext: OwlGuideScenarioContext
    let actionableCandidatesAvailable: Int
    let readableCandidatesAvailable: Int
    let topActionableElements: [ScreenUnderstandingCandidate]
    let topReadableElements: [ScreenUnderstandingCandidate]
}

struct ScreenUnderstandingRecommendedTarget: Decodable, Identifiable {
    let rank: Int
    let label: String
    let whyThisMatters: String
    let relatedLocalElement: String
    let intendedAction: String?
    let actionValue: String?
    let requiresConfirmation: Bool?
    /// Gemini-provided visual bounding box [y_min, x_min, y_max, x_max] normalized 0-1000.
    let visualBoundingBox: [Int]?

    var id: String {
        "\(rank)-\(label)"
    }

    /// Convert normalized bounding box [y_min, x_min, y_max, x_max] (0-1000) to a CGRect
    /// with values in 0.0-1.0 range: (x, y, width, height) where x/y is top-left.
    var visualBounds: CGRect? {
        guard let box = visualBoundingBox, box.count == 4 else { return nil }
        let yMin = CGFloat(box[0]) / 1000.0
        let xMin = CGFloat(box[1]) / 1000.0
        let yMax = CGFloat(box[2]) / 1000.0
        let xMax = CGFloat(box[3]) / 1000.0
        guard xMax > xMin, yMax > yMin else { return nil }
        return CGRect(x: xMin, y: yMin, width: xMax - xMin, height: yMax - yMin)
    }
}

enum ScreenUnderstandingLocalLinkStatus {
    case linkedActionable
    case linkedReadable
    case visualOnly
    case unresolved(String)

    var title: String {
        switch self {
        case .linkedActionable, .linkedReadable:
            return "AX-linked target"
        case .visualOnly, .unresolved:
            return "Visual-only target"
        }
    }

    var summary: String {
        switch self {
        case .linkedActionable:
            return "Linked to a local actionable element that Owl Guide can inspect and highlight."
        case .linkedReadable:
            return "Linked to a local readable element that Owl Guide can inspect and highlight."
        case .visualOnly:
            return "Visual-only target; screen-region grounding is not implemented yet."
        case .unresolved(let identifier):
            return "Local element id not found: \(identifier). Treating this as visual-only for now."
        }
    }

    var isLinked: Bool {
        switch self {
        case .linkedActionable, .linkedReadable:
            return true
        case .visualOnly, .unresolved:
            return false
        }
    }
}

struct ScreenUnderstandingResult: Decodable {
    let pageSummary: String
    let likelyUserGoal: String
    let recommendedTargets: [ScreenUnderstandingRecommendedTarget]
    let cautionNotes: [String]
}

enum AnalysisDebugPresentationMode: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case verbose = "Verbose"

    var id: String { rawValue }
}

enum VerificationSnapshotStatus: String {
    case pass = "pass"
    case partial = "partial"
    case fail = "fail"
    case notApplicable = "n/a"
}

struct VerificationSnapshotField: Identifiable {
    let key: String
    let title: String
    let status: VerificationSnapshotStatus
    let detail: String?

    var id: String { key }
}

enum BrowserAttemptState: String {
    case attempted = "attempted"
    case skipped = "skipped"
    case notApplicable = "not_applicable"
}

enum BrowserResultState: String {
    case success = "success"
    case failed = "failed"
    case skipped = "skipped"
}

enum EffectiveContextState: String {
    case browserAware = "browser-aware"
    case browserAwareWithGenericGrounding = "browser-aware + generic grounding"
    case genericFallback = "generic fallback"
    case genericOnly = "generic only"
}

enum AnalysisEvidenceState: String {
    case collecting = "collecting"
    case frozen = "frozen"
    case superseded = "superseded"
}

struct VerificationSnapshotRecord {
    let evidenceState: AnalysisEvidenceState
    let browserAttemptState: BrowserAttemptState
    let browserResultState: BrowserResultState
    let effectiveContextState: EffectiveContextState
    let browserErrorCode: String?
    let fields: [VerificationSnapshotField]
}

struct ScreenUnderstandingReadinessItem: Identifiable {
    let id: String
    let title: String
    let isReady: Bool
    let detail: String
}

struct ScreenUnderstandingReadiness {
    let items: [ScreenUnderstandingReadinessItem]
    let blockingReason: String?

    static let initial = ScreenUnderstandingReadiness(
        items: [],
        blockingReason: "Checking what Owl Guide needs before it can analyze the current screen."
    )

    var canAnalyze: Bool {
        !items.isEmpty && items.allSatisfy(\.isReady)
    }
}

enum GeminiModelSource: String {
    case environmentOverride = "Environment override"
    case savedLocalSelection = "Saved local selection"
    case builtInDefault = "Built-in default"

    var detail: String {
        switch self {
        case .environmentOverride:
            return "Using GEMINI_MODEL from the current app environment."
        case .savedLocalSelection:
            return "Using a Gemini model saved locally in Owl Guide."
        case .builtInDefault:
            return "Using Owl Guide's built-in Gemini model default."
        }
    }
}

enum ScreenUnderstandingPayloadMode: String, CaseIterable, Identifiable {
    case normal = "Normal payload"
    case minimal = "Minimal payload"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .normal:
            return "Send Owl Guide's compact default candidate set."
        case .minimal:
            return "Send at most 3 actionable and 3 readable candidates for debugging."
        }
    }
}

enum ScreenUnderstandingAnalysisMode: String {
    case normal = "Normal analysis mode"
    case simplifiedHighComplexity = "Simplified high-complexity mode"

    var detail: String {
        switch self {
        case .normal:
            return "Use Owl Guide's standard one-request screen-understanding contract."
        case .simplifiedHighComplexity:
            return "Use a shorter one-request contract that prefers a smaller successful result on dense screens."
        }
    }
}

struct ScreenUnderstandingPayloadRoutingDiagnostics {
    let reason: String
    let totalCandidatesEvaluated: Int
    let genericCandidateCount: Int
    let genericCandidateRatio: Double
    let containerOrWindowControlCount: Int
    let containerOrWindowControlRatio: Double
    let topCandidatesMostlyGeneric: Bool
    let meaningfulReadableCandidateCount: Int

    static let initial = ScreenUnderstandingPayloadRoutingDiagnostics(
        reason: "No automatic payload routing decision yet.",
        totalCandidatesEvaluated: 0,
        genericCandidateCount: 0,
        genericCandidateRatio: 0,
        containerOrWindowControlCount: 0,
        containerOrWindowControlRatio: 0,
        topCandidatesMostlyGeneric: false,
        meaningfulReadableCandidateCount: 0
    )
}

struct ScreenUnderstandingComplexityDiagnostics {
    let reason: String
    let sampledCandidateCount: Int
    let filteredUsefulElementCount: Int
    let actionableCandidateCount: Int
    let readableCandidateCount: Int
    let genericCandidateRatio: Double
    let containerOrWindowControlRatio: Double
    let topCandidatesMostlyGeneric: Bool
    let screenshotLongEdge: Int
    let sendImageByteCount: Int
    let routingConfidence: OwlGuideScenarioConfidence

    static let initial = ScreenUnderstandingComplexityDiagnostics(
        reason: "No complexity-aware analysis decision yet.",
        sampledCandidateCount: 0,
        filteredUsefulElementCount: 0,
        actionableCandidateCount: 0,
        readableCandidateCount: 0,
        genericCandidateRatio: 0,
        containerOrWindowControlRatio: 0,
        topCandidatesMostlyGeneric: false,
        screenshotLongEdge: 0,
        sendImageByteCount: 0,
        routingConfidence: .low
    )
}

enum GeminiParserOutcome: String {
    case none = "No parse attempt yet"
    case fullJSON = "Full JSON recovered"
    case nonJSONText = "Non-JSON text"
    case partialJSON = "Partial or truncated JSON"
    case schemaMismatch = "Schema mismatch"
}

enum GeminiAPIKeySource: String {
    case environment = "Environment"
    case keychain = "Saved in Owl Guide"
    case infoPlist = "App Bundle"
    case none = "Missing"

    var detail: String {
        switch self {
        case .environment:
            return "Using GEMINI_API_KEY from the current app environment."
        case .keychain:
            return "Using a Gemini API key saved locally in Owl Guide."
        case .infoPlist:
            return "Using a Gemini API key from the app bundle configuration."
        case .none:
            return "No usable Gemini API key is available yet."
        }
    }
}

enum ScreenUnderstandingFailureSource: String {
    case missingKey = "Missing key"
    case screenshotCapture = "Screenshot capture"
    case modelReturnedNonJSONText = "Model returned non-JSON text"
    case modelReturnedPartialJSON = "Model returned partial or truncated JSON"
    case modelReturnedInvalidSchemaShape = "Model returned invalid schema shape"
    case networkOrAPI = "Network / API"
    case unknown = "Unknown"
}

struct ScreenUnderstandingDebugInfo {
    let keySource: GeminiAPIKeySource
    let modelName: String
    let modelSource: GeminiModelSource
    let invocationMode: OwlInvocationMode
    let userRequestPresent: Bool
    let autoAnalysisFired: Bool
    let idleTimeoutSeconds: Int?
    let focusLockActive: Bool
    let draftTextPreserved: Bool
    let autoAnalysisUsedFreshCapture: Bool
    let timerRestartedDueToContextChange: Bool
    let replyLanguageMode: OwlReplyLanguageMode
    let preferredResponseLanguageCode: String?
    let payloadMode: ScreenUnderstandingPayloadMode
    let analysisMode: ScreenUnderstandingAnalysisMode
    let payloadRouting: ScreenUnderstandingPayloadRoutingDiagnostics
    let complexityDiagnostics: ScreenUnderstandingComplexityDiagnostics
    let browserCaptureAttempted: Bool
    let browserName: String?
    let browserFailureCategory: String?
    let browserContextUsageDescription: String
    let browserCurrentURL: String?
    let browserURLRetrievalStatus: String
    let browserPageTitle: String?
    let browserTitleRetrievalStatus: String
    let browserVisibleTextSummaryAvailable: Bool
    let browserTextSummaryStatus: String
    let browserPrimaryEntryPointCount: Int
    let screenshotCaptured: Bool
    let originalScreenshotMimeType: String
    let originalScreenshotWidth: Int?
    let originalScreenshotHeight: Int?
    let originalScreenshotByteCount: Int?
    let originalScreenshotProcessingDescription: String
    let sendImageMimeType: String
    let sendImageWidth: Int?
    let sendImageHeight: Int?
    let sendImageByteCount: Int?
    let sendImageDidDownscale: Bool?
    let sendImageUsedLossyCompression: Bool?
    let sendImageProcessingDescription: String
    let actionableCandidatesAvailable: Int
    let readableCandidatesAvailable: Int
    let actionableCandidatesSent: Int
    let readableCandidatesSent: Int
    let contextCharacterCount: Int
    let failureSource: ScreenUnderstandingFailureSource?
    let responseMimeType: String
    let responseSchemaModeEnabled: Bool
    let requestDiagnosticsNote: String
    let maxOutputTokens: Int
    let finishReason: String?
    let finishMessage: String?
    let promptTokenCount: Int?
    let outputTokenCount: Int?
    let totalTokenCount: Int?
    let totalElapsedTimeMilliseconds: Int?
    let screenshotPreparationTimeMilliseconds: Int?
    let geminiRoundTripTimeMilliseconds: Int?
    let httpStatusCode: Int?
    let transportError: String?
    let rawResponseLength: Int
    let parserOutcome: GeminiParserOutcome
    let requestSummary: String
    let rawResponseText: String
    let recoveredJSONText: String

    init(
        keySource: GeminiAPIKeySource,
        modelName: String,
        modelSource: GeminiModelSource,
        invocationMode: OwlInvocationMode = .none,
        userRequestPresent: Bool = false,
        autoAnalysisFired: Bool = false,
        idleTimeoutSeconds: Int? = nil,
        focusLockActive: Bool = false,
        draftTextPreserved: Bool = false,
        autoAnalysisUsedFreshCapture: Bool = false,
        timerRestartedDueToContextChange: Bool = false,
        replyLanguageMode: OwlReplyLanguageMode = .systemDefault,
        preferredResponseLanguageCode: String? = nil,
        payloadMode: ScreenUnderstandingPayloadMode,
        analysisMode: ScreenUnderstandingAnalysisMode,
        payloadRouting: ScreenUnderstandingPayloadRoutingDiagnostics = .initial,
        complexityDiagnostics: ScreenUnderstandingComplexityDiagnostics = .initial,
        browserCaptureAttempted: Bool = false,
        browserName: String? = nil,
        browserFailureCategory: String? = nil,
        browserContextUsageDescription: String = "Generic screenshot + AX context only",
        browserCurrentURL: String? = nil,
        browserURLRetrievalStatus: String = "Not attempted.",
        browserPageTitle: String? = nil,
        browserTitleRetrievalStatus: String = "Not attempted.",
        browserVisibleTextSummaryAvailable: Bool = false,
        browserTextSummaryStatus: String = "Not attempted.",
        browserPrimaryEntryPointCount: Int = 0,
        screenshotCaptured: Bool,
        originalScreenshotMimeType: String = "Unavailable",
        originalScreenshotWidth: Int? = nil,
        originalScreenshotHeight: Int? = nil,
        originalScreenshotByteCount: Int? = nil,
        originalScreenshotProcessingDescription: String = "No screenshot captured yet.",
        sendImageMimeType: String = "Unavailable",
        sendImageWidth: Int? = nil,
        sendImageHeight: Int? = nil,
        sendImageByteCount: Int? = nil,
        sendImageDidDownscale: Bool? = nil,
        sendImageUsedLossyCompression: Bool? = nil,
        sendImageProcessingDescription: String = "No Gemini send-image prepared yet.",
        actionableCandidatesAvailable: Int,
        readableCandidatesAvailable: Int,
        actionableCandidatesSent: Int,
        readableCandidatesSent: Int,
        contextCharacterCount: Int,
        failureSource: ScreenUnderstandingFailureSource?,
        responseMimeType: String,
        responseSchemaModeEnabled: Bool,
        requestDiagnosticsNote: String = "No Gemini request note yet.",
        maxOutputTokens: Int,
        finishReason: String?,
        finishMessage: String?,
        promptTokenCount: Int?,
        outputTokenCount: Int?,
        totalTokenCount: Int?,
        totalElapsedTimeMilliseconds: Int?,
        screenshotPreparationTimeMilliseconds: Int?,
        geminiRoundTripTimeMilliseconds: Int?,
        httpStatusCode: Int?,
        transportError: String?,
        rawResponseLength: Int,
        parserOutcome: GeminiParserOutcome,
        requestSummary: String,
        rawResponseText: String,
        recoveredJSONText: String
    ) {
        self.keySource = keySource
        self.modelName = modelName
        self.modelSource = modelSource
        self.invocationMode = invocationMode
        self.userRequestPresent = userRequestPresent
        self.autoAnalysisFired = autoAnalysisFired
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.focusLockActive = focusLockActive
        self.draftTextPreserved = draftTextPreserved
        self.autoAnalysisUsedFreshCapture = autoAnalysisUsedFreshCapture
        self.timerRestartedDueToContextChange = timerRestartedDueToContextChange
        self.replyLanguageMode = replyLanguageMode
        self.preferredResponseLanguageCode = preferredResponseLanguageCode
        self.payloadMode = payloadMode
        self.analysisMode = analysisMode
        self.payloadRouting = payloadRouting
        self.complexityDiagnostics = complexityDiagnostics
        self.browserCaptureAttempted = browserCaptureAttempted
        self.browserName = browserName
        self.browserFailureCategory = browserFailureCategory
        self.browserContextUsageDescription = browserContextUsageDescription
        self.browserCurrentURL = browserCurrentURL
        self.browserURLRetrievalStatus = browserURLRetrievalStatus
        self.browserPageTitle = browserPageTitle
        self.browserTitleRetrievalStatus = browserTitleRetrievalStatus
        self.browserVisibleTextSummaryAvailable = browserVisibleTextSummaryAvailable
        self.browserTextSummaryStatus = browserTextSummaryStatus
        self.browserPrimaryEntryPointCount = browserPrimaryEntryPointCount
        self.screenshotCaptured = screenshotCaptured
        self.originalScreenshotMimeType = originalScreenshotMimeType
        self.originalScreenshotWidth = originalScreenshotWidth
        self.originalScreenshotHeight = originalScreenshotHeight
        self.originalScreenshotByteCount = originalScreenshotByteCount
        self.originalScreenshotProcessingDescription = originalScreenshotProcessingDescription
        self.sendImageMimeType = sendImageMimeType
        self.sendImageWidth = sendImageWidth
        self.sendImageHeight = sendImageHeight
        self.sendImageByteCount = sendImageByteCount
        self.sendImageDidDownscale = sendImageDidDownscale
        self.sendImageUsedLossyCompression = sendImageUsedLossyCompression
        self.sendImageProcessingDescription = sendImageProcessingDescription
        self.actionableCandidatesAvailable = actionableCandidatesAvailable
        self.readableCandidatesAvailable = readableCandidatesAvailable
        self.actionableCandidatesSent = actionableCandidatesSent
        self.readableCandidatesSent = readableCandidatesSent
        self.contextCharacterCount = contextCharacterCount
        self.failureSource = failureSource
        self.responseMimeType = responseMimeType
        self.responseSchemaModeEnabled = responseSchemaModeEnabled
        self.requestDiagnosticsNote = requestDiagnosticsNote
        self.maxOutputTokens = maxOutputTokens
        self.finishReason = finishReason
        self.finishMessage = finishMessage
        self.promptTokenCount = promptTokenCount
        self.outputTokenCount = outputTokenCount
        self.totalTokenCount = totalTokenCount
        self.totalElapsedTimeMilliseconds = totalElapsedTimeMilliseconds
        self.screenshotPreparationTimeMilliseconds = screenshotPreparationTimeMilliseconds
        self.geminiRoundTripTimeMilliseconds = geminiRoundTripTimeMilliseconds
        self.httpStatusCode = httpStatusCode
        self.transportError = transportError
        self.rawResponseLength = rawResponseLength
        self.parserOutcome = parserOutcome
        self.requestSummary = requestSummary
        self.rawResponseText = rawResponseText
        self.recoveredJSONText = recoveredJSONText
    }

    static let initial = ScreenUnderstandingDebugInfo(
        keySource: .none,
        modelName: "gemini-3.1-pro-preview",
        modelSource: .builtInDefault,
        invocationMode: .none,
        userRequestPresent: false,
        autoAnalysisFired: false,
        idleTimeoutSeconds: nil,
        focusLockActive: false,
        draftTextPreserved: false,
        autoAnalysisUsedFreshCapture: false,
        timerRestartedDueToContextChange: false,
        replyLanguageMode: .systemDefault,
        preferredResponseLanguageCode: nil,
        payloadMode: .normal,
        analysisMode: .normal,
        browserCaptureAttempted: false,
        browserName: nil,
        browserFailureCategory: nil,
        browserContextUsageDescription: "Generic screenshot + AX context only",
        browserCurrentURL: nil,
        browserURLRetrievalStatus: "Not attempted.",
        browserPageTitle: nil,
        browserTitleRetrievalStatus: "Not attempted.",
        browserVisibleTextSummaryAvailable: false,
        browserTextSummaryStatus: "Not attempted.",
        browserPrimaryEntryPointCount: 0,
        screenshotCaptured: false,
        originalScreenshotMimeType: "Unavailable",
        originalScreenshotWidth: nil,
        originalScreenshotHeight: nil,
        originalScreenshotByteCount: nil,
        originalScreenshotProcessingDescription: "No screenshot captured yet.",
        sendImageMimeType: "Unavailable",
        sendImageWidth: nil,
        sendImageHeight: nil,
        sendImageByteCount: nil,
        sendImageDidDownscale: nil,
        sendImageUsedLossyCompression: nil,
        sendImageProcessingDescription: "No Gemini send-image prepared yet.",
        actionableCandidatesAvailable: 0,
        readableCandidatesAvailable: 0,
        actionableCandidatesSent: 0,
        readableCandidatesSent: 0,
        contextCharacterCount: 0,
        failureSource: nil,
        responseMimeType: "application/json",
        responseSchemaModeEnabled: true,
        requestDiagnosticsNote: "No Gemini request note yet.",
        maxOutputTokens: 1024,
        finishReason: nil,
        finishMessage: nil,
        promptTokenCount: nil,
        outputTokenCount: nil,
        totalTokenCount: nil,
        totalElapsedTimeMilliseconds: nil,
        screenshotPreparationTimeMilliseconds: nil,
        geminiRoundTripTimeMilliseconds: nil,
        httpStatusCode: nil,
        transportError: nil,
        rawResponseLength: 0,
        parserOutcome: .none,
        requestSummary: "No Gemini request yet.",
        rawResponseText: "No Gemini response yet.",
        recoveredJSONText: "No recovered JSON yet."
    )
}
