import AppKit
@preconcurrency import ApplicationServices
import Foundation
import NaturalLanguage
import Security

struct AppBuildInfo {
    static let version = "2026-03-15-2118"
}

enum AccessibilityScanState {
    case idle(String)
    case success(String)
    case empty(String)
    case failure(String)

    var statusTitle: String {
        switch self {
        case .idle:
            return "Idle"
        case .success:
            return "Complete"
        case .empty:
            return "Empty"
        case .failure:
            return "Error"
        }
    }

    var message: String {
        switch self {
        case .idle(let message), .success(let message), .empty(let message), .failure(let message):
            return message
        }
    }
}

enum AXSelectionSource: String {
    case raw = "Raw AX Tree"
    case filtered = "Filtered Useful Elements"
    case actionable = "Top Actionable Elements"
    case readable = "Top Readable Elements"
}

struct AXSelectedElementInspection {
    let source: AXSelectionSource
    let element: AXElementNode
    let score: Int?
    let reasonTags: [String]
}

struct OverlayPreviewItem: Identifiable {
    let id: UUID
    let rank: Int
    let label: String
    let caption: String
    let frame: CGRect
    let targetWindowFrame: CGRect
    let style: OverlayPreviewStyle
}

enum OverlayPreviewStyle {
    case precise
    case region
}

struct RelayReminderCard {
    let statusLabel: String
    let title: String
    let message: String
    let detail: String?
    let targetWindowFrame: CGRect?
    let progressCurrentStep: Int?
    let progressTotalSteps: Int?
    let emphasis: OverlayReminderEmphasis
    let proposedActionType: String?
    let proposedActionValue: String?
    /// Callback triggered when the user taps "Perform Action" on the overlay card.
    let onExecuteAction: (() -> Void)?
}

enum OverlayReminderEmphasis {
    case loading
    case normal
    case caution
}

struct OverlayPresentationRequest {
    let reminderCard: RelayReminderCard?
    let showsOverlay: Bool
    let overlayItems: [OverlayPreviewItem]
    let showsAnchor: Bool
    let anchorFrame: CGRect?

    static let hidden = OverlayPresentationRequest(
        reminderCard: nil,
        showsOverlay: false,
        overlayItems: [],
        showsAnchor: false,
        anchorFrame: nil
    )
}

private struct ScreenUnderstandingPayloadRoutingDecision {
    let mode: ScreenUnderstandingPayloadMode
    let diagnostics: ScreenUnderstandingPayloadRoutingDiagnostics
}

private struct ScreenUnderstandingAnalysisDecision {
    let mode: ScreenUnderstandingAnalysisMode
    let diagnostics: ScreenUnderstandingComplexityDiagnostics
}

private struct GuidedStepGroundingCandidate {
    let candidateIdentifier: String
    let source: AXSelectionSource
    let element: AXElementNode
    let score: Int?
    let reasonTags: [String]
}

private enum RecommendedTargetMatchStrategy {
    case relatedLocalElement
    case labelFallback
}

private struct ResolvedRecommendedTarget {
    let candidateIdentifier: String
    let source: AXSelectionSource
    let element: AXElementNode
    let score: Int?
    let reasonTags: [String]
    let strategy: RecommendedTargetMatchStrategy
    let bounds: CGRect
}

private struct GroundedTargetState {
    let bounds: CGRect?
    let isReady: Bool
    let trackingElement: AXUIElement?
}

private struct GuidedStepGroundingSnapshot {
    let contentRevision: Int
    let targetWindowFrame: CGRect
    let actionableCandidates: [GuidedStepGroundingCandidate]
    let readableCandidates: [GuidedStepGroundingCandidate]

    var allCandidates: [GuidedStepGroundingCandidate] {
        actionableCandidates + readableCandidates
    }
}

private enum ReasoningConsistencySeverity {
    case high
    case medium
    case low
}

private struct ReasoningConsistencyIssue {
    let tag: String
    let severity: ReasoningConsistencySeverity
}

private struct OwlInvocationTargetSignature: Equatable {
    let processIdentifier: String
    let windowTitle: String
    let windowRole: String
    let windowSubrole: String
    let frame: CGRect?
}

@MainActor
final class AppViewModel: ObservableObject {
    private static let maskedSavedKeyText = "••••••••••••••••"
    private static let normalActionablePayloadLimit = 4
    private static let normalReadablePayloadLimit = 8
    private static let minimalActionablePayloadLimit = 3
    private static let minimalReadablePayloadLimit = 3
    private let presentationCopy = OwlGuidePresentationCopy.mvpDefault
    private static let simplifiedNormalActionablePayloadLimit = 2
    private static let simplifiedNormalReadablePayloadLimit = 4
    private static let simplifiedMinimalActionablePayloadLimit = 1
    private static let simplifiedMinimalReadablePayloadLimit = 2
    private static let owlPassiveAutoLookDelaySeconds = 30
    private static let owlTargetChangeRestartTolerance: CGFloat = 36
    private static let localAXTrackingEnabled = false

    @Published var isInspectorPresented = false
    @Published var geminiAPIKeyDraft: String
    @Published var owlUserRequestText: String
    @Published private(set) var isOwlInvocationPromptPresented: Bool
    @Published private(set) var owlInteractionState: OwlInteractionSessionState
    @Published private(set) var owlInvocationMode: OwlInvocationMode
    @Published private(set) var owlIdleCountdownStartTime: Date?
    @Published private(set) var owlUserInteractedBeforeAutoAnalysis: Bool
    @Published private(set) var owlAutoAnalysisFired: Bool
    @Published private(set) var owlFocusLockActive: Bool
    @Published private(set) var owlDraftTextPreserved: Bool
    @Published private(set) var owlAutoAnalysisUsedFreshCapture: Bool
    @Published private(set) var owlTimerRestartedDueToContextChange: Bool
    @Published private(set) var owlReplyLanguageMode: OwlReplyLanguageMode
    @Published private(set) var owlPreferredResponseLanguageCode: String?
    @Published private(set) var owlFallbackMessage: String?
    @Published private(set) var screenUnderstandingPayloadMode: ScreenUnderstandingPayloadMode
    @Published private(set) var hasSavedGeminiAPIKey: Bool
    @Published private(set) var permissionState: AccessibilityPermissionState
    @Published private(set) var permissionFeedbackText: String?
    @Published private(set) var currentFrontmostAppDebugInfo: FrontmostAppDebugInfo
    @Published private(set) var capturedExternalTargetDebugInfo: FrontmostAppDebugInfo
    @Published private(set) var capturedExternalTargetStatusText: String
    @Published private(set) var rawScannedElements: [AXElementNode]
    @Published private(set) var filteredUsefulElements: [AXElementNode]
    @Published private(set) var topActionableElements: [AXRankedElement]
    @Published private(set) var topReadableElements: [AXRankedElement]
    @Published private(set) var actionableCandidateCount: Int
    @Published private(set) var readableCandidateCount: Int
    @Published private(set) var selectedElementInspection: AXSelectedElementInspection?
    @Published private(set) var selectedRecommendedTargetID: String?
    @Published private(set) var groundedTargetBounds: CGRect?
    @Published private(set) var activeAXElement: AXUIElement?
    @Published private(set) var isGroundedActionReady: Bool
    @Published private(set) var overlayPreviewRequested: Bool
    @Published private(set) var isOverlayPreviewVisible: Bool
    @Published private(set) var relayReminderCard: RelayReminderCard?
    @Published private(set) var relayPresentationDismissedByUser: Bool
    @Published private(set) var overlayPreviewItems: [OverlayPreviewItem]
    @Published private(set) var overlayPreviewStatusText: String
    @Published private(set) var windowAnchorRequested: Bool
    @Published private(set) var isWindowAnchorVisible: Bool
    @Published private(set) var overlayAnchorFrame: CGRect?
    @Published private(set) var windowAnchorStatusText: String
    @Published private(set) var overlayPresentationRequest: OverlayPresentationRequest
    @Published private(set) var screenUnderstandingReadiness: ScreenUnderstandingReadiness
    @Published private(set) var screenUnderstandingReadinessFeedbackText: String?
    @Published private(set) var appRuntimeIdentityDebugInfo: AppRuntimeIdentityDebugInfo
    @Published private(set) var screenUnderstandingState: ScreenUnderstandingState
    @Published private(set) var screenUnderstandingProgressStage: ScreenUnderstandingProgressStage
    @Published private(set) var frozenVerificationSnapshot: VerificationSnapshotRecord?
    @Published private(set) var screenUnderstandingTargetSnapshot: ScreenUnderstandingTargetSnapshot?
    @Published private(set) var screenScenarioGuidance: OwlGuideScenarioGuidance?
    @Published private(set) var scenarioIntentOptions: [OwlGuideIntentOption]
    @Published private(set) var currentTaskThread: OwlGuideTaskThread?
    @Published private(set) var guidedStepResponse: OwlGuideGuidedStep?
    @Published private(set) var latestGuidePlan: GuidePlanViewModel?
    @Published private(set) var backendHealthStatusText: String

    /// Convenience accessor for the arrow guide controller.
    var guidedStepNextStepText: String? {
        guidedStepResponse?.nextStep
    }
    @Published private(set) var lastScenarioContext: OwlGuideScenarioContext?
    @Published private(set) var screenUnderstandingResult: ScreenUnderstandingResult?
    @Published private(set) var screenUnderstandingDebugInfo: ScreenUnderstandingDebugInfo
    @Published private(set) var scanState: AccessibilityScanState
    @Published private(set) var didHitScanNodeLimit: Bool
    @Published private(set) var scanChildLookupFailureCount: Int

    var prepareForFreshAnalysis: (() -> Void)?

    private let permissionManager: PermissionManager
    private let frontmostAppDetector: FrontmostAppDetector
    private let accessibilityScanner: AccessibilityScanner
    private let axResultNormalizer: AXResultNormalizer
    private let axCandidateRanker: AXCandidateRanker
    private let scenarioSkillRouter: ScenarioSkillRouter
    private let browserContextCaptureService: BrowserContextCaptureService
    private let windowScreenshotService: WindowScreenshotService
    private let geminiScreenUnderstandingService: GeminiScreenUnderstandingService
    private let backendScreenUnderstandingService: BackendScreenUnderstandingService
    private let scanConfiguration: AccessibilityScanConfiguration
    private let backendSessionID: String
    private var activeElementTrackingTimer: Timer?
    private var lastNonSelfRunningApplication: NSRunningApplication?
    private var capturedExternalWindowElement: AXUIElement?
    private var capturedExternalWindowFrame: CGRect?
    private var targetContentRevision = 0
    private var analysisGroundingSnapshot: GuidedStepGroundingSnapshot?
    private var invocationIdleTask: Task<Void, Never>?
    private var slowResponseFallbackTask: Task<Void, Never>?
    private var owlInvocationTargetSignature: OwlInvocationTargetSignature?
    private var owlPromptDismissalWasExplicit = false
    private var lastResolvedRelayReminderCard: RelayReminderCard?
    private var analysisPresentationTargetWindowFrame: CGRect?
    private var currentScreenUnderstandingContext: ScreenUnderstandingContext?

    init(
        permissionManager: PermissionManager = PermissionManager(),
        frontmostAppDetector: FrontmostAppDetector = FrontmostAppDetector(),
        accessibilityScanner: AccessibilityScanner = AccessibilityScanner(),
        axResultNormalizer: AXResultNormalizer = AXResultNormalizer(),
        axCandidateRanker: AXCandidateRanker = AXCandidateRanker(),
        scenarioSkillRouter: ScenarioSkillRouter = ScenarioSkillRouter(),
        browserContextCaptureService: BrowserContextCaptureService = BrowserContextCaptureService(),
        windowScreenshotService: WindowScreenshotService = WindowScreenshotService(),
        geminiScreenUnderstandingService: GeminiScreenUnderstandingService = GeminiScreenUnderstandingService(),
        backendScreenUnderstandingService: BackendScreenUnderstandingService = BackendScreenUnderstandingService(),
        scanConfiguration: AccessibilityScanConfiguration = .default
    ) {
        self.permissionManager = permissionManager
        self.frontmostAppDetector = frontmostAppDetector
        self.accessibilityScanner = accessibilityScanner
        self.axResultNormalizer = axResultNormalizer
        self.axCandidateRanker = axCandidateRanker
        self.scenarioSkillRouter = scenarioSkillRouter
        self.browserContextCaptureService = browserContextCaptureService
        self.windowScreenshotService = windowScreenshotService
        self.geminiScreenUnderstandingService = geminiScreenUnderstandingService
        self.backendScreenUnderstandingService = backendScreenUnderstandingService
        self.scanConfiguration = scanConfiguration
        self.backendSessionID = UUID().uuidString
        let initialPermissionState = permissionManager.currentState()
        let hasSavedGeminiAPIKey = geminiScreenUnderstandingService.hasUserProvidedAPIKey()
        let modelConfiguration = geminiScreenUnderstandingService.currentModelConfiguration()
        self.geminiAPIKeyDraft = ""
        self.owlUserRequestText = ""
        self.isOwlInvocationPromptPresented = false
        self.owlInteractionState = .idle
        self.owlInvocationMode = .none
        self.owlIdleCountdownStartTime = nil
        self.owlUserInteractedBeforeAutoAnalysis = false
        self.owlAutoAnalysisFired = false
        self.owlFocusLockActive = false
        self.owlDraftTextPreserved = false
        self.owlAutoAnalysisUsedFreshCapture = false
        self.owlTimerRestartedDueToContextChange = false
        self.owlReplyLanguageMode = .systemDefault
        self.owlPreferredResponseLanguageCode = nil
        self.owlFallbackMessage = nil
        self.screenUnderstandingPayloadMode = .normal
        self.hasSavedGeminiAPIKey = hasSavedGeminiAPIKey
        self.permissionState = initialPermissionState
        self.currentFrontmostAppDebugInfo = .empty
        self.capturedExternalTargetDebugInfo = .empty
        self.capturedExternalTargetStatusText = "No external target has been captured yet."
        self.rawScannedElements = []
        self.filteredUsefulElements = []
        self.topActionableElements = []
        self.topReadableElements = []
        self.actionableCandidateCount = 0
        self.readableCandidateCount = 0
        self.selectedElementInspection = nil
        self.selectedRecommendedTargetID = nil
        self.groundedTargetBounds = nil
        self.activeAXElement = nil
        self.isGroundedActionReady = false
        self.overlayPreviewRequested = false
        self.isOverlayPreviewVisible = false
        self.relayReminderCard = nil
        self.relayPresentationDismissedByUser = false
        self.overlayPreviewItems = []
        self.overlayPreviewStatusText = "Overlay preview is off."
        self.windowAnchorRequested = false
        self.isWindowAnchorVisible = false
        self.overlayAnchorFrame = nil
        self.windowAnchorStatusText = "Window anchor is off."
        self.overlayPresentationRequest = .hidden
        self.screenUnderstandingReadiness = .initial
        self.screenUnderstandingReadinessFeedbackText = nil
        self.appRuntimeIdentityDebugInfo = Self.inspectRuntimeIdentity()
        self.screenUnderstandingState = .idle("Run a captured-window AX scan first, then analyze the current screen with Gemini.")
        self.screenUnderstandingProgressStage = .idle
        self.frozenVerificationSnapshot = nil
        self.screenUnderstandingTargetSnapshot = nil
        self.screenScenarioGuidance = nil
        self.scenarioIntentOptions = []
        self.currentTaskThread = nil
        self.guidedStepResponse = nil
        self.latestGuidePlan = nil
        self.backendHealthStatusText = "No backend health check yet."
        self.lastScenarioContext = nil
        self.screenUnderstandingResult = nil
        self.screenUnderstandingDebugInfo = ScreenUnderstandingDebugInfo(
            keySource: geminiScreenUnderstandingService.currentKeySource(),
            modelName: modelConfiguration.name,
            modelSource: modelConfiguration.source,
            invocationMode: .none,
            userRequestPresent: false,
            autoAnalysisFired: false,
            idleTimeoutSeconds: Self.owlPassiveAutoLookDelaySeconds,
            focusLockActive: false,
            draftTextPreserved: false,
            autoAnalysisUsedFreshCapture: false,
            timerRestartedDueToContextChange: false,
            replyLanguageMode: .systemDefault,
            preferredResponseLanguageCode: nil,
            payloadMode: .normal,
            analysisMode: .normal,
            screenshotCaptured: false,
            originalScreenshotMimeType: "Unavailable",
            originalScreenshotWidth: nil,
            originalScreenshotHeight: nil,
            originalScreenshotByteCount: nil,
            originalScreenshotProcessingDescription: "No screenshot captured yet.",
            actionableCandidatesAvailable: 0,
            readableCandidatesAvailable: 0,
            actionableCandidatesSent: 0,
            readableCandidatesSent: 0,
            contextCharacterCount: 0,
            failureSource: nil,
            responseMimeType: GeminiScreenUnderstandingService.responseMimeType,
            responseSchemaModeEnabled: GeminiScreenUnderstandingService.responseSchemaModeEnabled,
            requestDiagnosticsNote: GeminiScreenUnderstandingService.requestDiagnosticsNote,
            maxOutputTokens: GeminiScreenUnderstandingService.maxOutputTokens,
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
        self.scanState = .idle("Capture an external target, then scan its window's accessibility children up to depth \(scanConfiguration.maxDepth).")
        self.didHitScanNodeLimit = false
        self.scanChildLookupFailureCount = 0
        self.currentScreenUnderstandingContext = nil
        syncGeminiKeyDraftFromStoredState()
    }

    var scanDepthLimit: Int {
        scanConfiguration.maxDepth
    }

    var scanNodeLimit: Int {
        scanConfiguration.maxNodeCount
    }

    var rankedDisplayCap: Int {
        axCandidateRanker.displayCap
    }

    var isGeminiAPIKeyEditable: Bool {
        !hasSavedGeminiAPIKey
    }

    var canSaveGeminiAPIKey: Bool {
        isGeminiAPIKeyEditable && !geminiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var geminiMVPModelName: String {
        GeminiScreenUnderstandingService.previewModel
    }

    var activeBackendMode: BackendDataSourceMode {
        AppSettings.shared.backendDataSourceMode
    }

    var activeBackendModeTitle: String {
        activeBackendMode.displayName
    }

    var activeBackendModeDetail: String {
        activeBackendMode.detail
    }

    var currentTaskThreadStatusTitle: String {
        guard let currentTaskThread else {
            return "No task thread"
        }

        return currentTaskThread.isConfirmed ? "Confirmed task thread" : "Tentative task thread"
    }

    var screenUnderstandingLinkedRecommendationCount: Int {
        guard let result = screenUnderstandingResult else {
            return 0
        }

        return result.recommendedTargets.filter { localLinkStatus(for: $0).isLinked }.count
    }

    var screenUnderstandingVisualOnlyRecommendationCount: Int {
        guard let result = screenUnderstandingResult else {
            return 0
        }

        return result.recommendedTargets.filter { !localLinkStatus(for: $0).isLinked }.count
    }

    var screenUnderstandingUnresolvedRecommendationCount: Int {
        guard let result = screenUnderstandingResult else {
            return 0
        }

        return result.recommendedTargets.filter {
            if case .unresolved = localLinkStatus(for: $0) {
                return true
            }

            return false
        }.count
    }

    var screenUnderstandingGroundingStatusTitle: String {
        guard let result = screenUnderstandingResult else {
            return "No result yet"
        }

        guard !result.recommendedTargets.isEmpty else {
            return "No target recommendation"
        }

        if let effectiveGrounding = effectiveGuidedStepGrounding,
           effectiveGrounding.hasConcreteLocalTarget {
            let linkedCount = screenUnderstandingLinkedRecommendationCount
            let totalCount = result.recommendedTargets.count

            if linkedCount == totalCount && totalCount > 0 && effectiveGrounding.origin == .recommendedTarget {
                return "Grounded locally"
            }

            return "Partially grounded"
        }

        let linkedCount = screenUnderstandingLinkedRecommendationCount
        let totalCount = result.recommendedTargets.count

        if linkedCount == totalCount {
            return "Grounded locally"
        }

        if linkedCount > 0 {
            return "Partially grounded"
        }

        return "Visual understanding only"
    }

    var screenUnderstandingGroundingSummary: String {
        guard let result = screenUnderstandingResult else {
            return "Run screen analysis to see how well Gemini recommendations map back to local elements."
        }

        guard !result.recommendedTargets.isEmpty else {
            return "Owl Guide returned a screen understanding result, but it did not return a specific target recommendation yet."
        }

        let linkedCount = screenUnderstandingLinkedRecommendationCount
        let visualOnlyCount = screenUnderstandingVisualOnlyRecommendationCount
        let unresolvedCount = screenUnderstandingUnresolvedRecommendationCount

        if let effectiveGrounding = effectiveGuidedStepGrounding,
           effectiveGrounding.hasConcreteLocalTarget {
            switch effectiveGrounding.origin {
            case .recommendedTarget:
                return "The current guided step is grounded to a locally inspectable recommended target that Owl Guide can highlight."
            case .axLocalCandidate:
                return "Current recommendation cards may still be visual-only, but Owl Guide resolved this guided step to a separate local AX candidate from the same analyzed snapshot."
            case .screenRegionCandidate, .derivedContentAnchor:
                return "Current recommendation cards may still be visual-only, but Owl Guide resolved this guided step to a broader grounded local region from the same analyzed snapshot."
            case .unknown:
                break
            }
        }

        if linkedCount == result.recommendedTargets.count {
            return "All current recommendations are linked to local elements that Owl Guide can inspect. Linked recommendations can also use the current overlay path."
        }

        if linkedCount > 0 {
            if unresolvedCount > 0 {
                return "\(linkedCount) recommendation(s) are linked locally. \(visualOnlyCount) are not grounded locally yet, including \(unresolvedCount) with a local id Owl Guide could not match."
            }

            return "\(linkedCount) recommendation(s) are linked locally. \(visualOnlyCount) still rely on screenshot understanding only."
        }

        if unresolvedCount > 0 {
            return "Current recommendations are not grounded locally. \(unresolvedCount) referenced local ids that Owl Guide could not match, so they are being treated as visual-only for now."
        }

        return "Current recommendations rely on screenshot understanding only. Owl Guide is not yet grounding them to local inspectable elements."
    }

    var selectedRecommendedTargetLabel: String? {
        guard let result = screenUnderstandingResult,
              let selectedRecommendedTargetID,
              let selectedTarget = result.recommendedTargets.first(where: { $0.id == selectedRecommendedTargetID }) else {
            return nil
        }

        return selectedTarget.label
    }

    var selectedRecommendedTargetSummary: String? {
        guard let result = screenUnderstandingResult,
              let selectedRecommendedTargetID,
              let selectedTarget = result.recommendedTargets.first(where: { $0.id == selectedRecommendedTargetID }) else {
            return nil
        }

        switch localLinkStatus(for: selectedTarget) {
        case .linkedActionable, .linkedReadable:
            return "This recommendation is linked to the selected local element and uses the current overlay path."
        case .visualOnly:
            return "This recommendation is visual-only. Owl Guide cannot show a local overlay for it yet."
        case .unresolved:
            return "This recommendation referenced a local id Owl Guide could not match, so it remains visual-only."
        }
    }

    var relayPresentationModeTitle: String {
        effectiveGuidedStepGrounding?.relayPresentationMode.displayName ?? "No guided-step relay mode"
    }

    var relayHasConcreteLocalTarget: Bool {
        effectiveGuidedStepGrounding?.hasConcreteLocalTarget ?? false
    }

    var relayConfidenceNote: String {
        effectiveGuidedStepGrounding?.confidenceNote ?? "No guided-step grounding confidence note yet."
    }

    var relayDowngradeReason: String {
        effectiveGuidedStepGrounding?.downgradeReason ?? "None"
    }

    var guidedTargetOriginTitle: String {
        effectiveGuidedStepGrounding?.origin.displayName ?? "unknown"
    }

    var guidedTargetOriginSummary: String {
        guard let effectiveGrounding = effectiveGuidedStepGrounding else {
            return "No grounded target source is available yet."
        }

        switch effectiveGrounding.origin {
        case .recommendedTarget:
            return "The current guided step is using a target from the recommended targets list."
        case .axLocalCandidate:
            return "The current guided step is using a separate AX-resolved local candidate instead of the recommended targets list."
        case .screenRegionCandidate:
            return "The current guided step is using a broader screen-region candidate instead of one exact recommended target."
        case .derivedContentAnchor:
            return "The current guided step is using a derived content anchor from the current analyzed page region."
        case .unknown:
            return "Owl Guide does not yet have a trustworthy source for the current guided target."
        }
    }

    var guidedTargetOriginNeedsExplanation: Bool {
        screenUnderstandingVisualOnlyRecommendationCount > 0
            && screenUnderstandingLinkedRecommendationCount == 0
            && relayHasConcreteLocalTarget
            && guidedTargetOriginTitle != OwlGuideGuidedTargetOrigin.recommendedTarget.displayName
    }

    var guidedStepHighlightStatusTitle: String {
        effectiveGuidedStepGrounding?.status.displayName ?? "Text-only fallback"
    }

    var guidedStepConcreteTargetStatusText: String {
        relayHasConcreteLocalTarget ? "Resolved" : "Not resolved"
    }

    var guidedStepTargetTypeTitle: String? {
        effectiveGuidedStepGrounding?.targetType?.displayName
    }

    var guidedStepGroundingReasonText: String {
        effectiveGuidedStepGrounding?.reason ?? "No guided-step grounding reason yet."
    }

    var relayGeminiReplySummary: String {
        guard let result = screenUnderstandingResult else {
            return "No Gemini screen-understanding result yet."
        }

        return result.pageSummary
    }

    private var effectiveGuidedStepGrounding: OwlGuideGuidedStepGrounding? {
        guard let rawGrounding = guidedStepResponse?.grounding else {
            return nil
        }

        let hasPrimaryIdentifier = rawGrounding.primaryTargetLocalElementID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        switch rawGrounding.status {
        case .textOnlyFallback:
            return rawGrounding
        case .regionLevelFallback:
            if !hasPrimaryIdentifier && rawGrounding.origin == .recommendedTarget {
                return downgradedTruthfulGrounding(
                    from: rawGrounding,
                    status: .textOnlyFallback,
                    origin: .unknown,
                    reason: "Owl Guide understands the general step, but it does not have a stable grounded region to point to honestly."
                )
            }
            return rawGrounding
        case .axGroundedPreciseTarget:
            if !rawGrounding.hasConcreteLocalTarget {
                return downgradedTruthfulGrounding(
                    from: rawGrounding,
                    status: .textOnlyFallback,
                    origin: .unknown,
                    reason: "Owl Guide cannot honestly present a precise target because the current step does not have a stable local anchor."
                )
            }

            if rawGrounding.origin == .recommendedTarget,
               screenUnderstandingLinkedRecommendationCount == 0,
               screenUnderstandingVisualOnlyRecommendationCount > 0 {
                return downgradedTruthfulGrounding(
                    from: rawGrounding,
                    status: .textOnlyFallback,
                    origin: .unknown,
                    reason: "The current recommendation list is still visual-only, so Owl Guide is not claiming a precise grounded target from that list."
                )
            }

            return rawGrounding
        }
    }

    var screenUnderstandingDiagnosticNote: String {
        switch screenUnderstandingDiagnosticCategory {
        case "Output-side truncation / partial JSON":
            return "Gemini appears to be stopping before a full JSON result is returned. This points more to output truncation than to routing confidence."
        case "Image-size / request-payload pressure":
            return "The Gemini send-image is still relatively large. Image size or request payload pressure may still be contributing to slow or fragile runs."
        case "High-complexity screen fallback":
            return "Owl Guide detected a dense screen and switched to a shorter response contract to improve the odds of a valid result."
        case "Low routing-confidence / classification risk":
            return "Routing confidence is low. Owl Guide should keep the first response factual and avoid strong domain claims."
        case "Transport / API failure":
            return "The request appears to have failed at the transport or API layer rather than in the routed scenario layer."
        default:
            break
        }

        if lastScenarioContext?.confidence == .medium {
            return "Routing confidence is medium. Owl Guide should keep domain wording hedged until the page intent is clearer."
        }

        return "No obvious truncation or screenshot-size warning is visible in the current diagnostics."
    }

    var screenUnderstandingDiagnosticCategory: String {
        if screenUnderstandingDebugInfo.parserOutcome == .partialJSON || screenUnderstandingDebugInfo.finishReason == "MAX_TOKENS" {
            return "Output-side truncation / partial JSON"
        }

        if screenUnderstandingDebugInfo.analysisMode == .simplifiedHighComplexity {
            return "High-complexity screen fallback"
        }

        if screenUnderstandingDebugInfo.failureSource == .networkOrAPI {
            if let sendImageByteCount = screenUnderstandingDebugInfo.sendImageByteCount,
               sendImageByteCount >= 1_500_000 {
                return "Image-size / request-payload pressure"
            }

            return "Transport / API failure"
        }

        if let sendImageByteCount = screenUnderstandingDebugInfo.sendImageByteCount,
           sendImageByteCount >= 1_500_000,
           screenUnderstandingDebugInfo.finishReason == nil {
            return "Image-size / request-payload pressure"
        }

        if lastScenarioContext?.confidence == .low {
            return "Low routing-confidence / classification risk"
        }

        return "No clear dominant issue"
    }

    var screenUnderstandingFailureStageLabel: String {
        switch currentAnalysisFailureStage {
        case .none:
            return "None"
        case .contextPreparation:
            return "Context preparation"
        case .windowCapture:
            return "Window capture"
        case .geminiAnalysis:
            return "Gemini analysis"
        }
    }

    var screenUnderstandingFailureStageSummary: String {
        switch currentAnalysisFailureStage {
        case .none:
            return "No current failure is being shown."
        case .contextPreparation:
            return "Owl Guide has not gathered enough local page context yet, so Gemini did not receive a usable analysis request."
        case .windowCapture:
            return "Owl Guide found the target, but could not read or capture the current window reliably enough to continue."
        case .geminiAnalysis:
            return "Owl Guide already sent the page to Gemini, but this run did not produce a usable final result."
        }
    }

    var screenUnderstandingLikelyFailureCause: String {
        if screenUnderstandingDebugInfo.finishReason == "MAX_TOKENS"
            || screenUnderstandingDebugInfo.parserOutcome == .partialJSON {
            return "The Gemini response was cut off before Owl Guide could use it."
        }

        if screenUnderstandingDebugInfo.failureSource == .networkOrAPI {
            return "The Gemini request did not complete reliably."
        }

        if screenUnderstandingDebugInfo.parserOutcome == .schemaMismatch
            || screenUnderstandingDebugInfo.parserOutcome == .nonJSONText {
            return "Gemini returned a response format Owl Guide could not use."
        }

        switch currentAnalysisFailureStage {
        case .contextPreparation:
            return "The local page context was not ready yet."
        case .windowCapture:
            return "The current window or screenshot was not stable enough to read."
        case .geminiAnalysis:
            return "Gemini started reviewing the page, but Owl Guide did not get a usable final result."
        case .none:
            return "No current failure is being shown."
        }
    }

    var owlUserFacingFailureTitle: String? {
        switch currentAnalysisFailureStage {
        case .none:
            return nil
        case .contextPreparation:
            return "I'm still preparing this page"
        case .windowCapture:
            return "I can't read this window reliably yet"
        case .geminiAnalysis:
            return "I'm still understanding this page"
        }
    }

    var owlUserFacingFailureDetail: String? {
        switch currentAnalysisFailureStage {
        case .none:
            return nil
        case .contextPreparation:
            return "The page context still is not ready enough for a stable analysis request."
        case .windowCapture:
            return "This looks more like a window capture or screenshot stability problem."
        case .geminiAnalysis:
            if screenUnderstandingDebugInfo.finishReason == "MAX_TOKENS"
                || screenUnderstandingDebugInfo.parserOutcome == .partialJSON {
                return "Gemini started reviewing the page, but the response was cut off before Owl Guide could use it."
            }

            if screenUnderstandingDebugInfo.failureSource == .networkOrAPI {
                return "Gemini started reviewing the page, but the request did not complete reliably."
            }

            if screenUnderstandingDebugInfo.parserOutcome == .schemaMismatch
                || screenUnderstandingDebugInfo.parserOutcome == .nonJSONText {
                return "Gemini started reviewing the page, but the returned format was not usable."
            }

            return "Gemini started reviewing the page, but Owl Guide did not get a usable final result."
        }
    }

    var verificationSnapshotFields: [VerificationSnapshotField] {
        if let frozenVerificationSnapshot {
            return frozenVerificationSnapshot.fields
        }

        return buildVerificationSnapshotRecord(evidenceState: .collecting).fields
    }

    var verificationSnapshotEvidenceStateTitle: String {
        frozenVerificationSnapshot?.evidenceState.rawValue ?? AnalysisEvidenceState.collecting.rawValue
    }

    private func buildVerificationSnapshotRecord(evidenceState: AnalysisEvidenceState) -> VerificationSnapshotRecord {
        let browserFieldCount = [
            screenUnderstandingDebugInfo.browserCurrentURL != nil,
            screenUnderstandingDebugInfo.browserPageTitle != nil,
            screenUnderstandingDebugInfo.browserVisibleTextSummaryAvailable
        ].filter { $0 }.count
        let pageType = screenScenarioGuidance?.context.likelyPageType ?? lastScenarioContext?.likelyPageType ?? "Unavailable"
        let confidence = screenScenarioGuidance?.context.confidence ?? lastScenarioContext?.confidence
        let fallbackReason = fallbackReasonSummary
        let reasoningIssues = reasoningConsistencyIssues
        let browserAttemptState = currentBrowserAttemptState
        let browserResultState = currentBrowserResultState
        let effectiveContextState = currentEffectiveContextState
        let browserErrorCode = currentBrowserErrorCode

        let fields = [
            VerificationSnapshotField(
                key: "context_source",
                title: "Context source",
                status: effectiveContextSnapshotStatus(effectiveContextState),
                detail: effectiveContextState.rawValue
            ),
            VerificationSnapshotField(
                key: "browser_attempted",
                title: "Browser-aware attempted",
                status: browserAttemptSnapshotStatus(browserAttemptState),
                detail: browserAttemptState.rawValue
            ),
            VerificationSnapshotField(
                key: "browser_status",
                title: "Browser-aware status",
                status: browserResultSnapshotStatus(browserResultState, browserErrorCode: browserErrorCode, fieldCount: browserFieldCount),
                detail: browserResultDetail(browserResultState, browserErrorCode: browserErrorCode, fieldCount: browserFieldCount)
            ),
            VerificationSnapshotField(
                key: "browser_name",
                title: "Browser name",
                status: browserNameSnapshotStatus(browserAttemptState),
                detail: screenUnderstandingDebugInfo.browserName ?? (browserAttemptState == .attempted ? "missing" : "n/a")
            ),
            VerificationSnapshotField(
                key: "url_status",
                title: "URL status",
                status: retrievalSnapshotStatus(screenUnderstandingDebugInfo.browserURLRetrievalStatus, attemptState: browserAttemptState),
                detail: retrievalSnapshotDetail(screenUnderstandingDebugInfo.browserURLRetrievalStatus, attemptState: browserAttemptState, fallbackCode: browserErrorCode)
            ),
            VerificationSnapshotField(
                key: "title_status",
                title: "Title status",
                status: retrievalSnapshotStatus(screenUnderstandingDebugInfo.browserTitleRetrievalStatus, attemptState: browserAttemptState),
                detail: retrievalSnapshotDetail(screenUnderstandingDebugInfo.browserTitleRetrievalStatus, attemptState: browserAttemptState, fallbackCode: browserErrorCode)
            ),
            VerificationSnapshotField(
                key: "text_status",
                title: "Text summary status",
                status: retrievalSnapshotStatus(screenUnderstandingDebugInfo.browserTextSummaryStatus, attemptState: browserAttemptState),
                detail: retrievalSnapshotDetail(screenUnderstandingDebugInfo.browserTextSummaryStatus, attemptState: browserAttemptState, fallbackCode: browserErrorCode)
            ),
            VerificationSnapshotField(
                key: "host_status",
                title: "Host / domain status",
                status: hostSnapshotStatus(attemptState: browserAttemptState),
                detail: hostSnapshotDetail(attemptState: browserAttemptState, browserErrorCode: browserErrorCode)
            ),
            VerificationSnapshotField(
                key: "page_type",
                title: "Page type",
                status: pageType == "Unavailable" ? .fail : (pageType == "General page" ? .partial : .pass),
                detail: pageType
            ),
            VerificationSnapshotField(
                key: "confidence",
                title: "Confidence",
                status: confidenceSnapshotStatus(confidence),
                detail: confidence?.displayName ?? "Unavailable"
            ),
            VerificationSnapshotField(
                key: "relay_mode",
                title: "Relay mode",
                status: relayModeSnapshotStatus,
                detail: relayPresentationModeTitle
            ),
            VerificationSnapshotField(
                key: "concrete_target",
                title: "Concrete local target",
                status: concreteTargetSnapshotStatus,
                detail: concreteTargetSnapshotDetail
            ),
            VerificationSnapshotField(
                key: "reasoning",
                title: "Inconsistent reasoning flag",
                status: reasoningSnapshotStatus,
                detail: reasoningIssues.isEmpty
                    ? "none"
                    : reasoningIssues.prefix(2).map(\.tag).joined(separator: ", ")
            ),
            VerificationSnapshotField(
                key: "fallback",
                title: "Fallback reason",
                status: fallbackReason == nil ? .notApplicable : fallbackReasonSnapshotStatus,
                detail: fallbackReason ?? "none"
            )
        ]

        return VerificationSnapshotRecord(
            evidenceState: evidenceState,
            browserAttemptState: browserAttemptState,
            browserResultState: browserResultState,
            effectiveContextState: effectiveContextState,
            browserErrorCode: browserErrorCode,
            fields: fields
        )
    }

    private enum AnalysisFailureStage {
        case none
        case contextPreparation
        case windowCapture
        case geminiAnalysis
    }

    private var currentAnalysisFailureStage: AnalysisFailureStage {
        let isFailureState: Bool
        if case .failure = screenUnderstandingState {
            isFailureState = true
        } else {
            isFailureState = false
        }

        if owlFallbackMessage == nil && !isFailureState {
            return .none
        }

        if let failureSource = screenUnderstandingDebugInfo.failureSource {
            switch failureSource {
            case .missingKey:
                return .contextPreparation
            case .screenshotCapture:
                return .windowCapture
            case .modelReturnedNonJSONText,
                 .modelReturnedPartialJSON,
                 .modelReturnedInvalidSchemaShape,
                 .networkOrAPI,
                 .unknown:
                return .geminiAnalysis
            }
        }

        if !screenUnderstandingReadiness.canAnalyze
            || rawScannedElements.isEmpty
            || screenUnderstandingState.message.contains("Scan Captured Window Children")
            || screenUnderstandingState.message.contains("still missing something before it can analyze this screen") {
            return .contextPreparation
        }

        if screenUnderstandingState.message.contains("usable process id for screenshot capture")
            || screenUnderstandingState.message.contains("valid window bounds for screenshot capture")
            || screenUnderstandingState.message.contains("refresh the captured target before automatic analysis")
            || screenUnderstandingState.message.contains("reliably read this window") {
            return .windowCapture
        }

        if owlFallbackMessage != nil || isFailureState {
            return .geminiAnalysis
        }

        return .none
    }

    var reasoningConsistencyFlags: [String] {
        reasoningConsistencyIssues.map(\.tag)
    }

    private var reasoningConsistencyIssues: [ReasoningConsistencyIssue] {
        guard let scenarioGuidance = screenScenarioGuidance,
              let result = screenUnderstandingResult else {
            return []
        }

        let pageSummary = result.pageSummary.lowercased()
        let contextRecognition = scenarioGuidance.firstResponse.contextRecognition.lowercased()
        let likelyUserGoal = result.likelyUserGoal.lowercased()
        let primaryTask = scenarioGuidance.firstResponse.primaryLikelyTask.lowercased()
        let backupTask = scenarioGuidance.firstResponse.backupLikelyTask.lowercased()
        let pageType = scenarioGuidance.context.likelyPageType.lowercased()
        let groundingSummary = screenUnderstandingGroundingSummary.lowercased()
        let effectiveGrounding = effectiveGuidedStepGrounding
        let allTargetsVisualOnly = screenUnderstandingLinkedRecommendationCount == 0
            && !result.recommendedTargets.isEmpty
        var issues: [ReasoningConsistencyIssue] = []

        let homepageSignals = ["home page", "homepage", "navigation", "portal", "services", "hospital", "clinic", "organization", "medical imaging"]
        if containsAny(in: pageSummary, keywords: homepageSignals),
           (scenarioGuidance.context.confidence == .low || contextRecognition.contains("not fully sure") || pageType == "general page") {
            issues.append(ReasoningConsistencyIssue(tag: "summary_vs_context_conflict", severity: .medium))
        }

        if pageType == "information / guide page",
           containsAny(in: "\(primaryTask) | \(likelyUserGoal)", keywords: ["application", "form", "apply", "check status"]) {
            issues.append(ReasoningConsistencyIssue(tag: "page_type_vs_task_conflict", severity: .medium))
        }

        if screenUnderstandingDebugInfo.browserContextUsageDescription.contains("Browser-aware"),
           !relayHasConcreteLocalTarget,
           relayPresentationModeTitle == "Clarification card only",
           relayDowngradeReason == "None" {
            issues.append(ReasoningConsistencyIssue(tag: "browser_context_vs_grounding_conflict", severity: .low))
        }

        if containsAny(
            in: groundingSummary,
            keywords: [
                "screenshot understanding only",
                "not yet grounding",
                "not grounded locally",
                "visual-only"
            ]
        ),
           let effectiveGrounding,
           effectiveGrounding.status == .axGroundedPreciseTarget,
           !guidedTargetOriginNeedsExplanation {
            issues.append(ReasoningConsistencyIssue(tag: "grounding_vs_precise_overlay_conflict", severity: .high))
        }

        if allTargetsVisualOnly,
           let effectiveGrounding,
           effectiveGrounding.status == .axGroundedPreciseTarget,
           effectiveGrounding.origin == .recommendedTarget {
            issues.append(ReasoningConsistencyIssue(tag: "recommended_targets_vs_guided_target_conflict", severity: .high))
        }

        let visitingInfoKeywords = [
            "visiting hours", "visitor rules", "visitor guidance", "hospital visiting", "patient visit", "visiting info", "visitor hours"
        ]
        let imagingTaskKeywords = ["imaging", "medical images", "service options", "access medical images"]
        if containsAny(in: "\(pageSummary) | \(likelyUserGoal)", keywords: visitingInfoKeywords),
           containsAny(in: "\(primaryTask) | \(backupTask)", keywords: imagingTaskKeywords) {
            issues.append(ReasoningConsistencyIssue(tag: "summary_vs_task_cluster_conflict", severity: .high))
        }

        let actionHeavyTaskKeywords = ["application", "form", "apply", "status", "account", "medical images", "image access"]
        let infoTaskKeywords = ["information", "guide", "resource", "learn", "visiting", "visitor", "patient guidance"]
        if ["information / guide page", "medical services page"].contains(pageType),
           containsAny(in: primaryTask, keywords: actionHeavyTaskKeywords),
           !containsAny(in: primaryTask, keywords: infoTaskKeywords) {
            issues.append(ReasoningConsistencyIssue(tag: "page_type_vs_first_response_conflict", severity: .medium))
        }

        return uniqueReasoningIssues(issues)
    }

    var compactRoutingSummaryText: String {
        let pageType = screenScenarioGuidance?.context.likelyPageType ?? "Unavailable"
        let confidence = screenScenarioGuidance?.context.confidence.displayName ?? "Unavailable"
        let relayMode = relayPresentationModeTitle
        return "Page type: \(pageType) • Confidence: \(confidence) • Relay: \(relayMode)"
    }

    private var relayModeSnapshotStatus: VerificationSnapshotStatus {
        switch effectiveGuidedStepGrounding?.relayPresentationMode {
        case .preciseTargetOverlay:
            return .pass
        case .regionLevelGuidanceOverlay, .clarificationCardOnly:
            return .partial
        case .none:
            return .notApplicable
        }
    }

    private var concreteTargetSnapshotStatus: VerificationSnapshotStatus {
        if relayHasConcreteLocalTarget {
            return .pass
        }

        switch effectiveGuidedStepGrounding?.relayPresentationMode {
        case .regionLevelGuidanceOverlay, .clarificationCardOnly:
            return .partial
        case .preciseTargetOverlay:
            return .fail
        case .none:
            return .notApplicable
        }
    }

    private var concreteTargetSnapshotDetail: String {
        if relayHasConcreteLocalTarget {
            return "resolved • \(guidedTargetOriginTitle)"
        }

        switch effectiveGuidedStepGrounding?.relayPresentationMode {
        case .regionLevelGuidanceOverlay:
            return "region fallback"
        case .clarificationCardOnly:
            return "text-only or clarification"
        case .preciseTargetOverlay:
            return "missing precise target"
        case .none:
            return "n/a"
        }
    }

    private var fallbackReasonSummary: String? {
        if relayDowngradeReason != "None" {
            return compactSnapshotDetail(from: relayDowngradeReason)
        }

        if let failureSource = screenUnderstandingDebugInfo.failureSource?.rawValue {
            return failureSource
        }

        if let browserFailureCategory = screenUnderstandingDebugInfo.browserFailureCategory {
            return browserFailureCategory
        }

        return nil
    }

    private var fallbackReasonSnapshotStatus: VerificationSnapshotStatus {
        if screenUnderstandingDebugInfo.failureSource != nil {
            return .fail
        }

        return .partial
    }

    private var reasoningSnapshotStatus: VerificationSnapshotStatus {
        if reasoningConsistencyIssues.contains(where: { $0.severity == .high }) {
            return .fail
        }

        if !reasoningConsistencyIssues.isEmpty {
            return .partial
        }

        return .pass
    }

    private func downgradedTruthfulGrounding(
        from grounding: OwlGuideGuidedStepGrounding,
        status: OwlGuideGuidedStepGroundingStatus,
        origin: OwlGuideGuidedTargetOrigin,
        reason: String
    ) -> OwlGuideGuidedStepGrounding {
        OwlGuideGuidedStepGrounding(
            primaryTargetLocalElementID: status == .textOnlyFallback ? nil : grounding.primaryTargetLocalElementID,
            fallbackTargetLocalElementID: status == .textOnlyFallback ? nil : grounding.fallbackTargetLocalElementID,
            status: status,
            origin: origin,
            targetType: status == .textOnlyFallback ? nil : grounding.targetType,
            reason: reason,
            confidenceNote: "Owl Guide is showing the most conservative grounding state that the current local evidence can support.",
            downgradeReason: reason
        )
    }

    private func uniqueReasoningIssues(_ issues: [ReasoningConsistencyIssue]) -> [ReasoningConsistencyIssue] {
        var seen = Set<String>()
        return issues.filter { issue in
            seen.insert(issue.tag).inserted
        }
    }

    private var currentBrowserAttemptState: BrowserAttemptState {
        if screenUnderstandingDebugInfo.browserCaptureAttempted {
            return .attempted
        }

        if isSupportedBrowserBundleIdentifier(screenUnderstandingTargetSnapshot?.bundleIdentifier) {
            return .notApplicable
        }

        return .skipped
    }

    private var currentBrowserResultState: BrowserResultState {
        switch currentBrowserAttemptState {
        case .attempted:
            return screenUnderstandingDebugInfo.browserContextUsageDescription.contains("Browser-aware")
                ? .success
                : .failed
        case .skipped, .notApplicable:
            return .skipped
        }
    }

    private var currentEffectiveContextState: EffectiveContextState {
        let usage = screenUnderstandingDebugInfo.browserContextUsageDescription

        if usage.contains("Browser-aware context + generic grounding") {
            return .browserAwareWithGenericGrounding
        }

        if usage.contains("Browser-aware") {
            return .browserAware
        }

        if currentBrowserAttemptState == .attempted {
            return .genericFallback
        }

        return .genericOnly
    }

    private var currentBrowserErrorCode: String? {
        if currentBrowserAttemptState != .attempted {
            if isSupportedBrowserBundleIdentifier(screenUnderstandingTargetSnapshot?.bundleIdentifier) {
                return "unsupported_browser"
            }

            return "native_app_skipped"
        }

        if let category = screenUnderstandingDebugInfo.browserFailureCategory {
            switch category {
            case "permission":
                return "permission_denied"
            case "automation failed":
                return "automation_failed"
            case "empty result":
                return "empty_result"
            case "fallback used":
                return "fallback_used"
            case "unsupported browser":
                return "unsupported_browser"
            default:
                break
            }
        }

        let urlStatus = screenUnderstandingDebugInfo.browserURLRetrievalStatus.lowercased()
        let titleStatus = screenUnderstandingDebugInfo.browserTitleRetrievalStatus.lowercased()
        let textStatus = screenUnderstandingDebugInfo.browserTextSummaryStatus.lowercased()

        if urlStatus.contains("failed") || titleStatus.contains("failed") || textStatus.contains("failed") {
            return "automation_failed"
        }

        if currentBrowserAttemptState == .attempted,
           screenUnderstandingDebugInfo.browserCurrentURL != nil,
           hostSnapshotValue == nil {
            return "missing_host"
        }

        if currentBrowserAttemptState == .attempted,
           currentEffectiveContextState == .genericFallback {
            return "fallback_used"
        }

        return nil
    }

    private var hostSnapshotValue: String? {
        if let hostname = screenScenarioGuidance?.context.browserHostname, !hostname.isEmpty {
            return hostname
        }

        if let hostname = lastScenarioContext?.browserHostname, !hostname.isEmpty {
            return hostname
        }

        if let currentURL = screenUnderstandingDebugInfo.browserCurrentURL,
           let host = URL(string: currentURL)?.host,
           !host.isEmpty {
            return host.lowercased()
        }

        return nil
    }

    private func browserAttemptSnapshotStatus(_ state: BrowserAttemptState) -> VerificationSnapshotStatus {
        switch state {
        case .attempted:
            return .pass
        case .skipped, .notApplicable:
            return .notApplicable
        }
    }

    private func browserResultSnapshotStatus(
        _ state: BrowserResultState,
        browserErrorCode: String?,
        fieldCount: Int
    ) -> VerificationSnapshotStatus {
        switch state {
        case .success:
            return fieldCount >= 3 ? .pass : .partial
        case .failed:
            return .fail
        case .skipped:
            return .notApplicable
        }
    }

    private func browserResultDetail(
        _ state: BrowserResultState,
        browserErrorCode: String?,
        fieldCount: Int
    ) -> String {
        switch state {
        case .success:
            return fieldCount >= 3 ? "success" : "partial success"
        case .failed:
            return browserErrorCode ?? "failed"
        case .skipped:
            return currentBrowserErrorCode ?? "n/a"
        }
    }

    private func effectiveContextSnapshotStatus(_ state: EffectiveContextState) -> VerificationSnapshotStatus {
        switch state {
        case .browserAware, .browserAwareWithGenericGrounding:
            return .pass
        case .genericFallback:
            return .partial
        case .genericOnly:
            return .notApplicable
        }
    }

    private func browserNameSnapshotStatus(_ attemptState: BrowserAttemptState) -> VerificationSnapshotStatus {
        switch attemptState {
        case .attempted:
            return screenUnderstandingDebugInfo.browserName == nil ? .fail : .pass
        case .skipped, .notApplicable:
            return .notApplicable
        }
    }

    private func retrievalSnapshotStatus(_ statusText: String, attemptState: BrowserAttemptState) -> VerificationSnapshotStatus {
        switch attemptState {
        case .attempted:
            let lowercased = statusText.lowercased()
            if lowercased.contains("retrieved") {
                return .pass
            }
            if lowercased.contains("failed") || lowercased.contains("unavailable") {
                return .fail
            }
            return .partial
        case .skipped, .notApplicable:
            return .notApplicable
        }
    }

    private func retrievalSnapshotDetail(_ statusText: String, attemptState: BrowserAttemptState, fallbackCode: String?) -> String {
        switch attemptState {
        case .attempted:
            let compact = compactSnapshotDetail(from: statusText)
            if compact == "failed", let fallbackCode {
                return fallbackCode
            }
            return compact
        case .skipped, .notApplicable:
            return "n/a"
        }
    }

    private func hostSnapshotStatus(attemptState: BrowserAttemptState) -> VerificationSnapshotStatus {
        switch attemptState {
        case .attempted:
            return hostSnapshotValue == nil ? .fail : .pass
        case .skipped, .notApplicable:
            return .notApplicable
        }
    }

    private func hostSnapshotDetail(attemptState: BrowserAttemptState, browserErrorCode: String?) -> String {
        switch attemptState {
        case .attempted:
            return hostSnapshotValue ?? browserErrorCode ?? "missing_host"
        case .skipped, .notApplicable:
            return "n/a"
        }
    }

    private func isSupportedBrowserBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.apple.Safari" || bundleIdentifier == "com.google.Chrome"
    }

    private func browserAwareStatus(fieldCount: Int, attempted: Bool) -> VerificationSnapshotStatus {
        guard attempted else {
            return .notApplicable
        }

        if screenUnderstandingDebugInfo.browserContextUsageDescription.contains("Browser-aware"), fieldCount >= 2 {
            return fieldCount == 3 ? .pass : .partial
        }

        if fieldCount > 0 {
            return .partial
        }

        return .fail
    }

    private func browserAwareStatusDetail(fieldCount: Int, attempted: Bool) -> String {
        guard attempted else {
            return "skipped"
        }

        if let category = screenUnderstandingDebugInfo.browserFailureCategory,
           !screenUnderstandingDebugInfo.browserContextUsageDescription.contains("Browser-aware") {
            return category
        }

        switch fieldCount {
        case 3:
            return "full browser context"
        case 1...2:
            return "partial browser context"
        default:
            return "fallback used"
        }
    }

    private func retrievalSnapshotStatus(_ statusText: String, attempted: Bool) -> VerificationSnapshotStatus {
        let lowercased = statusText.lowercased()

        if !attempted || lowercased.contains("skipped") || lowercased == "not attempted." {
            return .notApplicable
        }

        if lowercased.contains("retrieved") {
            return .pass
        }

        if lowercased.contains("failed") {
            return .fail
        }

        return .partial
    }

    private func confidenceSnapshotStatus(_ confidence: OwlGuideScenarioConfidence?) -> VerificationSnapshotStatus {
        switch confidence {
        case .high:
            return .pass
        case .medium, .low:
            return .partial
        case .none:
            return .notApplicable
        }
    }

    private func compactSnapshotDetail(from text: String) -> String {
        let trimmed = text
            .replacingOccurrences(of: "Retrieved", with: "retrieved")
            .replacingOccurrences(of: "Failed:", with: "")
            .replacingOccurrences(of: "Skipped:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count <= 60 {
            return trimmed
        }

        let prefix = trimmed.prefix(57).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)…"
    }

    private func containsAny(in text: String, keywords: [String]) -> Bool {
        let lowercased = text.lowercased()
        return keywords.contains { lowercased.contains($0.lowercased()) }
    }

    private var currentPayloadActionableLimit: Int {
        payloadActionableLimit(for: screenUnderstandingPayloadMode)
    }

    private var currentPayloadReadableLimit: Int {
        payloadReadableLimit(for: screenUnderstandingPayloadMode)
    }

    private var currentPayloadActionableCount: Int {
        min(topActionableElements.count, currentPayloadActionableLimit)
    }

    private var currentPayloadReadableCount: Int {
        min(topReadableElements.count, currentPayloadReadableLimit)
    }

    private func payloadActionableLimit(for mode: ScreenUnderstandingPayloadMode) -> Int {
        mode == .minimal ? Self.minimalActionablePayloadLimit : Self.normalActionablePayloadLimit
    }

    private func payloadReadableLimit(for mode: ScreenUnderstandingPayloadMode) -> Int {
        mode == .minimal ? Self.minimalReadablePayloadLimit : Self.normalReadablePayloadLimit
    }

    private func payloadActionableCount(for mode: ScreenUnderstandingPayloadMode) -> Int {
        min(topActionableElements.count, payloadActionableLimit(for: mode))
    }

    private func payloadReadableCount(for mode: ScreenUnderstandingPayloadMode) -> Int {
        min(topReadableElements.count, payloadReadableLimit(for: mode))
    }

    private func analysisActionableLimit(
        for payloadMode: ScreenUnderstandingPayloadMode,
        analysisMode: ScreenUnderstandingAnalysisMode
    ) -> Int {
        switch (payloadMode, analysisMode) {
        case (.normal, .normal):
            return Self.normalActionablePayloadLimit
        case (.minimal, .normal):
            return Self.minimalActionablePayloadLimit
        case (.normal, .simplifiedHighComplexity):
            return Self.simplifiedNormalActionablePayloadLimit
        case (.minimal, .simplifiedHighComplexity):
            return Self.simplifiedMinimalActionablePayloadLimit
        }
    }

    private func analysisReadableLimit(
        for payloadMode: ScreenUnderstandingPayloadMode,
        analysisMode: ScreenUnderstandingAnalysisMode
    ) -> Int {
        switch (payloadMode, analysisMode) {
        case (.normal, .normal):
            return Self.normalReadablePayloadLimit
        case (.minimal, .normal):
            return Self.minimalReadablePayloadLimit
        case (.normal, .simplifiedHighComplexity):
            return Self.simplifiedNormalReadablePayloadLimit
        case (.minimal, .simplifiedHighComplexity):
            return Self.simplifiedMinimalReadablePayloadLimit
        }
    }

    var isAwaitingUserIntent: Bool {
        owlInteractionState == .awaitingUserIntent
    }

    var owlPassiveAutoLookDelaySeconds: Int {
        Self.owlPassiveAutoLookDelaySeconds
    }

    var shouldShowOwlIdleCountdown: Bool {
        isOwlInvocationPromptPresented
            && owlInteractionState == .awaitingUserIntent
            && owlIdleCountdownStartTime != nil
            && !owlUserInteractedBeforeAutoAnalysis
            && !owlFocusLockActive
    }

    var owlVoicePlaceholderLabel: String {
        "Voice (later)"
    }

    private var trimmedOwlUserRequest: String? {
        let trimmed = owlUserRequestText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func toggleInspector() {
        isInspectorPresented.toggle()
    }

    func openDebugPanelFromDeveloperGesture() {
        cancelInvocationIdleTask()
        clearRelayPresentation()
        isOwlInvocationPromptPresented = false
        owlInteractionState = .idle
        owlIdleCountdownStartTime = nil
        owlFocusLockActive = false
        owlFallbackMessage = nil
        owlInvocationMode = .none
        owlAutoAnalysisFired = false
        if capturedExternalWindowElement == nil {
            captureExternalTarget()
        }
        isInspectorPresented = true
        NSApp.activate(ignoringOtherApps: true)
    }

    func beginOwlInvocation() {
        prepareForNewAnalysisRun()

        if owlInteractionState == .awaitingUserIntent {
            isOwlInvocationPromptPresented = true
            owlPromptDismissalWasExplicit = false
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        cancelInvocationIdleTask()

        if hasReplayableRelayPresentation {
            let analysisSignature = currentAnalysisTargetSignature()

            if let freshTarget = detectFreshExternalTarget() {
                applyDetectedExternalTarget(freshTarget, resetDependentState: false)
                let freshSignature = currentCapturedTargetSignature()

                if targetHasMateriallyChanged(from: analysisSignature, to: freshSignature) {
                    clearRelayPresentation()
                    presentOwlInvocationPrompt(
                        clearDraft: true,
                        preserveExistingTargetSignature: false
                    )
                    NSApp.activate(ignoringOtherApps: true)
                    return
                }
            }

            presentOwlInvocationPrompt(
                clearDraft: true,
                preserveExistingTargetSignature: true
            )
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        captureExternalTarget()
        refreshScreenUnderstandingReadiness()
        presentOwlInvocationPrompt(
            clearDraft: true,
            preserveExistingTargetSignature: false
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissRelayPresentationByUser() {
        relayPresentationDismissedByUser = true
        relayReminderCard = nil
        overlayPreviewRequested = false
        overlayPreviewItems = []
        overlayPreviewStatusText = "Reminder hidden."
        refreshOverlayPresentationRequest()
    }

    func dismissOwlInvocationPrompt() {
        owlPromptDismissalWasExplicit = true
        cancelInvocationIdleTask()
        isOwlInvocationPromptPresented = false
        owlInteractionState = .idle
        owlIdleCountdownStartTime = nil
        owlFocusLockActive = false
    }

    func handleOwlInvocationPromptPresentationChange(isPresented: Bool) {
        guard !isPresented else {
            DispatchQueue.main.async { [weak self] in
                self?.isOwlInvocationPromptPresented = true
                self?.owlPromptDismissalWasExplicit = false
            }
            return
        }

        guard owlInteractionState == .awaitingUserIntent else {
            DispatchQueue.main.async { [weak self] in
                self?.isOwlInvocationPromptPresented = false
                self?.owlPromptDismissalWasExplicit = false
            }
            return
        }

        if owlPromptDismissalWasExplicit {
            DispatchQueue.main.async { [weak self] in
                self?.dismissOwlInvocationPrompt()
                self?.owlPromptDismissalWasExplicit = false
            }
            return
        }

        markDraftPreservedIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.owlInteractionState == .awaitingUserIntent else {
                return
            }

            self.isOwlInvocationPromptPresented = true
        }
    }

    func noteOwlIntentPromptInteraction() {
        owlUserInteractedBeforeAutoAnalysis = true
        cancelInvocationIdleTask()
        owlIdleCountdownStartTime = nil
    }

    func noteOwlIntentFieldFocused() {
        owlFocusLockActive = true
        noteOwlIntentPromptInteraction()
    }

    func noteOwlPromptTapped() {
        noteOwlIntentPromptInteraction()
    }

    func noteOwlPromptRepositioned() {
        guard owlInteractionState == .awaitingUserIntent else {
            return
        }

        markDraftPreservedIfNeeded()
        noteOwlIntentPromptInteraction()
        isOwlInvocationPromptPresented = true
    }

    func noteOwlVoicePlaceholderPressed() {
        noteOwlIntentPromptInteraction()
    }

    func updateOwlUserRequestText(_ text: String) {
        owlUserRequestText = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            owlReplyLanguageMode = .matchedUserInput
            owlPreferredResponseLanguageCode = detectedLanguageCode(for: text)
            noteOwlIntentFieldFocused()
        } else {
            owlReplyLanguageMode = .systemDefault
            owlPreferredResponseLanguageCode = nil
        }
    }

    func submitOwlUserRequest() {
        let trimmed = owlUserRequestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        noteOwlIntentPromptInteraction()
        startInvocationAnalysis(
            mode: .userRequestedHelp,
            userRequest: trimmed,
            autoAnalysisFired: false
        )
    }

    func requestScreenLookFromPrompt() {
        noteOwlIntentPromptInteraction()
        let userRequest = trimmedOwlUserRequest ?? "请分析这个屏幕"
        startInvocationAnalysis(
            mode: .userRequestedHelp,
            userRequest: userRequest,
            autoAnalysisFired: false
        )
    }

    func closeInspector() {
        isInspectorPresented = false
    }

    private func startInvocationAnalysis(
        mode: OwlInvocationMode,
        userRequest: String?,
        autoAnalysisFired: Bool
    ) {
        owlInvocationMode = mode
        owlAutoAnalysisFired = autoAnalysisFired
        owlAutoAnalysisUsedFreshCapture = false
        owlInteractionState = .capturingContext
        owlIdleCountdownStartTime = nil
        owlFallbackMessage = nil
        isOwlInvocationPromptPresented = false
        analyzeCurrentScreen(userRequest: userRequest, invocationMode: mode, autoAnalysisFired: autoAnalysisFired)
    }

    private func cancelInvocationIdleTask() {
        invocationIdleTask?.cancel()
        invocationIdleTask = nil
    }

    private func startOwlIdleCountdown() {
        cancelInvocationIdleTask()
        owlIdleCountdownStartTime = Date()

        invocationIdleTask = Task { @MainActor [weak self] in
            let delayNanoseconds = UInt64(Self.owlPassiveAutoLookDelaySeconds) * 1_000_000_000
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self,
                  self.owlInteractionState == .awaitingUserIntent,
                  self.isOwlInvocationPromptPresented,
                  !self.owlUserInteractedBeforeAutoAnalysis,
                  !self.owlFocusLockActive else {
                return
            }

            self.owlAutoAnalysisFired = true
            self.startInvocationAnalysis(
                mode: .automaticAfterIdleTimeout,
                userRequest: nil,
                autoAnalysisFired: true
            )
        }
    }

    private func markDraftPreservedIfNeeded() {
        if !owlUserRequestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || owlFocusLockActive {
            owlDraftTextPreserved = true
        }
    }

    private func cancelSlowResponseFallbackTask() {
        slowResponseFallbackTask?.cancel()
        slowResponseFallbackTask = nil
    }

    func refreshPermissionStatus() {
        permissionState = permissionManager.currentState()
        appRuntimeIdentityDebugInfo = Self.inspectRuntimeIdentity()
        refreshScreenUnderstandingReadiness()
    }

    func refreshCurrentFrontmostAppDebugInfo() {
        let currentApplication = frontmostAppDetector.currentFrontmostApplication()
        currentFrontmostAppDebugInfo = frontmostAppDetector.captureDebugInfo(for: currentApplication)
    }

    func captureExternalTarget() {
        let currentApplication = frontmostAppDetector.currentFrontmostApplication()
        currentFrontmostAppDebugInfo = frontmostAppDetector.captureDebugInfo(for: currentApplication)

        if let currentApplication, !frontmostAppDetector.isOwlGuide(currentApplication) {
            lastNonSelfRunningApplication = currentApplication
            let capturedTarget = frontmostAppDetector.captureTarget(for: currentApplication)
            capturedExternalTargetDebugInfo = capturedTarget.debugInfo
            capturedExternalWindowElement = capturedTarget.windowElement
            capturedExternalWindowFrame = capturedTarget.windowFrame
            capturedExternalTargetStatusText = "Captured the current external target before Owl Guide became frontmost."
            hideOverlayPreview(statusText: "Overlay preview was hidden because the captured external target changed.")
            hideWindowAnchor(statusText: "Window anchor was hidden because the captured external target changed.")
            resetScanState()
            resetScreenUnderstandingState(message: "Captured target updated. Run a fresh AX scan before asking Gemini to analyze this screen.")
            refreshScreenUnderstandingReadiness()
            return
        }

        if let lastNonSelfRunningApplication, !lastNonSelfRunningApplication.isTerminated {
            let capturedTarget = frontmostAppDetector.captureTarget(for: lastNonSelfRunningApplication)
            capturedExternalTargetDebugInfo = capturedTarget.debugInfo
            capturedExternalWindowElement = capturedTarget.windowElement
            capturedExternalWindowFrame = capturedTarget.windowFrame
            capturedExternalTargetStatusText = "Owl Guide is frontmost, so the most recent non-OwlGuide target is being preserved."
            hideOverlayPreview(statusText: "Overlay preview was hidden because the captured external target changed.")
            hideWindowAnchor(statusText: "Window anchor was hidden because the captured external target changed.")
            resetScanState()
            resetScreenUnderstandingState(message: "Captured target updated. Run a fresh AX scan before asking Gemini to analyze this screen.")
            refreshScreenUnderstandingReadiness()
            return
        }

        capturedExternalTargetDebugInfo = .unavailable(message: "Owl Guide is frontmost and there is no cached external target yet.")
        capturedExternalTargetStatusText = "No cached external target is available yet. Open Owl Guide from another app first."
        capturedExternalWindowElement = nil
        capturedExternalWindowFrame = nil
        invalidateGroundingSnapshot()
        hideOverlayPreview(statusText: "Overlay preview was hidden because there is no captured external target.")
        hideWindowAnchor(statusText: "Window anchor was hidden because there is no captured external target.")
        rawScannedElements = []
        filteredUsefulElements = []
        topActionableElements = []
        topReadableElements = []
        actionableCandidateCount = 0
        readableCandidateCount = 0
        selectedElementInspection = nil
        selectedRecommendedTargetID = nil
        didHitScanNodeLimit = false
        scanChildLookupFailureCount = 0
        resetScreenUnderstandingState(message: "No captured external target is available yet. Open Owl Guide from another app first.")
        scanState = .failure("No captured external window is available yet. Open Owl Guide from another app first.")
        refreshScreenUnderstandingReadiness()
    }

    func noteActivatedApplication(_ application: NSRunningApplication) {
        guard !frontmostAppDetector.isOwlGuide(application) else { return }
        lastNonSelfRunningApplication = application
    }

    func requestAccessibilityPermission() {
        permissionManager.requestAccessibilityPermissionPrompt()
        permissionFeedbackText = "macOS should show the Accessibility permission prompt or take you toward the correct settings area."
        refreshPermissionStatus()
    }

    func openAccessibilitySettings() {
        if permissionManager.openAccessibilitySettings() {
            permissionFeedbackText = "System Settings should open to the Accessibility permissions area."
        } else {
            permissionFeedbackText = "Open System Settings > Privacy & Security > Accessibility manually if the shortcut does not work on this macOS version."
        }
    }

    func requestScreenRecordingPermission() {
        _ = permissionManager.requestScreenRecordingPermissionPrompt()
        screenUnderstandingReadinessFeedbackText = "macOS should show the Screen Recording prompt. After enabling Owl Guide, quit and reopen the app, then refresh readiness."
        refreshScreenUnderstandingReadiness()
    }

    func openScreenRecordingSettings() {
        if permissionManager.openScreenRecordingSettings() {
            screenUnderstandingReadinessFeedbackText = "System Settings should open to Screen Recording. After enabling Owl Guide, quit and reopen the app, then refresh readiness."
        } else if permissionManager.openSystemSettings() {
            screenUnderstandingReadinessFeedbackText = "System Settings opened. Go to Privacy & Security > Screen Recording, enable Owl Guide, then quit and reopen the app."
        } else {
            screenUnderstandingReadinessFeedbackText = "Open System Settings > Privacy & Security > Screen Recording, enable Owl Guide, then quit and reopen the app."
        }
    }

    func refreshScreenUnderstandingReadiness() {
        appRuntimeIdentityDebugInfo = Self.inspectRuntimeIdentity()
        let accessibilityReady = permissionState.isGranted
        let screenRecordingReady = permissionManager.isScreenRecordingGranted()
        let backendMode = activeBackendMode
        let keySource = geminiScreenUnderstandingService.currentKeySource()
        let modelConfiguration = geminiScreenUnderstandingService.currentModelConfiguration()
        hasSavedGeminiAPIKey = geminiScreenUnderstandingService.hasUserProvidedAPIKey()
        syncGeminiKeyDraftFromStoredState()
        let hasCapturedTarget = capturedExternalWindowElement != nil && capturedProcessIdentifier != nil && sanitizedTargetWindowFrame() != nil
        let hasLocalCandidates = !rawScannedElements.isEmpty
        let analysisSourceDetail: String
        switch backendMode {
        case .localSample:
            analysisSourceDetail = "Using the bundled local sample response. No network is required."
        case .localBackend:
            analysisSourceDetail = "Using the local backend at \(BackendEnvironment.localBackendBaseURL.absoluteString)."
        case .cloudBackend:
            analysisSourceDetail = "Using the cloud backend at \(BackendEnvironment.cloudBackendBaseURL.absoluteString)."
        }

        let readinessItems = [
            ScreenUnderstandingReadinessItem(
                id: "accessibility",
                title: "Accessibility access",
                isReady: accessibilityReady,
                detail: accessibilityReady
                    ? "Owl Guide can read interface elements from other apps."
                    : "Turn on Accessibility so Owl Guide can inspect the current app."
            ),
            ScreenUnderstandingReadinessItem(
                id: "screen-recording",
                title: "Screen Recording",
                isReady: screenRecordingReady,
                detail: screenRecordingReady
                    ? "Owl Guide can capture the target app window image."
                    : "Turn on Screen Recording so Owl Guide can capture the current app window. You may need to quit and reopen Owl Guide after enabling it."
            ),
            ScreenUnderstandingReadinessItem(
                id: "analysis-source",
                title: "Analysis source",
                isReady: true,
                detail: analysisSourceDetail
            ),
            ScreenUnderstandingReadinessItem(
                id: "captured-target",
                title: "Captured app window",
                isReady: hasCapturedTarget,
                detail: hasCapturedTarget
                    ? "A non-OwlGuide app window is captured and ready to inspect."
                    : "Open Owl Guide from another app, then refresh the external target."
            ),
            ScreenUnderstandingReadinessItem(
                id: "local-candidates",
                title: "Local screen scan",
                isReady: hasLocalCandidates,
                detail: hasLocalCandidates
                    ? "Local screen candidates are ready to send with the screenshot."
                    : "Run “Scan Captured Window Children” first so Owl Guide has local screen elements to ground the analysis."
            ),
            windowScreenshotService.canAttemptWindowScreenshot(
                processIdentifier: capturedProcessIdentifier,
                windowTitle: optionalValue(from: capturedExternalTargetDebugInfo.windowTitle),
                targetFrame: sanitizedTargetWindowFrame()
            )
        ]

        screenUnderstandingReadiness = ScreenUnderstandingReadiness(
            items: readinessItems,
            blockingReason: readinessItems.first(where: { !$0.isReady })?.detail
        )

        if screenUnderstandingReadiness.canAnalyze {
            screenUnderstandingReadinessFeedbackText = nil
        }

        screenUnderstandingDebugInfo = ScreenUnderstandingDebugInfo(
            keySource: keySource,
            modelName: modelConfiguration.name,
            modelSource: modelConfiguration.source,
            invocationMode: screenUnderstandingDebugInfo.invocationMode,
            userRequestPresent: screenUnderstandingDebugInfo.userRequestPresent,
            autoAnalysisFired: screenUnderstandingDebugInfo.autoAnalysisFired,
            idleTimeoutSeconds: screenUnderstandingDebugInfo.idleTimeoutSeconds,
            focusLockActive: owlFocusLockActive,
            draftTextPreserved: owlDraftTextPreserved,
            autoAnalysisUsedFreshCapture: screenUnderstandingDebugInfo.autoAnalysisUsedFreshCapture,
            timerRestartedDueToContextChange: owlTimerRestartedDueToContextChange,
            replyLanguageMode: owlReplyLanguageMode,
            preferredResponseLanguageCode: owlPreferredResponseLanguageCode,
            payloadMode: screenUnderstandingPayloadMode,
            analysisMode: screenUnderstandingDebugInfo.analysisMode,
            payloadRouting: screenUnderstandingDebugInfo.payloadRouting,
            complexityDiagnostics: screenUnderstandingDebugInfo.complexityDiagnostics,
            screenshotCaptured: screenUnderstandingDebugInfo.screenshotCaptured,
            originalScreenshotMimeType: screenUnderstandingDebugInfo.originalScreenshotMimeType,
            originalScreenshotWidth: screenUnderstandingDebugInfo.originalScreenshotWidth,
            originalScreenshotHeight: screenUnderstandingDebugInfo.originalScreenshotHeight,
            originalScreenshotByteCount: screenUnderstandingDebugInfo.originalScreenshotByteCount,
            originalScreenshotProcessingDescription: screenUnderstandingDebugInfo.originalScreenshotProcessingDescription,
            sendImageMimeType: screenUnderstandingDebugInfo.sendImageMimeType,
            sendImageWidth: screenUnderstandingDebugInfo.sendImageWidth,
            sendImageHeight: screenUnderstandingDebugInfo.sendImageHeight,
            sendImageByteCount: screenUnderstandingDebugInfo.sendImageByteCount,
            sendImageDidDownscale: screenUnderstandingDebugInfo.sendImageDidDownscale,
            sendImageUsedLossyCompression: screenUnderstandingDebugInfo.sendImageUsedLossyCompression,
            sendImageProcessingDescription: screenUnderstandingDebugInfo.sendImageProcessingDescription,
            actionableCandidatesAvailable: actionableCandidateCount,
            readableCandidatesAvailable: readableCandidateCount,
            actionableCandidatesSent: screenUnderstandingDebugInfo.actionableCandidatesSent,
            readableCandidatesSent: screenUnderstandingDebugInfo.readableCandidatesSent,
            contextCharacterCount: screenUnderstandingDebugInfo.contextCharacterCount,
            failureSource: screenUnderstandingDebugInfo.failureSource,
            responseMimeType: screenUnderstandingDebugInfo.responseMimeType,
            responseSchemaModeEnabled: screenUnderstandingDebugInfo.responseSchemaModeEnabled,
            requestDiagnosticsNote: screenUnderstandingDebugInfo.requestDiagnosticsNote,
            maxOutputTokens: screenUnderstandingDebugInfo.maxOutputTokens,
            finishReason: screenUnderstandingDebugInfo.finishReason,
            finishMessage: screenUnderstandingDebugInfo.finishMessage,
            promptTokenCount: screenUnderstandingDebugInfo.promptTokenCount,
            outputTokenCount: screenUnderstandingDebugInfo.outputTokenCount,
            totalTokenCount: screenUnderstandingDebugInfo.totalTokenCount,
            totalElapsedTimeMilliseconds: screenUnderstandingDebugInfo.totalElapsedTimeMilliseconds,
            screenshotPreparationTimeMilliseconds: screenUnderstandingDebugInfo.screenshotPreparationTimeMilliseconds,
            geminiRoundTripTimeMilliseconds: screenUnderstandingDebugInfo.geminiRoundTripTimeMilliseconds,
            httpStatusCode: screenUnderstandingDebugInfo.httpStatusCode,
            transportError: screenUnderstandingDebugInfo.transportError,
            rawResponseLength: screenUnderstandingDebugInfo.rawResponseLength,
            parserOutcome: screenUnderstandingDebugInfo.parserOutcome,
            requestSummary: screenUnderstandingDebugInfo.requestSummary,
            rawResponseText: screenUnderstandingDebugInfo.rawResponseText,
            recoveredJSONText: screenUnderstandingDebugInfo.recoveredJSONText
        )
    }

    func checkBackendHealth() {
        let mode = activeBackendMode
        backendHealthStatusText = "Checking \(mode.displayName)..."

        Task {
            do {
                let response = try await backendScreenUnderstandingService.health(mode: mode)
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }

                    self.backendHealthStatusText = response.value.ok
                        ? "Health check passed for \(mode.displayName)."
                        : "Health check returned ok=false for \(mode.displayName)."
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.backendHealthStatusText = "Health check failed for \(mode.displayName): \(error.localizedDescription)"
                }
            }
        }
    }

    private static func inspectRuntimeIdentity() -> AppRuntimeIdentityDebugInfo {
        let bundle = Bundle.main
        let bundleIdentifier = bundle.bundleIdentifier ?? "Unavailable"
        let bundlePath = bundle.bundleURL.path
        let executablePath = bundle.executableURL?.path ?? "Unavailable"
        let signingStatus = signingStatus(for: bundle.bundleURL)

        return AppRuntimeIdentityDebugInfo(
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath,
            executablePath: executablePath,
            signingState: signingStatus.state,
            signingDetail: signingStatus.detail
        )
    }

    private static func signingStatus(for bundleURL: URL) -> (state: String, detail: String) {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode)

        guard createStatus == errSecSuccess, let staticCode else {
            return (
                "Unavailable",
                "macOS could not inspect the current app signature (status \(createStatus))."
            )
        }

        let validityStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
        if validityStatus == errSecSuccess {
            return ("Signed", "This running app instance has a valid code signature.")
        }

        if validityStatus == errSecCSUnsigned {
            return ("Unsigned", "This running app instance is not code signed. macOS privacy permissions may not match older Owl Guide entries.")
        }

        return (
            "Invalid",
            "The current app signature could not be validated (status \(validityStatus))."
        )
    }

    func saveGeminiAPIKey() {
        guard isGeminiAPIKeyEditable else {
            screenUnderstandingReadinessFeedbackText = "A Gemini API key is already saved locally. Clear it before entering a different one."
            return
        }

        let trimmed = geminiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            screenUnderstandingReadinessFeedbackText = "Enter a Gemini API key before saving it."
            return
        }

        do {
            try geminiScreenUnderstandingService.saveUserProvidedAPIKey(trimmed)
            hasSavedGeminiAPIKey = true
            syncGeminiKeyDraftFromStoredState()
            screenUnderstandingReadinessFeedbackText = "Gemini API key saved locally in Owl Guide."
            refreshScreenUnderstandingReadiness()
        } catch {
            screenUnderstandingReadinessFeedbackText = error.localizedDescription
        }
    }

    func clearGeminiAPIKey() {
        do {
            try geminiScreenUnderstandingService.clearUserProvidedAPIKey()
            geminiAPIKeyDraft = ""
            hasSavedGeminiAPIKey = false
            screenUnderstandingReadinessFeedbackText = "Saved Gemini API key removed from Owl Guide."
            refreshScreenUnderstandingReadiness()
        } catch {
            screenUnderstandingReadinessFeedbackText = error.localizedDescription
        }
    }

    func copyRawGeminiResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(screenUnderstandingDebugInfo.rawResponseText, forType: .string)
        screenUnderstandingReadinessFeedbackText = "Raw Gemini response copied."
    }

    func copyGeminiRequestSummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(screenUnderstandingDebugInfo.requestSummary, forType: .string)
        screenUnderstandingReadinessFeedbackText = "Gemini request summary copied."
    }

    func scanCapturedExternalTargetWindow() {
        refreshPermissionStatus()
        selectedElementInspection = nil
        selectedRecommendedTargetID = nil
        invalidateGroundingSnapshot()
        let shouldRestoreOverlayPreview = overlayPreviewRequested
        let shouldRestoreWindowAnchor = windowAnchorRequested
        performCapturedTargetScan(
            resetAnalysisState: true,
            restoreOverlayPreview: shouldRestoreOverlayPreview,
            restoreWindowAnchor: shouldRestoreWindowAnchor,
            analysisResetMessage: "Scanning the captured target window. Run Gemini analysis again after this scan completes."
        )
    }

    private func performCapturedTargetScan(
        resetAnalysisState: Bool,
        restoreOverlayPreview: Bool,
        restoreWindowAnchor: Bool,
        analysisResetMessage: String? = nil
    ) {
        if resetAnalysisState, let analysisResetMessage {
            resetScreenUnderstandingState(message: analysisResetMessage)
        }

        suspendOverlayPreviewForRefresh()
        suspendWindowAnchorForRefresh()

        guard capturedExternalWindowElement != nil else {
            scanState = .failure(scanUnavailableMessage())
            rawScannedElements = []
            filteredUsefulElements = []
            topActionableElements = []
            topReadableElements = []
            actionableCandidateCount = 0
            readableCandidateCount = 0
            didHitScanNodeLimit = false
            scanChildLookupFailureCount = 0
            refreshScreenUnderstandingReadiness()
            return
        }

        let result = accessibilityScanner.scanWindow(capturedExternalWindowElement, configuration: scanConfiguration)
        let normalizedResults = axResultNormalizer.normalize(rawNodes: result.elements)
        let rankedResults = axCandidateRanker.rank(filteredElements: normalizedResults.usefulNodes)
        rawScannedElements = normalizedResults.rawNodes
        filteredUsefulElements = normalizedResults.usefulNodes
        topActionableElements = rankedResults.actionable.displayedElements
        topReadableElements = rankedResults.readable.displayedElements
        actionableCandidateCount = rankedResults.actionable.totalCandidateCount
        readableCandidateCount = rankedResults.readable.totalCandidateCount
        didHitScanNodeLimit = result.didHitNodeLimit
        scanChildLookupFailureCount = result.childLookupFailureCount

        let normalizationSummary = " Raw nodes: \(rawScannedElements.count). Filtered useful elements: \(filteredUsefulElements.count). Actionable candidates: \(actionableCandidateCount), showing \(topActionableElements.count). Readable candidates: \(readableCandidateCount), showing \(topReadableElements.count)."

        if result.isFailure {
            scanState = .failure(result.statusMessage + normalizationSummary)
        } else if rawScannedElements.isEmpty {
            scanState = .empty(result.statusMessage + normalizationSummary)
            autoShowWindowAnchorForCurrentScan()
        } else {
            scanState = .success(result.statusMessage + normalizationSummary)
            autoShowWindowAnchorForCurrentScan()
        }

        if restoreOverlayPreview {
            showOverlayPreview()
        }

        if restoreWindowAnchor {
            showWindowAnchor()
        }

        refreshScreenUnderstandingReadiness()
    }

    private func scanUnavailableMessage() -> String {
        if !permissionState.isGranted {
            return "Owl Guide cannot scan this window yet because Accessibility permission is off. Open System Settings > Privacy & Security > Accessibility, enable Owl Guide, then refresh the external target and scan again."
        }

        let lookupStatus = capturedExternalTargetDebugInfo.statusMessage
        if lookupStatus.contains("Accessibility API disabled") {
            return "Owl Guide could not resolve a scannable window because macOS Accessibility access is disabled for this app. Enable Accessibility permission, then refresh the external target and scan again."
        }

        if capturedExternalTargetDebugInfo.focusedWindowFound || capturedExternalTargetDebugInfo.mainWindowFallbackFound {
            return "Owl Guide expected a scannable external window, but the resolved window element is missing. Refresh the external target and try scanning again."
        }

        return "Owl Guide could not resolve a scannable external window from the current target. Refresh the external target and try scanning again."
    }

    private func resetScanState() {
        invalidateGroundingSnapshot()
        clearGroundedTargetState()
        rawScannedElements = []
        filteredUsefulElements = []
        topActionableElements = []
        topReadableElements = []
        actionableCandidateCount = 0
        readableCandidateCount = 0
        selectedElementInspection = nil
        selectedRecommendedTargetID = nil
        didHitScanNodeLimit = false
        scanChildLookupFailureCount = 0
        scanState = .idle("Captured target updated. Scan again to inspect AXChildren from its resolved window up to depth \(scanConfiguration.maxDepth).")
    }

    private func prepareForNewAnalysisRun() {
        cancelSlowResponseFallbackTask()
        prepareForFreshAnalysis?()
        clearRelayPresentation()
        currentScreenUnderstandingContext = nil
        invalidateGroundingSnapshot()
        selectedRecommendedTargetID = nil
        selectedElementInspection = nil
        clearGroundedTargetState()
        overlayPreviewRequested = false
        overlayPreviewItems = []
        overlayPreviewStatusText = "Overlay preview is off."
        windowAnchorRequested = false
        overlayAnchorFrame = nil
        windowAnchorStatusText = "Window anchor is off."
        topActionableElements = []
        topReadableElements = []
        actionableCandidateCount = 0
        readableCandidateCount = 0
        filteredUsefulElements = []
        rawScannedElements = []
        screenUnderstandingResult = nil
        screenScenarioGuidance = nil
        currentTaskThread = nil
        guidedStepResponse = nil
        lastScenarioContext = nil
        screenUnderstandingTargetSnapshot = nil
        refreshOverlayPresentationRequest()
    }

    // MARK: - Action Execution (Phase 2)

    private let actionExecutionService = ActionExecutionService()

    /// Execute the currently grounded action (click or type) at the target bounds center.
    /// - Parameter isAutopilot: When true, uses the user-configured delay from AppSettings.
    ///   When false (default, manual button tap), uses a fixed 1.0 s release delay.
    func executeCurrentGroundedAction(isAutopilot: Bool = false) {
        let activeTarget = screenUnderstandingResult.flatMap(preferredExecutableRecommendedTarget(from:))

        guard canPresentExecutableAction(for: activeTarget),
              let bounds = groundedTargetBounds else {
            print("[ActionExecution] ⚠️ No groundedTargetBounds to execute action on.")
            return
        }

        let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)

        let actionType = activeTarget?.intendedAction?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? "click"
        let actionValue = activeTarget?.actionValue

        let delayNs: UInt64 = isAutopilot
            ? UInt64(AppSettings.shared.actionDelaySeconds * 1_000_000_000)
            : 1_000_000_000 // Fixed 1.0 s for manual tap (time to release mouse)

        print("[ActionExecution] \(isAutopilot ? "🤖 Autopilot" : "👆 Manual") – type=\(actionType) value=\(actionValue ?? "nil") at=\(centerPoint) delay=\(delayNs / 1_000_000)ms")

        // Create the task but keep Overlay VISIBLE during the countdown 
        // to maintain window focus state for the underlying app.
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            do {
                // Autopilot or Manual sleep
                try await Task.sleep(nanoseconds: delayNs)
                
                // Hide overlay and arrow JUST BEFORE executing so our click 
                // doesn't land on the overlay and doesn't happen during a window hide transition.
                self.prepareForFreshAnalysis?()
                
                // Small additional settle time to ensure system registers the window is gone
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                
                switch actionType {
                case "type":
                    let textToType = actionValue ?? ""
                    guard !textToType.isEmpty else {
                        print("[ActionExecution] ⚠️ Action is 'type' but no actionValue provided. Falling back to click.")
                        try await self.actionExecutionService.click(at: centerPoint)
                        break
                    }
                    try await self.actionExecutionService.type(text: textToType, focusingAt: centerPoint)
                    print("[ActionExecution] ✅ Typed '\(textToType)' at \(centerPoint)")

                default: // "click" or "none" or anything else
                    try await self.actionExecutionService.click(at: centerPoint)
                    print("[ActionExecution] ✅ Clicked at \(centerPoint)")
                }
            } catch {
                print("[ActionExecution] ❌ Execution failed: \(error.localizedDescription)")
            }

            // Clear the grounded target state after execution
            self.clearGroundedTargetState()
            self.guidedStepResponse = nil
            self.clearRelayPresentation()
        }
    }

    private func clearGroundedTargetState() {
        stopTrackingActiveElement(clearBounds: false)
        groundedTargetBounds = nil
        isGroundedActionReady = false
    }

    private func applyGroundedTargetState(_ state: GroundedTargetState) {
        groundedTargetBounds = state.bounds
        isGroundedActionReady = state.isReady

        if Self.localAXTrackingEnabled, let trackingElement = state.trackingElement {
            activeAXElement = trackingElement
            startTrackingActiveElement()
        } else {
            stopTrackingActiveElement(clearBounds: false)
        }
    }

    func startTrackingActiveElement() {
        guard let activeAXElement else {
            stopTrackingActiveElement(clearBounds: false)
            return
        }

        activeElementTrackingTimer?.invalidate()

        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let activeAXElement = self.activeAXElement else {
                    return
                }

                self.trackActiveElementFrame(activeAXElement)
            }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        activeElementTrackingTimer = timer

        trackActiveElementFrame(activeAXElement)
    }

    private func stopTrackingActiveElement(clearBounds: Bool) {
        activeElementTrackingTimer?.invalidate()
        activeElementTrackingTimer = nil
        activeAXElement = nil

        if clearBounds {
            groundedTargetBounds = nil
            isGroundedActionReady = false
            refreshOverlayPresentationRequest()
        }
    }

    private func trackActiveElementFrame(_ element: AXUIElement) {
        guard let newBounds = currentFrame(for: element)?.standardized else {
            stopTrackingActiveElement(clearBounds: true)
            return
        }

        guard let previousBounds = groundedTargetBounds else {
            groundedTargetBounds = newBounds
            refreshOverlayPresentationRequest()
            return
        }

        guard frameHasMeaningfullyChanged(from: previousBounds, to: newBounds) else {
            return
        }

        groundedTargetBounds = newBounds
        refreshOverlayPresentationRequest()
    }

    private func frameHasMeaningfullyChanged(from oldFrame: CGRect, to newFrame: CGRect) -> Bool {
        let tolerance: CGFloat = 1.0
        return abs(oldFrame.origin.x - newFrame.origin.x) > tolerance
            || abs(oldFrame.origin.y - newFrame.origin.y) > tolerance
            || abs(oldFrame.size.width - newFrame.size.width) > tolerance
            || abs(oldFrame.size.height - newFrame.size.height) > tolerance
    }

    private func currentFrame(for element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute as CFString, from: element),
              let size = sizeAttribute(kAXSizeAttribute as CFString, from: element),
              size.width > 1,
              size.height > 1 else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(rawValue, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(rawValue, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    /// Called after groundedTargetBounds is resolved. If the user has Autopilot enabled
    /// for this action type, fires the action automatically without user button press.
    func triggerAutopilotIfEnabled() {
        guard let activeTarget = screenUnderstandingResult.flatMap(preferredExecutableRecommendedTarget(from:)),
              let intendedAction = activeTarget.intendedAction?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              intendedAction == "click" || intendedAction == "type" else {
            // 没有可执行的操作，直接返回，避免执行无效action导致崩溃
            return
        }

        let actionType = intendedAction
        let requiresConfirmation = activeTarget.requiresConfirmation == true

        let shouldFire: Bool
        switch actionType {
        case "type":
            shouldFire = AppSettings.shared.autoTypeEnabled
        default:
            shouldFire = AppSettings.shared.autoClickEnabled
        }

        guard shouldFire,
              canPresentExecutableAction(for: activeTarget),
              !requiresConfirmation else { return }
        print("[ActionExecution] 🤖 Autopilot auto-triggered for action '\(actionType)'")
        executeCurrentGroundedAction(isAutopilot: true)
    }

    private func resolvedGroundedTargetState(
        for recommendedTargets: [ScreenUnderstandingRecommendedTarget],
        targetWindowFrame: CGRect?
    ) -> GroundedTargetState {
//        print("[ArrowGuide] 🎯 Gemini returned \(recommendedTargets.count) recommended targets:")
//        for target in recommendedTargets {
//            print("[ArrowGuide]   - rank=\(target.rank) label=\"\(target.label)\" visualBBox=\(String(describing: target.visualBoundingBox)) relatedLocalElement=\"\(target.relatedLocalElement)\"")
//        }

        guard let firstTarget = recommendedTargets.first else {
//            print("[ArrowGuide] ⚠️ No recommended targets returned by Gemini")
            return GroundedTargetState(bounds: nil, isReady: false, trackingElement: nil)
        }

        // PRIORITY 1: Use Gemini's visual bounding box (normalized 0-1 → CG screen coordinates)
        if let visualScreenBounds = convertVisualBoundsToScreen(
            firstTarget.visualBounds,
            windowFrame: targetWindowFrame
        ) {
//            print("[ArrowGuide] ✅ VISUAL GROUNDING: \"\(firstTarget.label)\" → CG screen bounds = \(visualScreenBounds)")
            return GroundedTargetState(
                bounds: visualScreenBounds,
                isReady: true,
                trackingElement: nil
            )
        }

        // PRIORITY 2: Fall back to AX element matching
        if let resolvedTarget = recommendedTargets.lazy.compactMap({ target -> ResolvedRecommendedTarget? in
            if let resolved = self.resolveRecommendedTarget(for: target) {
//                print("[ArrowGuide]   ✅ AX fallback match: \"\(target.label)\" → \"\(resolved.element.displayName)\" bounds=\(String(describing: resolved.bounds))")
                return resolved
            }
            return nil
        }).first {
//            print("[ArrowGuide] 🏁 AX fallback grounded bounds: \(String(describing: resolvedTarget.bounds))")
            return GroundedTargetState(
                bounds: resolvedTarget.bounds,
                isReady: true,
                trackingElement: resolvedTarget.element.axElement
            )
        }

//        print("[ArrowGuide] ⚠️ Neither visual grounding nor AX matching succeeded for \"\(firstTarget.label)\"")
        return GroundedTargetState(bounds: nil, isReady: false, trackingElement: nil)
    }

    /// Convert Gemini's normalized bounding box to CG screen coordinates.
    ///
    /// `normalizedBounds` is a CGRect with values in 0.0–1.0 range, where:
    ///   - x = fraction from left edge of screenshot/window
    ///   - y = fraction from top edge of screenshot/window
    ///   - width/height = fraction of window dimensions
    ///
    /// The window frame is in CG global coordinates (origin at top-left of primary display).
    private func convertVisualBoundsToScreen(
        _ normalizedBounds: CGRect?,
        windowFrame: CGRect?
    ) -> CGRect? {
        guard let normRect = normalizedBounds else {
//            print("[ArrowGuide] 🔇 No visualBoundingBox from Gemini")
            return nil
        }
        guard normRect.width > 0, normRect.height > 0 else {
//            print("[ArrowGuide] 🔇 Invalid visualBoundingBox: \(normRect)")
            return nil
        }
        guard let windowFrame, windowFrame.width > 0, windowFrame.height > 0 else {
//            print("[ArrowGuide] 🔇 No target window frame for coordinate conversion")
            return nil
        }

        let screenRect = CGRect(
            x: windowFrame.origin.x + normRect.origin.x * windowFrame.width,
            y: windowFrame.origin.y + normRect.origin.y * windowFrame.height,
            width: normRect.width * windowFrame.width,
            height: normRect.height * windowFrame.height
        )

//        print("[ArrowGuide] 📐 Normalized→Screen: norm=\(normRect) window=\(windowFrame) → screen=\(screenRect)")
        return screenRect
    }

    func analyzeCurrentScreen(
        userRequest: String? = nil,
        invocationMode: OwlInvocationMode = .manualPanelAnalysis,
        autoAnalysisFired: Bool = false
    ) {
        guard !screenUnderstandingState.isLoading else {
            return
        }

        prepareForFreshAnalysis?()
        refreshScreenUnderstandingReadiness()
        owlInteractionState = .capturingContext
        screenUnderstandingProgressStage = .preparing
        screenUnderstandingState = .loading("Owl Guide is starting to look at the current page.")
        latestGuidePlan = nil
        analysisPresentationTargetWindowFrame = sanitizedTargetWindowFrame()
        relayPresentationDismissedByUser = false
        refreshRelayPresentation()
        if !screenUnderstandingReadiness.canAnalyze {
            attemptAutomaticContextPreparation(for: invocationMode)
            refreshScreenUnderstandingReadiness()
        }

        guard screenUnderstandingReadiness.canAnalyze else {
            screenUnderstandingResult = nil
            screenUnderstandingState = .idle(screenUnderstandingReadiness.blockingReason ?? "Owl Guide is still missing something before it can analyze this screen.")
            owlInteractionState = .fallbackShown
            owlFallbackMessage = "I'm still preparing this page. You can also tell me what you want to do."
            refreshRelayPresentation()
            return
        }

        Task {
            await performCurrentScreenAnalysis(
                userRequest: userRequest?.trimmingCharacters(in: .whitespacesAndNewlines),
                invocationMode: invocationMode,
                autoAnalysisFired: autoAnalysisFired
            )
        }
    }

    private func attemptAutomaticContextPreparation(for invocationMode: OwlInvocationMode) {
        guard invocationMode != .manualPanelAnalysis else {
            return
        }

        var missingItemIDs = Set(
            screenUnderstandingReadiness.items
                .filter { !$0.isReady }
                .map(\.id)
        )

        if missingItemIDs.contains("captured-target") {
            captureExternalTarget()
            refreshScreenUnderstandingReadiness()
            missingItemIDs = Set(
                screenUnderstandingReadiness.items
                    .filter { !$0.isReady }
                    .map(\.id)
            )
        }

        if missingItemIDs == ["local-candidates"] {
            screenUnderstandingProgressStage = .preparing
            screenUnderstandingState = .loading("Reading the current window first so Owl Guide can ground Gemini with local interface elements.")
            refreshRelayPresentation()
            performCapturedTargetScan(
                resetAnalysisState: false,
                restoreOverlayPreview: false,
                restoreWindowAnchor: false
            )
        }
    }

    func confirmScenarioIntent(_ intent: OwlGuideUserIntent) {
        guard let scenarioContext = lastScenarioContext,
              let screenUnderstandingResult else {
            return
        }

        let transition = scenarioSkillRouter.confirmTaskThread(
            intent: intent,
            from: scenarioContext,
            result: screenUnderstandingResult
        )
        applyTaskThreadTransition(transition)
    }

    func isIntentSelected(_ intent: OwlGuideUserIntent) -> Bool {
        currentTaskThread?.chosenIntent == intent
    }

    func isIntentConfirmed(_ intent: OwlGuideUserIntent) -> Bool {
        currentTaskThread?.chosenIntent == intent && currentTaskThread?.isConfirmed == true
    }

    func selectRawElement(_ element: AXElementNode) {
        clearRecommendedTargetSelection(refreshOverlay: true)
        selectedElementInspection = AXSelectedElementInspection(source: .raw, element: element, score: nil, reasonTags: [])
    }

    func selectFilteredElement(_ element: AXElementNode) {
        clearRecommendedTargetSelection(refreshOverlay: true)
        selectedElementInspection = AXSelectedElementInspection(source: .filtered, element: element, score: nil, reasonTags: [])
    }

    func selectActionableElement(_ rankedElement: AXRankedElement) {
        clearRecommendedTargetSelection(refreshOverlay: true)
        selectedElementInspection = AXSelectedElementInspection(
            source: .actionable,
            element: rankedElement.element,
            score: rankedElement.score,
            reasonTags: rankedElement.reasonTags
        )
    }

    func selectReadableElement(_ rankedElement: AXRankedElement) {
        clearRecommendedTargetSelection(refreshOverlay: true)
        selectedElementInspection = AXSelectedElementInspection(
            source: .readable,
            element: rankedElement.element,
            score: rankedElement.score,
            reasonTags: rankedElement.reasonTags
        )
    }

    func clearSelectedElementInspection() {
        clearRecommendedTargetSelection(refreshOverlay: true)
        selectedElementInspection = nil
    }

    func inspectRecommendedTarget(_ target: ScreenUnderstandingRecommendedTarget) {
        guard let linkedElementSelection = linkedElementInspection(for: target) else {
            return
        }

        selectedRecommendedTargetID = target.id
        selectedElementInspection = linkedElementSelection
        showOverlayPreview()
    }

    func localLinkStatus(for target: ScreenUnderstandingRecommendedTarget) -> ScreenUnderstandingLocalLinkStatus {
        if let resolvedTarget = resolveRecommendedTarget(for: target) {
            switch resolvedTarget.source {
            case .actionable:
                return .linkedActionable
            case .readable:
                return .linkedReadable
            case .raw, .filtered:
                return .visualOnly
            }
        }

        let identifier = target.relatedLocalElement.trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? .visualOnly : .unresolved(identifier)
    }

    func isRecommendedTargetSelected(_ target: ScreenUnderstandingRecommendedTarget) -> Bool {
        selectedRecommendedTargetID == target.id
    }

    func toggleOverlayPreview() {
        if overlayPreviewRequested {
            hideOverlayPreview()
        } else {
            showOverlayPreview()
        }
    }

    func toggleWindowAnchor() {
        if windowAnchorRequested {
            hideWindowAnchor()
        } else {
            showWindowAnchor()
        }
    }

    func selectOverlayPreviewItem(_ item: OverlayPreviewItem) {
        guard let rankedElement = topActionableElements.first(where: { $0.element.id == item.id }) else {
            guard let readableElement = topReadableElements.first(where: { $0.element.id == item.id }) else {
                return
            }

            selectReadableElement(readableElement)
            return
        }

        selectActionableElement(rankedElement)
    }

    func validateGuidedStepOverlaySafety() {
        guard overlayPreviewRequested,
              selectedRecommendedTargetID == nil,
              let effectiveGrounding = effectiveGuidedStepGrounding else {
            return
        }

        switch effectiveGrounding.status {
        case .axGroundedPreciseTarget, .regionLevelFallback:
            break
        case .textOnlyFallback:
            return
        }

        guard let snapshot = analysisGroundingSnapshot else {
            demoteGuidedStepGroundingToTextOnly(
                reason: "The current overlay was hidden because Owl Guide no longer has a grounded analysis snapshot for this step."
            )
            return
        }

        guard snapshot.contentRevision == targetContentRevision else {
            demoteGuidedStepGroundingToTextOnly(
                reason: "The page changed after the last analysis, so Owl Guide hid the old highlight until you analyze this screen again."
            )
            return
        }

        guard let liveWindowFrame = frontmostAppDetector.currentWindowFrame(for: capturedExternalWindowElement),
              !liveWindowFrameHasMateriallyShifted(from: snapshot.targetWindowFrame, to: liveWindowFrame) else {
            demoteGuidedStepGroundingToTextOnly(
                reason: "The current window layout shifted after analysis, so Owl Guide hid the old highlight until you analyze this screen again."
            )
            return
        }
    }

    func validateRelayPresentationRelevance() {
        guard relayReminderCard != nil
                || overlayPreviewRequested
                || windowAnchorRequested
                || isOverlayPreviewVisible
                || isWindowAnchorVisible else {
            return
        }

        let baselineSignature = currentAnalysisTargetSignature() ?? currentCapturedTargetSignature()
        guard let baselineSignature else {
            clearCurrentRelayPresentationForTargetChange(
                reason: "The current page context is no longer available, so Owl Guide hid the previous reminder."
            )
            return
        }

        guard let freshTarget = detectFreshExternalTarget(),
              let freshSignature = targetSignature(
                    from: freshTarget.debugInfo,
                    frame: freshTarget.windowFrame
              ) else {
            // Preserve the card on transient AX/window refresh failures. These are common on
            // complex pages and would otherwise make the action affordance disappear abruptly.
            hideOverlayPreview(statusText: "Owl Guide temporarily lost the live target window, so it hid the highlight until the next stable refresh.")
            hideWindowAnchor(statusText: "Owl Guide temporarily lost the live target window, so it hid the anchor until the next stable refresh.")
            return
        }

        guard targetHasMateriallyChanged(from: baselineSignature, to: freshSignature) else {
            return
        }

        clearCurrentRelayPresentationForTargetChange(
            reason: "The current page changed, so Owl Guide hid the previous reminder until you ask it to look again."
        )
    }

    private func showOverlayPreview() {
        let candidates = makeOverlayPreviewItems()
        guard !candidates.isEmpty else {
            overlayPreviewRequested = false
            isOverlayPreviewVisible = false
            overlayPreviewItems = []
            overlayPreviewStatusText = unavailableOverlayStatusText()
            refreshOverlayPresentationRequest()
            return
        }

        overlayPreviewRequested = true
        overlayPreviewItems = candidates
        isOverlayPreviewVisible = false
        overlayPreviewStatusText = preparingOverlayStatusText(for: candidates.count)
        refreshOverlayPresentationRequest()
    }

    private func hideOverlayPreview(statusText: String = "Overlay preview is off.") {
        overlayPreviewRequested = false
        isOverlayPreviewVisible = false
        overlayPreviewItems = []
        overlayPreviewStatusText = statusText
        refreshOverlayPresentationRequest()
    }

    private func showWindowAnchor() {
        showWindowAnchor(statusText: "Preparing the lightweight target window anchor.")
    }

    private func showWindowAnchor(statusText: String) {
        guard let targetWindowFrame = sanitizedTargetWindowFrame() else {
            windowAnchorRequested = false
            isWindowAnchorVisible = false
            overlayAnchorFrame = nil
            windowAnchorStatusText = "No valid captured target window bounds are available for the window anchor."
            refreshOverlayPresentationRequest()
            return
        }

        windowAnchorRequested = true
        overlayAnchorFrame = targetWindowFrame
        isWindowAnchorVisible = false
        windowAnchorStatusText = statusText
        refreshOverlayPresentationRequest()
    }

    private func hideWindowAnchor(statusText: String = "Window anchor is off.") {
        windowAnchorRequested = false
        isWindowAnchorVisible = false
        overlayAnchorFrame = nil
        windowAnchorStatusText = statusText
        refreshOverlayPresentationRequest()
    }

    private func suspendOverlayPreviewForRefresh() {
        isOverlayPreviewVisible = false
        overlayPreviewItems = []

        if overlayPreviewRequested {
            overlayPreviewStatusText = "Refreshing overlay preview for the updated scan results."
        } else {
            overlayPreviewStatusText = "Overlay preview is off."
        }

        refreshOverlayPresentationRequest()
    }

    private func suspendWindowAnchorForRefresh() {
        isWindowAnchorVisible = false

        if windowAnchorRequested {
            windowAnchorStatusText = "Refreshing the captured target window anchor."
        } else {
            windowAnchorStatusText = "Window anchor is off."
        }

        refreshOverlayPresentationRequest()
    }

    private func autoShowWindowAnchorForCurrentScan() {
        guard sanitizedTargetWindowFrame() != nil else {
            return
        }

        showWindowAnchor(
            statusText: "Current analysis window locked. Please keep this window in place while Owl Guide is reading it."
        )
    }

    func applyOverlayPresentationResult(overlayVisible: Bool, anchorVisible: Bool) {
        isOverlayPreviewVisible = overlayVisible
        isWindowAnchorVisible = anchorVisible

        if overlayVisible {
            overlayPreviewStatusText = visibleOverlayStatusText(for: overlayPreviewItems.count)
        } else if overlayPreviewRequested {
            overlayPreviewRequested = false
            overlayPreviewItems = []
            overlayPreviewStatusText = "Overlay preview could not be rendered on the captured external target window."
            refreshOverlayPresentationRequest()
        } else {
            overlayPreviewStatusText = "Overlay preview is off."
        }

        if anchorVisible {
            windowAnchorStatusText = "Showing a lightweight outline for the captured target window."
        } else if windowAnchorRequested {
            windowAnchorRequested = false
            overlayAnchorFrame = nil
            windowAnchorStatusText = "Window anchor could not be rendered for the captured external target window."
            refreshOverlayPresentationRequest()
        } else {
            windowAnchorStatusText = "Window anchor is off."
        }
    }

    private func refreshOverlayPresentationRequest() {
        let shouldShowImplicitAnchor = overlayPreviewRequested && groundedTargetBounds != nil
        overlayPresentationRequest = OverlayPresentationRequest(
            reminderCard: relayReminderCard,
            showsOverlay: overlayPreviewRequested,
            overlayItems: overlayPreviewItems,
            showsAnchor: windowAnchorRequested || shouldShowImplicitAnchor,
            anchorFrame: overlayAnchorFrame ?? groundedTargetBounds
        )
    }

    private func refreshRelayPresentation() {
        lastResolvedRelayReminderCard = makeRelayReminderCard()

        guard !relayPresentationDismissedByUser else {
            relayReminderCard = nil
            refreshOverlayPresentationRequest()
            return
        }

        relayReminderCard = lastResolvedRelayReminderCard
        refreshOverlayPresentationRequest()
    }

    private func clearRelayPresentation() {
        relayPresentationDismissedByUser = false
        lastResolvedRelayReminderCard = nil
        relayReminderCard = nil
        refreshOverlayPresentationRequest()
    }

    private func clearRecommendedTargetSelection(refreshOverlay: Bool) {
        guard selectedRecommendedTargetID != nil else {
            return
        }

        selectedRecommendedTargetID = nil

        if refreshOverlay, overlayPreviewRequested {
            showOverlayPreview()
        }
    }

    private func preparingOverlayStatusText(for candidateCount: Int) -> String {
        if selectedRecommendedTargetID != nil {
            return "Preparing overlay preview for the selected Gemini target."
        }

        if let effectiveGrounding = effectiveGuidedStepGrounding {
            switch effectiveGrounding.status {
            case .axGroundedPreciseTarget:
                return "Preparing a grounded guided-step highlight for the current next step."
            case .regionLevelFallback:
                return "Preparing a broader guided-step region highlight for the current next step."
            case .textOnlyFallback:
                break
            }
        }

        return "Preparing overlay preview for \(candidateCount) actionable element\(candidateCount == 1 ? "" : "s")."
    }

    private func visibleOverlayStatusText(for candidateCount: Int) -> String {
        if selectedRecommendedTargetID != nil {
            return "Showing the selected Gemini target in the overlay."
        }

        if let effectiveGrounding = effectiveGuidedStepGrounding {
            switch effectiveGrounding.status {
            case .axGroundedPreciseTarget:
                return "Showing the current guided step as an AX-grounded target in the overlay."
            case .regionLevelFallback:
                return "Showing the current guided step as a broader grounded region in the overlay."
            case .textOnlyFallback:
                break
            }
        }

        return "Showing overlay preview for \(candidateCount) actionable element\(candidateCount == 1 ? "" : "s")."
    }

    private func unavailableOverlayStatusText() -> String {
        if selectedRecommendedTargetID != nil {
            return "The selected Gemini target could not be shown in the overlay because Owl Guide does not have usable local bounds for it."
        }

        if let effectiveGrounding = effectiveGuidedStepGrounding {
            return effectiveGrounding.reason
        }

        return "No suitable actionable elements with meaningful bounds are available for overlay preview."
    }

    private func makeRelayReminderCard() -> RelayReminderCard? {
        let targetWindowFrame = overlayTargetWindowFrame()

        if let loadingCard = loadingRelayReminderCard(for: targetWindowFrame) {
            return loadingCard
        }

        if let answerCard = answeredUserQuestionRelayReminderCard(for: targetWindowFrame) {
            return answerCard
        }

        if let currentTaskThread,
           let guidedStep = guidedStepResponse,
           let effectiveGrounding = effectiveGuidedStepGrounding {
            let title = relayReminderTitle(for: currentTaskThread, guidedStep: guidedStep)
            let message = optimizedRelayPrimaryText(guidedStep.nextStep)
            let detailSource: String? = guidedStep.clarificationQuestion ?? guidedStep.safetyNote ?? effectiveGrounding.confidenceNote
            let detail = relaySupportingText(primary: message, supporting: detailSource)

            let proposedTarget = screenUnderstandingResult.flatMap(preferredExecutableRecommendedTarget(from:))
            let proposedActionType = proposedTarget?.intendedAction
            let proposedActionValue = proposedTarget?.actionValue

            let executeAction: (() -> Void)? = canPresentExecutableAction(for: proposedTarget)
                ? { [weak self] in self?.executeCurrentGroundedAction() }
                : nil

            return RelayReminderCard(
                statusLabel: relayReminderStatusLabel(for: effectiveGrounding.relayPresentationMode),
                title: title,
                message: message,
                detail: detail,
                targetWindowFrame: targetWindowFrame,
                progressCurrentStep: nil,
                progressTotalSteps: nil,
                emphasis: effectiveGrounding.relayPresentationMode == .clarificationCardOnly ? .caution : .normal,
                proposedActionType: proposedActionType,
                proposedActionValue: proposedActionValue,
                onExecuteAction: executeAction
            )
        }

        if let fallbackMessage = owlFallbackMessage {
            let message = optimizedRelayPrimaryText(fallbackMessage)
            return RelayReminderCard(
                statusLabel: presentationCopy.needsConfirmationLabel,
                title: owlUserFacingFailureTitle ?? presentationCopy.defaultUnderstandingTitle,
                message: message,
                detail: relaySupportingText(primary: message, supporting: owlUserFacingFailureDetail),
                targetWindowFrame: targetWindowFrame,
                progressCurrentStep: nil,
                progressTotalSteps: nil,
                emphasis: .caution,
                proposedActionType: nil,
                proposedActionValue: nil,
                onExecuteAction: nil
            )
        }

        return nil
    }

    private func answeredUserQuestionRelayReminderCard(for targetWindowFrame: CGRect?) -> RelayReminderCard? {
        guard let result = screenUnderstandingResult,
              let scenarioGuidance = screenScenarioGuidance,
              scenarioGuidance.context.userRequest?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return nil
        }

        let answer = optimizedRelayPrimaryText(result.pageSummary)
        guard !answer.isEmpty else {
            return nil
        }

        let titleCandidate = result.likelyUserGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailCandidate = result.recommendedTargets.first?.whyThisMatters.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDetail = scenarioGuidance.firstResponse.safeFirstStep.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeDetail: String? = if let detailCandidate, !detailCandidate.isEmpty {
            detailCandidate
        } else if !fallbackDetail.isEmpty {
            fallbackDetail
        } else {
            nil
        }

        let proposedTarget = preferredExecutableRecommendedTarget(from: result)
        let proposedActionType = proposedTarget?.intendedAction
        let proposedActionValue = proposedTarget?.actionValue

        let executeAction: (() -> Void)? = canPresentExecutableAction(for: proposedTarget)
            ? { [weak self] in self?.executeCurrentGroundedAction() }
            : nil

        return RelayReminderCard(
            statusLabel: presentationCopy.safeNextStepLabel,
            title: relayQuestionAnswerTitle(from: titleCandidate),
            message: answer,
            detail: relaySupportingText(primary: answer, supporting: safeDetail),
            targetWindowFrame: targetWindowFrame,
            progressCurrentStep: nil,
            progressTotalSteps: nil,
            emphasis: .normal,
            proposedActionType: proposedActionType,
            proposedActionValue: proposedActionValue,
            onExecuteAction: executeAction
        )
    }

    private func relayQuestionAnswerTitle(from titleCandidate: String) -> String {
        let trimmed = titleCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 6 {
            return presentableRelayText(trimmed, limit: 54)
        }

        return "What this means"
    }

    private func preferredExecutableRecommendedTarget(from result: ScreenUnderstandingResult) -> ScreenUnderstandingRecommendedTarget? {
        if let activeTargetID = selectedRecommendedTargetID,
           let activeTarget = result.recommendedTargets.first(where: { $0.id == activeTargetID }),
           activeTarget.intendedAction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return activeTarget
        }

        if let preferredTypeTarget = result.recommendedTargets.first(where: {
            $0.intendedAction?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "type"
        }) {
            return preferredTypeTarget
        }

        if let preferredClickTarget = result.recommendedTargets.first(where: {
            $0.intendedAction?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "click"
        }) {
            return preferredClickTarget
        }

        if let firstExecutableTarget = result.recommendedTargets.first(where: {
            $0.intendedAction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }) {
            return firstExecutableTarget
        }

        return result.recommendedTargets.first
    }

    private func canPresentExecutableAction(for target: ScreenUnderstandingRecommendedTarget?) -> Bool {
        guard groundedTargetBounds != nil,
              let target,
              target.intendedAction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }

        // When AX scanning produced no usable local candidates, execution is too unreliable on
        // complex or protected windows. Keep the explanatory card, but suppress the action button.
        let hasAnyLocalCandidates = !topActionableElements.isEmpty || !topReadableElements.isEmpty
        guard hasAnyLocalCandidates else {
            return false
        }

        return true
    }

    private func loadingRelayReminderCard(for targetWindowFrame: CGRect?) -> RelayReminderCard? {
        guard screenUnderstandingState.isLoading else {
            return nil
        }

        return RelayReminderCard(
            statusLabel: loadingRelayStatusLabel(),
            title: loadingRelayTitle(),
            message: loadingRelayMessage(),
            detail: loadingRelayDetail(),
            targetWindowFrame: targetWindowFrame,
            progressCurrentStep: loadingRelayProgressStep(),
            progressTotalSteps: 3,
            emphasis: .loading,
            proposedActionType: nil,
            proposedActionValue: nil,
            onExecuteAction: nil
        )
    }

    private func loadingRelayStatusLabel() -> String {
        switch screenUnderstandingProgressStage {
        case .preparing:
            return presentationCopy.loadingPreparingLabel
        case .capturingScreenshot:
            return presentationCopy.loadingCapturingLabel
        case .sendingRequest:
            return presentationCopy.loadingGeminiLabel
        case .readingResponse:
            return presentationCopy.loadingReadingLabel
        case .idle, .ready, .failed:
            return presentationCopy.loadingPreparingLabel
        }
    }

    private func loadingRelayTitle() -> String {
        if let request = trimmedOwlUserRequest {
            return presentableRelayText("Helping with: \(request)", limit: 36)
        }

        if let targetSnapshot = screenUnderstandingTargetSnapshot,
           targetSnapshot.displayWindowTitle != "Untitled window" {
            return presentableRelayText(targetSnapshot.displayWindowTitle, limit: 36)
        }

        return presentationCopy.defaultPageTitle
    }

    private func loadingRelayMessage() -> String {
        switch screenUnderstandingProgressStage {
        case .preparing:
            return presentationCopy.loadingPreparingMessage
        case .capturingScreenshot:
            return presentationCopy.loadingCapturingMessage
        case .sendingRequest:
            return presentationCopy.loadingSendingMessage
        case .readingResponse:
            return presentationCopy.loadingReadingMessage
        case .idle, .ready, .failed:
            return presentationCopy.loadingPreparingMessage
        }
    }

    private func loadingRelayDetail() -> String? {
        switch screenUnderstandingProgressStage {
        case .preparing:
            return presentationCopy.loadingPreparingDetail
        case .capturingScreenshot:
            return presentationCopy.loadingCapturingDetail
        case .sendingRequest:
            return presentationCopy.loadingSendingDetail
        case .readingResponse:
            return presentationCopy.loadingReadingDetail
        case .idle, .ready, .failed:
            return nil
        }
    }

    private func loadingRelayProgressStep() -> Int {
        switch screenUnderstandingProgressStage {
        case .preparing:
            return 1
        case .capturingScreenshot:
            return 2
        case .sendingRequest, .readingResponse:
            return 3
        case .idle, .ready, .failed:
            return 1
        }
    }

    private func relayReminderStatusLabel(for relayMode: OwlGuideRelayPresentationMode) -> String {
        switch relayMode {
        case .clarificationCardOnly:
            return presentationCopy.needsConfirmationLabel
        case .regionLevelGuidanceOverlay:
            return presentationCopy.safeNextStepLabel
        case .preciseTargetOverlay:
            return presentationCopy.safeNextStepLabel
        }
    }

    private func relayReminderTitle(for taskThread: OwlGuideTaskThread, guidedStep: OwlGuideGuidedStep) -> String {
        let candidates = [
            guidedStep.title,
            taskThread.chosenIntent.displayName,
            screenUnderstandingResult?.likelyUserGoal,
            presentationCopy.defaultUnderstandingTitle
        ]

        for candidate in candidates.compactMap({ $0 }) {
            let normalized = presentableRelayText(candidate, limit: 54)
            if normalized.count >= 8 {
                return normalized
            }
        }

        return presentationCopy.defaultUnderstandingTitle
    }

    private func cleanedRelayBodyText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func optimizedRelayPrimaryText(_ text: String) -> String {
        let cleaned = cleanedRelayBodyText(text)
        guard !cleaned.isEmpty else {
            return cleaned
        }

        let sentenceCandidates = cleaned
            .components(separatedBy: CharacterSet(charactersIn: ".!?。！？"))
            .map { cleanedRelayBodyText($0) }
            .filter { !$0.isEmpty }

        if sentenceCandidates.count > 1 {
            let filtered = sentenceCandidates.filter { !isGenericRelaySceneSettingSentence($0) }
            if let firstMeaningful = filtered.first, !firstMeaningful.isEmpty {
                return presentableRelayText(firstMeaningful, limit: 120)
            }
        }

        return presentableRelayText(cleaned, limit: 140)
    }

    private func isGenericRelaySceneSettingSentence(_ sentence: String) -> Bool {
        let normalized = normalizedSemanticText(sentence)
        let genericPrefixes = [
            "you are in",
            "you are looking at",
            "you appear to be",
            "the screen shows",
            "this page",
            "您当前正在",
            "你当前正在",
            "你正在",
            "当前页面",
            "当前屏幕",
        ]

        return genericPrefixes.contains { normalized.hasPrefix($0) }
    }

    private func relaySupportingText(primary: String, supporting: String?) -> String? {
        guard let supporting else {
            return nil
        }

        let cleanedPrimary = normalizedSemanticText(primary)
        let cleanedSupporting = cleanedRelayBodyText(supporting)
        guard !cleanedSupporting.isEmpty else {
            return nil
        }

        let normalizedSupporting = normalizedSemanticText(cleanedSupporting)
        guard normalizedSupporting != cleanedPrimary else {
            return nil
        }

        return cleanedSupporting
    }

    private func presentableRelayText(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else {
            return trimmed
        }

        let preferredBoundaryCharacters = CharacterSet(charactersIn: ".!?。！？;；:")
        if let boundaryIndex = bestRelayBoundaryIndex(
            in: trimmed,
            limit: limit,
            preferredCharacters: preferredBoundaryCharacters
        ) {
            return "\(trimmed[..<boundaryIndex])…"
        }

        if let boundaryIndex = bestRelayBoundaryIndex(
            in: trimmed,
            limit: limit,
            preferredCharacters: .whitespacesAndNewlines
        ) {
            return "\(trimmed[..<boundaryIndex])…"
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: max(limit - 1, 1))
        return "\(trimmed[..<endIndex])…"
    }

    private func bestRelayBoundaryIndex(
        in text: String,
        limit: Int,
        preferredCharacters: CharacterSet
    ) -> String.Index? {
        guard limit > 0 else {
            return nil
        }

        let maximumIndex = text.index(text.startIndex, offsetBy: min(limit, text.count))
        var candidateIndex: String.Index?
        var index = text.startIndex

        while index < maximumIndex {
            let scalar = text[index].unicodeScalars.first
            if let scalar, preferredCharacters.contains(scalar) {
                candidateIndex = index
            }
            index = text.index(after: index)
        }

        return candidateIndex
    }

    private func restoreRelayPresentation() {
        relayPresentationDismissedByUser = false
        relayReminderCard = lastResolvedRelayReminderCard ?? makeRelayReminderCard()

        if overlayPreviewRequested {
            showOverlayPreview()
        } else if let relayMode = effectiveGuidedStepGrounding?.relayPresentationMode {
            switch relayMode {
            case .clarificationCardOnly:
                refreshOverlayPresentationRequest()
            case .regionLevelGuidanceOverlay, .preciseTargetOverlay:
                showOverlayPreview()
            }
        } else {
            refreshOverlayPresentationRequest()
        }
    }

    private var hasReplayableRelayPresentation: Bool {
        lastResolvedRelayReminderCard != nil
            || relayReminderCard != nil
            || guidedStepResponse != nil
            || owlFallbackMessage != nil
    }

    private func presentOwlInvocationPrompt(
        clearDraft: Bool,
        preserveExistingTargetSignature: Bool
    ) {
        if clearDraft {
            owlUserRequestText = ""
        }

        owlInteractionState = .awaitingUserIntent
        owlInvocationMode = .none
        owlUserInteractedBeforeAutoAnalysis = false
        owlAutoAnalysisFired = false
        owlFocusLockActive = false
        owlDraftTextPreserved = false
        owlAutoAnalysisUsedFreshCapture = false
        owlTimerRestartedDueToContextChange = false
        owlReplyLanguageMode = .systemDefault
        owlPreferredResponseLanguageCode = nil
        owlFallbackMessage = nil
        owlInvocationTargetSignature = preserveExistingTargetSignature
            ? (owlInvocationTargetSignature ?? currentCapturedTargetSignature())
            : currentCapturedTargetSignature()
        isOwlInvocationPromptPresented = true
        owlPromptDismissalWasExplicit = false
        // 已禁用自动30秒无输入扫描功能
        // startOwlIdleCountdown()
    }

    private func currentAnalysisTargetSignature() -> OwlInvocationTargetSignature? {
        guard let targetSnapshot = screenUnderstandingTargetSnapshot else {
            return nil
        }

        return OwlInvocationTargetSignature(
            processIdentifier: targetSnapshot.processIdentifier,
            windowTitle: targetSnapshot.windowTitle,
            windowRole: targetSnapshot.windowRole,
            windowSubrole: targetSnapshot.windowSubrole,
            frame: analysisGroundingSnapshot?.targetWindowFrame ?? overlayTargetWindowFrame()
        )
    }

    private func syncGeminiKeyDraftFromStoredState() {
        if hasSavedGeminiAPIKey {
            geminiAPIKeyDraft = Self.maskedSavedKeyText
        } else if geminiAPIKeyDraft == Self.maskedSavedKeyText {
            geminiAPIKeyDraft = ""
        }
    }

    private func resetScreenUnderstandingState(message: String) {
        let modelConfiguration = geminiScreenUnderstandingService.currentModelConfiguration()
        cancelInvocationIdleTask()
        cancelSlowResponseFallbackTask()
        clearRelayPresentation()
        clearGroundedTargetState()
        screenUnderstandingResult = nil
        latestGuidePlan = nil
        screenUnderstandingState = .idle(message)
        screenUnderstandingProgressStage = .idle
        screenUnderstandingTargetSnapshot = nil
        screenScenarioGuidance = nil
        scenarioIntentOptions = []
        currentTaskThread = nil
        guidedStepResponse = nil
        lastScenarioContext = nil
        isOwlInvocationPromptPresented = false
        owlInteractionState = .idle
        owlInvocationMode = .none
        owlIdleCountdownStartTime = nil
        owlFocusLockActive = false
        owlDraftTextPreserved = false
        owlAutoAnalysisFired = false
        owlAutoAnalysisUsedFreshCapture = false
        owlTimerRestartedDueToContextChange = false
        owlReplyLanguageMode = .systemDefault
        owlPreferredResponseLanguageCode = nil
        owlFallbackMessage = nil
        analysisPresentationTargetWindowFrame = nil
        currentScreenUnderstandingContext = nil
        screenUnderstandingDebugInfo = ScreenUnderstandingDebugInfo(
            keySource: geminiScreenUnderstandingService.currentKeySource(),
            modelName: modelConfiguration.name,
            modelSource: modelConfiguration.source,
            invocationMode: owlInvocationMode,
            userRequestPresent: false,
            autoAnalysisFired: false,
            idleTimeoutSeconds: Self.owlPassiveAutoLookDelaySeconds,
            focusLockActive: false,
            draftTextPreserved: false,
            autoAnalysisUsedFreshCapture: false,
            timerRestartedDueToContextChange: false,
            replyLanguageMode: .systemDefault,
            preferredResponseLanguageCode: nil,
            payloadMode: screenUnderstandingPayloadMode,
            analysisMode: screenUnderstandingDebugInfo.analysisMode,
            payloadRouting: screenUnderstandingDebugInfo.payloadRouting,
            complexityDiagnostics: screenUnderstandingDebugInfo.complexityDiagnostics,
            browserCaptureAttempted: screenUnderstandingDebugInfo.browserCaptureAttempted,
            browserName: screenUnderstandingDebugInfo.browserName,
            browserFailureCategory: screenUnderstandingDebugInfo.browserFailureCategory,
            browserContextUsageDescription: screenUnderstandingDebugInfo.browserContextUsageDescription,
            browserCurrentURL: screenUnderstandingDebugInfo.browserCurrentURL,
            browserURLRetrievalStatus: screenUnderstandingDebugInfo.browserURLRetrievalStatus,
            browserPageTitle: screenUnderstandingDebugInfo.browserPageTitle,
            browserTitleRetrievalStatus: screenUnderstandingDebugInfo.browserTitleRetrievalStatus,
            browserVisibleTextSummaryAvailable: screenUnderstandingDebugInfo.browserVisibleTextSummaryAvailable,
            browserTextSummaryStatus: screenUnderstandingDebugInfo.browserTextSummaryStatus,
            browserPrimaryEntryPointCount: screenUnderstandingDebugInfo.browserPrimaryEntryPointCount,
            screenshotCaptured: false,
            originalScreenshotMimeType: "Unavailable",
            originalScreenshotWidth: nil,
            originalScreenshotHeight: nil,
            originalScreenshotByteCount: nil,
            originalScreenshotProcessingDescription: "No screenshot captured yet.",
            actionableCandidatesAvailable: actionableCandidateCount,
            readableCandidatesAvailable: readableCandidateCount,
            actionableCandidatesSent: currentPayloadActionableCount,
            readableCandidatesSent: currentPayloadReadableCount,
            contextCharacterCount: 0,
            failureSource: nil,
            responseMimeType: GeminiScreenUnderstandingService.responseMimeType,
            responseSchemaModeEnabled: GeminiScreenUnderstandingService.responseSchemaModeEnabled,
            requestDiagnosticsNote: GeminiScreenUnderstandingService.requestDiagnosticsNote,
            maxOutputTokens: GeminiScreenUnderstandingService.maxOutputTokens,
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

    private func performCurrentScreenAnalysis(
        userRequest: String?,
        invocationMode: OwlInvocationMode,
        autoAnalysisFired: Bool
    ) async {
        markFrozenVerificationSnapshotSuperseded()
        hideOverlayPreview()
        lastScenarioContext = nil
        let analysisStart = Date()
        let hasUserRequest = !(userRequest?.isEmpty ?? true)
        let replyLanguageCode = hasUserRequest ? detectedLanguageCode(for: userRequest) : nil
        let replyLanguageMode: OwlReplyLanguageMode = hasUserRequest ? .matchedUserInput : .systemDefault
        owlInvocationMode = invocationMode
        owlAutoAnalysisFired = autoAnalysisFired
        owlReplyLanguageMode = replyLanguageMode
        owlPreferredResponseLanguageCode = replyLanguageCode
        owlFallbackMessage = nil
        owlInteractionState = .capturingContext
        cancelSlowResponseFallbackTask()

        if autoAnalysisFired {
            switch refreshCapturedContextForAutoAnalysis() {
            case .restartCountdown:
                return
            case .proceed:
                owlAutoAnalysisUsedFreshCapture = true
                analysisPresentationTargetWindowFrame = sanitizedTargetWindowFrame()
            }
        }

        guard !rawScannedElements.isEmpty else {
            screenUnderstandingResult = nil
            screenUnderstandingProgressStage = .failed
            screenUnderstandingState = .failure("Run “Scan Captured Window Children” first so Gemini receives grounded local candidate data.")
            owlInteractionState = .fallbackShown
            owlFallbackMessage = "I'm still preparing the page context. You can also tell me what you want to do."
            refreshRelayPresentation()
            freezeVerificationSnapshot()
            return
        }

        let targetSnapshot = makeScreenUnderstandingTargetSnapshot()
        screenUnderstandingTargetSnapshot = targetSnapshot

        guard let processIdentifier = capturedProcessIdentifier else {
            screenUnderstandingResult = nil
            screenUnderstandingProgressStage = .failed
            screenUnderstandingState = .failure("Owl Guide could not analyze \(targetSnapshot.appName) — \(targetSnapshot.displayWindowTitle) because the captured target does not have a usable process id for screenshot capture.")
            owlInteractionState = .fallbackShown
            owlFallbackMessage = "I can't read this window reliably yet, so I do not want to guess. You can also tell me what you want to do."
            refreshRelayPresentation()
            freezeVerificationSnapshot()
            return
        }

        guard let targetWindowFrame = sanitizedTargetWindowFrame() else {
            screenUnderstandingResult = nil
            screenUnderstandingProgressStage = .failed
            screenUnderstandingState = .failure("Owl Guide could not analyze \(targetSnapshot.appName) — \(targetSnapshot.displayWindowTitle) because the captured target does not have valid window bounds for screenshot capture.")
            owlInteractionState = .fallbackShown
            owlFallbackMessage = "I can't read this window reliably yet, so I do not want to guess. You can also tell me what you want to do."
            refreshRelayPresentation()
            freezeVerificationSnapshot()
            return
        }

        let payloadRouting = determinePayloadRouting()
        let browserCapture = browserContextCaptureService.captureContext(
            forAppNamed: targetSnapshot.appName,
            bundleIdentifier: targetSnapshot.bundleIdentifier
        )
        let scenarioContext = detectScenarioContext(
            targetSnapshot: targetSnapshot,
            browserCapture: browserCapture,
            userRequest: userRequest
        )
        screenUnderstandingPayloadMode = payloadRouting.mode
        screenUnderstandingResult = nil
        screenScenarioGuidance = nil
        scenarioIntentOptions = []
        guidedStepResponse = nil
        lastScenarioContext = scenarioContext
        let modelConfiguration = geminiScreenUnderstandingService.currentModelConfiguration()
        selectedRecommendedTargetID = nil
        screenUnderstandingProgressStage = .preparing
        screenUnderstandingDebugInfo = ScreenUnderstandingDebugInfo(
            keySource: geminiScreenUnderstandingService.currentKeySource(),
            modelName: modelConfiguration.name,
            modelSource: modelConfiguration.source,
            invocationMode: invocationMode,
            userRequestPresent: hasUserRequest,
            autoAnalysisFired: autoAnalysisFired,
            idleTimeoutSeconds: Self.owlPassiveAutoLookDelaySeconds,
            focusLockActive: owlFocusLockActive,
            draftTextPreserved: owlDraftTextPreserved,
            autoAnalysisUsedFreshCapture: owlAutoAnalysisUsedFreshCapture,
            timerRestartedDueToContextChange: owlTimerRestartedDueToContextChange,
            replyLanguageMode: replyLanguageMode,
            preferredResponseLanguageCode: replyLanguageCode,
            payloadMode: payloadRouting.mode,
            analysisMode: .normal,
            payloadRouting: payloadRouting.diagnostics,
            browserCaptureAttempted: browserCapture.attempted,
            browserName: browserCapture.browserName,
            browserFailureCategory: browserCapture.failureCategory?.rawValue,
            browserContextUsageDescription: browserCapture.contextUsageDescription,
            browserCurrentURL: browserCapture.context?.currentURL,
            browserURLRetrievalStatus: browserCapture.urlRetrievalStatus,
            browserPageTitle: browserCapture.context?.pageTitle,
            browserTitleRetrievalStatus: browserCapture.titleRetrievalStatus,
            browserVisibleTextSummaryAvailable: browserCapture.context?.visibleTextSummary != nil,
            browserTextSummaryStatus: browserCapture.textSummaryStatus,
            browserPrimaryEntryPointCount: browserCapture.context?.primaryEntryPoints.count ?? 0,
            screenshotCaptured: false,
            originalScreenshotMimeType: "Unavailable",
            originalScreenshotWidth: nil,
            originalScreenshotHeight: nil,
            originalScreenshotByteCount: nil,
            originalScreenshotProcessingDescription: "No screenshot captured yet.",
            actionableCandidatesAvailable: actionableCandidateCount,
            readableCandidatesAvailable: readableCandidateCount,
            actionableCandidatesSent: payloadActionableCount(for: payloadRouting.mode),
            readableCandidatesSent: payloadReadableCount(for: payloadRouting.mode),
            contextCharacterCount: 0,
            failureSource: nil,
            responseMimeType: GeminiScreenUnderstandingService.responseMimeType,
            responseSchemaModeEnabled: GeminiScreenUnderstandingService.responseSchemaModeEnabled,
            requestDiagnosticsNote: GeminiScreenUnderstandingService.requestDiagnosticsNote,
            maxOutputTokens: GeminiScreenUnderstandingService.maxOutputTokens,
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
            requestSummary: "Preparing Gemini request.",
            rawResponseText: "No Gemini response yet.",
            recoveredJSONText: "No recovered JSON yet."
        )
        screenUnderstandingState = .loading("Preparing screen analysis for \(targetSnapshot.appName) — \(targetSnapshot.displayWindowTitle).")
        refreshRelayPresentation()

        do {
            let backendMode = activeBackendMode
            screenUnderstandingProgressStage = .capturingScreenshot
            owlInteractionState = .capturingContext
            screenUnderstandingState = .loading("Capturing the \(targetSnapshot.displayWindowTitle) window from \(targetSnapshot.appName).")
            refreshRelayPresentation()
            let screenshotPreparationStart = Date()
            let screenshot = try await windowScreenshotService.captureWindowScreenshot(
                processIdentifier: processIdentifier,
                windowTitle: optionalValue(from: capturedExternalTargetDebugInfo.windowTitle),
                targetFrame: targetWindowFrame
            )
            let sendImage = try windowScreenshotService.prepareGeminiSendImage(from: screenshot)
            let screenshotPreparationElapsed = elapsedMilliseconds(since: screenshotPreparationStart)
            let analysisDecision = determineAnalysisMode(
                payloadRouting: payloadRouting.diagnostics,
                scenarioContext: scenarioContext,
                sendImage: sendImage,
                userRequestPresent: hasUserRequest
            )
            let context = makeScreenUnderstandingContext(
                payloadMode: payloadRouting.mode,
                analysisMode: analysisDecision.mode,
                scenarioContext: scenarioContext,
                browserCapture: browserCapture,
                userRequest: userRequest,
                preferredResponseLanguageCode: replyLanguageCode
            )
            currentScreenUnderstandingContext = context
            screenUnderstandingProgressStage = .sendingRequest
            owlInteractionState = .analyzing
            screenUnderstandingState = .loading("Sending one grounded backend request for \(targetSnapshot.appName) — \(targetSnapshot.displayWindowTitle).")
            refreshRelayPresentation()
            screenUnderstandingDebugInfo = ScreenUnderstandingDebugInfo(
                keySource: geminiScreenUnderstandingService.currentKeySource(),
                modelName: backendMode.displayName,
                modelSource: .builtInDefault,
                invocationMode: invocationMode,
                userRequestPresent: hasUserRequest,
                autoAnalysisFired: autoAnalysisFired,
                idleTimeoutSeconds: Self.owlPassiveAutoLookDelaySeconds,
                focusLockActive: owlFocusLockActive,
                draftTextPreserved: owlDraftTextPreserved,
                autoAnalysisUsedFreshCapture: owlAutoAnalysisUsedFreshCapture,
                timerRestartedDueToContextChange: owlTimerRestartedDueToContextChange,
                replyLanguageMode: replyLanguageMode,
                preferredResponseLanguageCode: replyLanguageCode,
                payloadMode: payloadRouting.mode,
                analysisMode: analysisDecision.mode,
                payloadRouting: payloadRouting.diagnostics,
                complexityDiagnostics: analysisDecision.diagnostics,
                browserCaptureAttempted: browserCapture.attempted,
                browserName: browserCapture.browserName,
                browserFailureCategory: browserCapture.failureCategory?.rawValue,
                browserContextUsageDescription: browserCapture.contextUsageDescription,
                browserCurrentURL: browserCapture.context?.currentURL,
                browserURLRetrievalStatus: browserCapture.urlRetrievalStatus,
                browserPageTitle: browserCapture.context?.pageTitle,
                browserTitleRetrievalStatus: browserCapture.titleRetrievalStatus,
                browserVisibleTextSummaryAvailable: browserCapture.context?.visibleTextSummary != nil,
                browserTextSummaryStatus: browserCapture.textSummaryStatus,
                browserPrimaryEntryPointCount: browserCapture.context?.primaryEntryPoints.count ?? 0,
                screenshotCaptured: true,
                originalScreenshotMimeType: screenshot.mimeType,
                originalScreenshotWidth: screenshot.pixelWidth,
                originalScreenshotHeight: screenshot.pixelHeight,
                originalScreenshotByteCount: screenshot.byteCount,
                originalScreenshotProcessingDescription: screenshot.processingDescription,
                sendImageMimeType: sendImage.mimeType,
                sendImageWidth: sendImage.pixelWidth,
                sendImageHeight: sendImage.pixelHeight,
                sendImageByteCount: sendImage.byteCount,
                sendImageDidDownscale: sendImage.didDownscale,
                sendImageUsedLossyCompression: sendImage.usedLossyCompression,
                sendImageProcessingDescription: sendImage.processingDescription,
                actionableCandidatesAvailable: context.actionableCandidatesAvailable,
                readableCandidatesAvailable: context.readableCandidatesAvailable,
                actionableCandidatesSent: context.topActionableElements.count,
                readableCandidatesSent: context.topReadableElements.count,
                contextCharacterCount: contextCharacterCount(for: context),
                failureSource: nil,
                responseMimeType: GeminiScreenUnderstandingService.responseMimeType,
                responseSchemaModeEnabled: GeminiScreenUnderstandingService.responseSchemaModeEnabled,
                requestDiagnosticsNote: "Routing through Owl Guide backend mode: \(backendMode.rawValue).",
                maxOutputTokens: GeminiScreenUnderstandingService.maxOutputTokens,
                finishReason: nil,
                finishMessage: nil,
                promptTokenCount: nil,
                outputTokenCount: nil,
                totalTokenCount: nil,
                totalElapsedTimeMilliseconds: elapsedMilliseconds(since: analysisStart),
                screenshotPreparationTimeMilliseconds: screenshotPreparationElapsed,
                geminiRoundTripTimeMilliseconds: nil,
                httpStatusCode: nil,
                transportError: nil,
                rawResponseLength: 0,
                parserOutcome: .none,
                requestSummary: "Backend mode: \(backendMode.rawValue)\n\n" + pendingRequestSummary(
                    for: context,
                    modelConfiguration: modelConfiguration,
                    payloadRouting: payloadRouting.diagnostics,
                    payloadMode: payloadRouting.mode,
                    analysisMode: analysisDecision.mode,
                    complexityDiagnostics: analysisDecision.diagnostics,
                    browserCapture: browserCapture,
                    originalScreenshot: screenshot,
                    sendImage: sendImage
                ),
                rawResponseText: "Waiting for Gemini response.",
                recoveredJSONText: "Waiting for recovered JSON."
            )
            slowResponseFallbackTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, self.screenUnderstandingState.isLoading else {
                    return
                }

                self.owlInteractionState = .fallbackShown
                self.owlFallbackMessage = "I'm still understanding this page. You can also tell me what you want to do, for example: help me sign in, I forgot my password, or what does this page mean?"
                self.refreshRelayPresentation()
            }
            let backendRoundTripStart = Date()
            let response = try await backendScreenUnderstandingService.analyzeScreen(
                screenshot: screenshot,
                context: context,
                sessionID: backendSessionID,
                mode: backendMode
            )
            let backendRoundTripElapsed = elapsedMilliseconds(since: backendRoundTripStart)
            let totalElapsed = elapsedMilliseconds(since: analysisStart)
            let groundedTargetState = resolvedGroundedTargetState(
                for: response.result.recommendedTargets,
                targetWindowFrame: targetWindowFrame
            )
            let refinedScenarioContext = scenarioSkillRouter.refineContext(base: scenarioContext, result: response.result)
            let nextScenarioGuidance = scenarioSkillRouter.buildFirstResponse(
                from: refinedScenarioContext,
                result: response.result
            )
            let nextIntentOptions = scenarioSkillRouter.intentOptions(for: refinedScenarioContext)
            let nextGroundingSnapshot = makeGroundingSnapshot(contentRevision: targetContentRevision)
            let nextTaskThreadTransition: ScenarioSkillRouter.TaskThreadTransition
            if let currentTaskThread {
                nextTaskThreadTransition = scenarioSkillRouter.continueTaskThread(
                    existing: currentTaskThread,
                    newContext: refinedScenarioContext,
                    result: response.result
                )
            } else {
                nextTaskThreadTransition = scenarioSkillRouter.startTaskThread(
                    from: refinedScenarioContext,
                    result: response.result
                )
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.cancelSlowResponseFallbackTask()
                self.selectedRecommendedTargetID = nil
                self.screenUnderstandingResult = response.result
                self.latestGuidePlan = response.guidePlan
                self.applyGroundedTargetState(groundedTargetState)
                self.triggerAutopilotIfEnabled()
                self.screenScenarioGuidance = nextScenarioGuidance
                self.scenarioIntentOptions = nextIntentOptions
                self.lastScenarioContext = refinedScenarioContext
                self.analysisGroundingSnapshot = nextGroundingSnapshot
                self.applyTaskThreadTransition(nextTaskThreadTransition)
                self.screenUnderstandingProgressStage = .readingResponse
                self.screenUnderstandingDebugInfo = ScreenUnderstandingDebugInfo(
                    keySource: geminiScreenUnderstandingService.currentKeySource(),
                    modelName: response.sourceMode.displayName,
                    modelSource: .builtInDefault,
                    invocationMode: invocationMode,
                    userRequestPresent: hasUserRequest,
                    autoAnalysisFired: autoAnalysisFired,
                    idleTimeoutSeconds: Self.owlPassiveAutoLookDelaySeconds,
                    focusLockActive: owlFocusLockActive,
                    draftTextPreserved: owlDraftTextPreserved,
                    autoAnalysisUsedFreshCapture: owlAutoAnalysisUsedFreshCapture,
                    timerRestartedDueToContextChange: owlTimerRestartedDueToContextChange,
                    replyLanguageMode: replyLanguageMode,
                    preferredResponseLanguageCode: replyLanguageCode,
                    payloadMode: payloadRouting.mode,
                    analysisMode: analysisDecision.mode,
                    payloadRouting: payloadRouting.diagnostics,
                    complexityDiagnostics: analysisDecision.diagnostics,
                    browserCaptureAttempted: browserCapture.attempted,
                    browserName: browserCapture.browserName,
                    browserFailureCategory: browserCapture.failureCategory?.rawValue,
                    browserContextUsageDescription: browserCapture.contextUsageDescription,
                    browserCurrentURL: browserCapture.context?.currentURL,
                    browserURLRetrievalStatus: browserCapture.urlRetrievalStatus,
                    browserPageTitle: browserCapture.context?.pageTitle,
                    browserTitleRetrievalStatus: browserCapture.titleRetrievalStatus,
                    browserVisibleTextSummaryAvailable: browserCapture.context?.visibleTextSummary != nil,
                    browserTextSummaryStatus: browserCapture.textSummaryStatus,
                    browserPrimaryEntryPointCount: browserCapture.context?.primaryEntryPoints.count ?? 0,
                    screenshotCaptured: true,
                    originalScreenshotMimeType: screenshot.mimeType,
                    originalScreenshotWidth: screenshot.pixelWidth,
                    originalScreenshotHeight: screenshot.pixelHeight,
                    originalScreenshotByteCount: screenshot.byteCount,
                    originalScreenshotProcessingDescription: screenshot.processingDescription,
                    sendImageMimeType: sendImage.mimeType,
                    sendImageWidth: sendImage.pixelWidth,
                    sendImageHeight: sendImage.pixelHeight,
                    sendImageByteCount: sendImage.byteCount,
                    sendImageDidDownscale: sendImage.didDownscale,
                    sendImageUsedLossyCompression: sendImage.usedLossyCompression,
                    sendImageProcessingDescription: sendImage.processingDescription,
                    actionableCandidatesAvailable: context.actionableCandidatesAvailable,
                    readableCandidatesAvailable: context.readableCandidatesAvailable,
                    actionableCandidatesSent: context.topActionableElements.count,
                    readableCandidatesSent: context.topReadableElements.count,
                    contextCharacterCount: contextCharacterCount(for: context),
                    failureSource: nil,
                    responseMimeType: "application/json",
                    responseSchemaModeEnabled: true,
                    requestDiagnosticsNote: "Backend response accepted in mode \(response.sourceMode.rawValue).",
                    maxOutputTokens: GeminiScreenUnderstandingService.maxOutputTokens,
                    finishReason: nil,
                    finishMessage: nil,
                    promptTokenCount: nil,
                    outputTokenCount: nil,
                    totalTokenCount: nil,
                    totalElapsedTimeMilliseconds: totalElapsed,
                    screenshotPreparationTimeMilliseconds: screenshotPreparationElapsed,
                    geminiRoundTripTimeMilliseconds: backendRoundTripElapsed,
                    httpStatusCode: response.statusCode,
                    transportError: nil,
                    rawResponseLength: response.rawResponseText.count,
                    parserOutcome: .fullJSON,
                    requestSummary: "Backend mode \(response.sourceMode.rawValue) returned a normalized action_plan response.",
                    rawResponseText: response.rawResponseText,
                    recoveredJSONText: response.rawResponseText
                )
                self.screenUnderstandingProgressStage = .ready
                self.screenUnderstandingState = .success("Backend analyzed \(targetSnapshot.appName) — \(targetSnapshot.displayWindowTitle) using the current target screenshot plus \(context.topActionableElements.count) actionable and \(context.topReadableElements.count) readable local candidates.")
                self.owlInteractionState = self.shouldTreatAnalysisAsAnswered(
                    scenarioGuidance: self.screenScenarioGuidance,
                    result: response.result,
                    userRequest: userRequest
                ) ? .answered : .needsClarification
                self.owlFallbackMessage = nil
                self.refreshRelayPresentation()
                self.freezeVerificationSnapshot()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.cancelSlowResponseFallbackTask()
                self.clearGroundedTargetState()
                self.screenUnderstandingResult = nil
                self.latestGuidePlan = nil
                self.screenScenarioGuidance = nil
                self.scenarioIntentOptions = []
                self.guidedStepResponse = nil
                self.screenUnderstandingProgressStage = .failed
                self.screenUnderstandingDebugInfo = self.debugInfo(
                    for: error,
                    totalElapsedTimeMilliseconds: self.elapsedMilliseconds(since: analysisStart)
                )
                self.screenUnderstandingState = .failure("Owl Guide could not finish analyzing \(targetSnapshot.appName) — \(targetSnapshot.displayWindowTitle). \(error.localizedDescription)")
                self.owlInteractionState = .fallbackShown
                self.owlFallbackMessage = "I'm still understanding this page. You can also tell me what you want to do, for example: sign in, find the right starting point, or tell me what this page means."
                self.refreshRelayPresentation()
                self.freezeVerificationSnapshot()
            }
        }
    }

    private func elapsedMilliseconds(since startDate: Date) -> Int {
        max(Int(Date().timeIntervalSince(startDate) * 1000), 0)
    }

    private func markFrozenVerificationSnapshotSuperseded() {
        guard let frozenVerificationSnapshot else {
            return
        }

        self.frozenVerificationSnapshot = VerificationSnapshotRecord(
            evidenceState: .superseded,
            browserAttemptState: frozenVerificationSnapshot.browserAttemptState,
            browserResultState: frozenVerificationSnapshot.browserResultState,
            effectiveContextState: frozenVerificationSnapshot.effectiveContextState,
            browserErrorCode: frozenVerificationSnapshot.browserErrorCode,
            fields: frozenVerificationSnapshot.fields
        )
    }

    private func freezeVerificationSnapshot() {
        frozenVerificationSnapshot = buildVerificationSnapshotRecord(evidenceState: .frozen)
    }

    private func applyTaskThreadTransition(_ transition: ScenarioSkillRouter.TaskThreadTransition) {
        currentTaskThread = transition.thread
        guidedStepResponse = groundedGuidedStep(from: transition.guidedStep)
        refreshRelayPresentation()

        switch effectiveGuidedStepGrounding?.relayPresentationMode {
        case .preciseTargetOverlay, .regionLevelGuidanceOverlay:
            showOverlayPreview()
        case .clarificationCardOnly, .none:
            hideOverlayPreview()
        }
    }

    private func groundedGuidedStep(from guidedStep: OwlGuideGuidedStep) -> OwlGuideGuidedStep {
        let resolvedIdentifiers = groundedRecommendedTargetIdentifiers(for: guidedStep.grounding)
        let preparedGuidedStep = OwlGuideGuidedStep(
            title: guidedStep.title,
            nextStep: guidedStep.nextStep,
            safetyNote: guidedStep.safetyNote,
            clarificationQuestion: guidedStep.clarificationQuestion,
            grounding: OwlGuideGuidedStepGrounding(
                primaryTargetLocalElementID: resolvedIdentifiers.primary ?? guidedStep.grounding.primaryTargetLocalElementID,
                fallbackTargetLocalElementID: resolvedIdentifiers.fallback ?? guidedStep.grounding.fallbackTargetLocalElementID,
                status: guidedStep.grounding.status,
                origin: guidedStep.grounding.origin,
                targetType: guidedStep.grounding.targetType,
                reason: guidedStep.grounding.reason,
                confidenceNote: guidedStep.grounding.confidenceNote,
                downgradeReason: guidedStep.grounding.downgradeReason
            )
        )

        return OwlGuideGuidedStep(
            title: preparedGuidedStep.title,
            nextStep: preparedGuidedStep.nextStep,
            safetyNote: preparedGuidedStep.safetyNote,
            clarificationQuestion: preparedGuidedStep.clarificationQuestion,
            grounding: resolveGuidedStepGrounding(from: preparedGuidedStep)
        )
    }

    private func demoteGuidedStepGroundingToTextOnly(reason: String) {
        guard let guidedStep = guidedStepResponse else {
            return
        }

        guidedStepResponse = OwlGuideGuidedStep(
            title: guidedStep.title,
            nextStep: guidedStep.nextStep,
            safetyNote: guidedStep.safetyNote,
            clarificationQuestion: guidedStep.clarificationQuestion,
            grounding: OwlGuideGuidedStepGrounding(
                primaryTargetLocalElementID: guidedStep.grounding.primaryTargetLocalElementID,
                fallbackTargetLocalElementID: guidedStep.grounding.fallbackTargetLocalElementID,
                status: .textOnlyFallback,
                origin: .unknown,
                targetType: nil,
                reason: reason,
                confidenceNote: "Owl Guide is no longer confident that a precise on-screen highlight would still be trustworthy.",
                downgradeReason: reason
            )
        )

        refreshRelayPresentation()

        hideOverlayPreview(statusText: reason)
    }

    private func resolveGuidedStepGrounding(from guidedStep: OwlGuideGuidedStep) -> OwlGuideGuidedStepGrounding {
        guard let snapshot = analysisGroundingSnapshot else {
            return OwlGuideGuidedStepGrounding(
                primaryTargetLocalElementID: guidedStep.grounding.primaryTargetLocalElementID,
                fallbackTargetLocalElementID: guidedStep.grounding.fallbackTargetLocalElementID,
                status: .textOnlyFallback,
                origin: .unknown,
                targetType: nil,
                reason: "Owl Guide does not have a grounded local snapshot for this analysis yet.",
                confidenceNote: "Owl Guide cannot point to a trustworthy on-screen target without a grounded local snapshot.",
                downgradeReason: "No grounded local snapshot is available for this guided step."
            )
        }

        guard snapshot.contentRevision == targetContentRevision else {
            return OwlGuideGuidedStepGrounding(
                primaryTargetLocalElementID: guidedStep.grounding.primaryTargetLocalElementID,
                fallbackTargetLocalElementID: guidedStep.grounding.fallbackTargetLocalElementID,
                status: .textOnlyFallback,
                origin: .unknown,
                targetType: nil,
                reason: "This page changed after the last analysis, so Owl Guide is keeping the guidance text-only until you analyze it again.",
                confidenceNote: "Owl Guide will not keep showing a precise box when the analyzed page snapshot is no longer current.",
                downgradeReason: "The current page no longer matches the analyzed grounding snapshot."
            )
        }

        let primaryIdentifier = guidedStep.grounding.primaryTargetLocalElementID
        let fallbackIdentifier = guidedStep.grounding.fallbackTargetLocalElementID
        let intent = currentTaskThread?.chosenIntent ?? .understandPage

        // BYPASS SAFETY DOWNGRADE: Disable the forced text-only fallback over ambiguity or low confidence.
        /*
        if let currentTaskThread,
           !currentTaskThread.isConfirmed,
           guidedStep.clarificationQuestion != nil {
            return OwlGuideGuidedStepGrounding(
                primaryTargetLocalElementID: primaryIdentifier,
                fallbackTargetLocalElementID: fallbackIdentifier,
                status: .textOnlyFallback,
                origin: .unknown,
                targetType: nil,
                reason: "Owl Guide is still waiting to confirm the user's goal, so it is keeping the guidance in a clarification card instead of drawing a strong on-screen target.",
                confidenceNote: "The current goal is still ambiguous, so Owl Guide is avoiding a premature highlight.",
                downgradeReason: "Clarification is still needed before Owl Guide can ground one trustworthy next target."
            )
        }

        if currentTaskThread?.confidence == .low {
            return OwlGuideGuidedStepGrounding(
                primaryTargetLocalElementID: primaryIdentifier,
                fallbackTargetLocalElementID: fallbackIdentifier,
                status: .textOnlyFallback,
                origin: .unknown,
                targetType: nil,
                reason: "Owl Guide's current understanding is still low-confidence, so it is keeping the guidance text-only for now.",
                confidenceNote: "Low confidence is a better fit for a clarification card than for a precise or regional highlight.",
                downgradeReason: "The current interpretation is not stable enough to justify an on-screen highlight."
            )
        }
        */

        if let primaryCandidate = resolveSnapshotCandidate(withIdentifier: primaryIdentifier, in: snapshot),
           hasTrustworthyOverlayBounds(for: primaryCandidate.element, targetWindowFrame: snapshot.targetWindowFrame) {
            
            // NOTE: Do NOT override groundedTargetBounds here.
            // Visual grounding (from resolvedGroundedTargetState) has already set it correctly.
            // The old HACKATHON FORCE GROUNDING OVERRIDE was overwriting visual bounding box
            // coordinates with AX-derived bounds, causing the arrow to point to wrong locations.
            
            return OwlGuideGuidedStepGrounding(
                primaryTargetLocalElementID: primaryCandidate.candidateIdentifier,
                fallbackTargetLocalElementID: resolveSnapshotCandidate(withIdentifier: fallbackIdentifier, in: snapshot)?.candidateIdentifier,
                status: .axGroundedPreciseTarget,
                origin: .recommendedTarget,
                targetType: targetType(for: primaryCandidate),
                reason: preciseGroundingReason(for: primaryCandidate),
                confidenceNote: "Owl Guide found a grounded local target that matches the current next step strongly enough to show a precise highlight.",
                downgradeReason: nil
            )
        }

        if let fallbackCandidate = resolveSnapshotCandidate(withIdentifier: fallbackIdentifier, in: snapshot),
           hasTrustworthyOverlayBounds(for: fallbackCandidate.element, targetWindowFrame: snapshot.targetWindowFrame) {
            
            return OwlGuideGuidedStepGrounding(
                primaryTargetLocalElementID: fallbackCandidate.candidateIdentifier,
                fallbackTargetLocalElementID: nil,
                status: .axGroundedPreciseTarget,
                origin: .recommendedTarget,
                targetType: targetType(for: fallbackCandidate),
                reason: "Owl Guide could not trust the first linked target, so it is using a grounded backup target from the same analysis snapshot.",
                confidenceNote: "Owl Guide still has a strong local match for the next step, but it had to use a grounded backup target.",
                downgradeReason: nil
            )
        }

        if let semanticMatch = semanticFallbackCandidate(for: guidedStep, intent: intent, in: snapshot),
           hasTrustworthyOverlayBounds(for: semanticMatch.element, targetWindowFrame: snapshot.targetWindowFrame) {
            
            return OwlGuideGuidedStepGrounding(
                primaryTargetLocalElementID: semanticMatch.candidateIdentifier,
                fallbackTargetLocalElementID: nil,
                status: .axGroundedPreciseTarget,
                origin: .axLocalCandidate,
                targetType: targetType(for: semanticMatch),
                reason: "Owl Guide chose a higher-value local target for this step because the exact linked element did not look like the most useful place to start.",
                confidenceNote: "Owl Guide found a stronger grounded local target for this next step and can show it precisely.",
                downgradeReason: nil
            )
        }

        if let broaderRegion = broaderContentRegionCandidate(for: guidedStep, intent: intent, in: snapshot),
           hasTrustworthyOverlayBounds(for: broaderRegion.element, targetWindowFrame: snapshot.targetWindowFrame) {
            
            return OwlGuideGuidedStepGrounding(
                primaryTargetLocalElementID: broaderRegion.candidateIdentifier,
                fallbackTargetLocalElementID: nil,
                status: .regionLevelFallback,
                origin: .derivedContentAnchor,
                targetType: .contentArea,
                reason: "Owl Guide could not find a precise local control, so it is falling back to a broader grounded content region.",
                confidenceNote: "Owl Guide is confident about the general workflow area, but not about one exact element.",
                downgradeReason: "A broader region is safer than a wrong precise highlight for this guided step."
            )
        }

        return OwlGuideGuidedStepGrounding(
            primaryTargetLocalElementID: primaryIdentifier,
            fallbackTargetLocalElementID: fallbackIdentifier,
            status: .textOnlyFallback,
            origin: .unknown,
            targetType: nil,
            reason: "Owl Guide does not have a trustworthy grounded region for this next step, so it is keeping the guidance text-only.",
            confidenceNote: "Owl Guide is not confident enough to draw a reliable on-screen highlight for this step.",
            downgradeReason: "No stable local target or trustworthy region could be resolved from the analyzed snapshot."
        )
    }

    private func invalidateGroundingSnapshot() {
        targetContentRevision += 1
        analysisGroundingSnapshot = nil
        analysisPresentationTargetWindowFrame = nil
    }

    private func makeGroundingSnapshot(contentRevision: Int) -> GuidedStepGroundingSnapshot? {
        guard let targetWindowFrame = sanitizedTargetWindowFrame() else {
            return nil
        }

        return GuidedStepGroundingSnapshot(
            contentRevision: contentRevision,
            targetWindowFrame: targetWindowFrame,
            actionableCandidates: topActionableElements.map {
                makeGroundingCandidate(from: $0, prefix: "actionable", source: .actionable)
            },
            readableCandidates: topReadableElements.map {
                makeGroundingCandidate(from: $0, prefix: "readable", source: .readable)
            }
        )
    }

    private func makeGroundingCandidate(
        from rankedElement: AXRankedElement,
        prefix: String,
        source: AXSelectionSource
    ) -> GuidedStepGroundingCandidate {
        GuidedStepGroundingCandidate(
            candidateIdentifier: candidateIdentifier(for: rankedElement, prefix: prefix),
            source: source,
            element: rankedElement.element,
            score: rankedElement.score,
            reasonTags: rankedElement.reasonTags
        )
    }

    private func resolveSnapshotCandidate(
        withIdentifier identifier: String?,
        in snapshot: GuidedStepGroundingSnapshot
    ) -> GuidedStepGroundingCandidate? {
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty else {
            return nil
        }

        return snapshot.allCandidates.first(where: { $0.candidateIdentifier == identifier })
    }

    private func semanticFallbackCandidate(
        for guidedStep: OwlGuideGuidedStep,
        intent: OwlGuideUserIntent,
        in snapshot: GuidedStepGroundingSnapshot
    ) -> GuidedStepGroundingCandidate? {
        let targetText = guidedStep.nextStep
        let scoredMatches = snapshot.allCandidates.compactMap { candidate -> (GuidedStepGroundingCandidate, Int)? in
            guard !isLikelyWindowControl(candidate),
                  hasTrustworthyOverlayBounds(for: candidate.element, targetWindowFrame: snapshot.targetWindowFrame) else {
                return nil
            }

            let score = guidedGroundingValueScore(
                intent: intent,
                targetText: targetText,
                candidate: candidate
            )
            guard score >= 7 else {
                return nil
            }

            return (candidate, score)
        }

        return scoredMatches
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return candidateSortScore(lhs.0) > candidateSortScore(rhs.0)
                }
                return lhs.1 > rhs.1
            }
            .first?.0
    }

    private func broaderContentRegionCandidate(
        for guidedStep: OwlGuideGuidedStep,
        intent: OwlGuideUserIntent,
        in snapshot: GuidedStepGroundingSnapshot
    ) -> GuidedStepGroundingCandidate? {
        let targetText = guidedStep.nextStep
        let candidate = snapshot.readableCandidates
            .filter { candidate in
                candidate.element.hasUsefulText
                    && candidate.element.hasMeaningfulBounds
                    && !isLikelyWindowControl(candidate)
                    && hasTrustworthyOverlayBounds(for: candidate.element, targetWindowFrame: snapshot.targetWindowFrame)
            }
            .map { candidate in
                (
                    candidate,
                    guidedGroundingValueScore(
                        intent: intent,
                        targetText: targetText,
                        candidate: candidate
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return candidateSortScore(lhs.0) > candidateSortScore(rhs.0)
                }
                return lhs.1 > rhs.1
            }
            .first?.0

        return candidate ?? snapshot.readableCandidates.first(where: {
            $0.element.hasUsefulText
                && $0.element.hasMeaningfulBounds
                && !isLikelyWindowControl($0)
                && hasTrustworthyOverlayBounds(for: $0.element, targetWindowFrame: snapshot.targetWindowFrame)
        })
    }

    private func preferredGuidedTargetType(for intent: OwlGuideUserIntent) -> OwlGuideGuidedStepTargetType {
        switch intent {
        case .signIn, .recoverAccount, .bookAppointment, .sendMessage, .payBill, .accessMedicalImages, .continueApplication, .confirmProfile:
            return .control
        case .learnServices, .findResources, .checkResults, .findDoctor, .checkStatus, .understandPage:
            return .contentArea
        }
    }

    private func canUsePreciseRelayPresentation(for guidedStep: OwlGuideGuidedStep) -> Bool {
        guard let currentTaskThread else {
            return false
        }

        guard currentTaskThread.isConfirmed, guidedStep.clarificationQuestion == nil else {
            return false
        }

        return currentTaskThread.confidence != .low
    }

    private func shouldTrustExactGuidedTarget(
        _ candidate: GuidedStepGroundingCandidate,
        preferredTargetType: OwlGuideGuidedStepTargetType,
        guidedStep: OwlGuideGuidedStep
    ) -> Bool {
        guard let currentTaskThread,
              canUsePreciseRelayPresentation(for: guidedStep) else {
            return false
        }

        let targetText = guidedStep.nextStep
        let score = guidedGroundingValueScore(
            intent: currentTaskThread.chosenIntent,
            targetText: targetText,
            candidate: candidate
        )

        let targetTypeMatches = targetType(for: candidate) == preferredTargetType

        if isGenericGroundingCandidate(candidate) {
            return score >= 10 && currentTaskThread.confidence == .high && targetTypeMatches
        }

        if currentTaskThread.confidence == .high {
            return targetTypeMatches ? score >= 7 : score >= 9
        }

        return targetTypeMatches && score >= 10
    }

    private func guidedGroundingValueScore(
        intent: OwlGuideUserIntent,
        targetText: String,
        candidate: GuidedStepGroundingCandidate
    ) -> Int {
        var score = semanticMatchScore(targetText: targetText, candidate: candidate)
        score += max((candidate.score ?? 0) / 4, 0)

        if candidate.element.hasUsefulText {
            score += 2
        }

        if candidate.element.hasMeaningfulBounds {
            score += 1
        }

        if targetType(for: candidate) == preferredGuidedTargetType(for: intent) {
            score += 3
        }

        if isGenericGroundingCandidate(candidate) {
            score -= 4
        }

        if candidate.element.isContainerLike {
            score -= 3
        }

        if isLikelyWindowControl(candidate) {
            score -= 100
        }

        return score
    }

    private func isGenericGroundingCandidate(_ candidate: GuidedStepGroundingCandidate) -> Bool {
        let normalizedLabel = candidate.element.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let readableFallback = readableRoleFallback(for: candidate.element.role).lowercased()
        let genericLabels: Set<String> = [
            "button",
            "link",
            "text",
            "text field",
            "group",
            "layout area",
            "scroll area",
            "toolbar",
            "list",
            "browser",
            "screen",
            "page",
            "area"
        ]

        if !candidate.element.hasUsefulText && (candidate.element.isContainerLike || isControlRole(candidate.element.role)) {
            return true
        }

        if normalizedLabel == readableFallback || normalizedLabel == candidate.element.role.lowercased() {
            return true
        }

        return genericLabels.contains(normalizedLabel)
    }

    private func semanticMatchScore(targetText: String, candidate: GuidedStepGroundingCandidate) -> Int {
        let normalizedTarget = normalizedSemanticText(targetText)
        guard !normalizedTarget.isEmpty else {
            return 0
        }

        let candidateTexts = [
            candidate.element.displayName,
            candidate.element.title,
            candidate.element.label,
            candidate.element.value
        ]

        let normalizedCandidateText = normalizedSemanticText(candidateTexts.joined(separator: " "))
        let targetTokens = significantTokens(in: normalizedTarget)
        let candidateTokens = significantTokens(in: normalizedCandidateText)
        let overlap = targetTokens.intersection(candidateTokens).count

        var score = overlap

        if !normalizedCandidateText.isEmpty && normalizedTarget.contains(normalizedCandidateText) {
            score += 2
        }

        if !normalizedCandidateText.isEmpty && normalizedCandidateText.contains(normalizedTarget) {
            score += 1
        }

        if candidate.source == .actionable {
            score += 1
        }

        if candidate.element.hasMeaningfulBounds {
            score += 1
        }

        return score
    }

    private func candidateSortScore(_ candidate: GuidedStepGroundingCandidate) -> Int {
        var score = candidate.score ?? 0

        if candidate.source == .actionable {
            score += 2
        }

        if candidate.element.hasUsefulText {
            score += 1
        }

        return score
    }

    private func isLikelyWindowControl(_ candidate: GuidedStepGroundingCandidate) -> Bool {
        let hints = [
            candidate.element.role,
            candidate.element.subrole,
            candidate.element.title,
            candidate.element.label,
            candidate.element.value
        ]
        .joined(separator: " ")
        .lowercased()

        let blockedTerms = ["close", "minimize", "zoom", "fullscreen", "toolbar button"]
        return blockedTerms.contains { hints.contains($0) }
    }

    private func normalizedSemanticText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "[^\\p{L}\\p{N} ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func significantTokens(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "to", "for", "of", "on", "in", "with",
            "this", "that", "your", "you", "before", "after", "main", "next", "step",
            "start", "review", "look", "open", "find", "page", "screen", "area"
        ]

        return Set(
            text
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 3 && !stopWords.contains($0) }
        )
    }

    private func hasTrustworthyOverlayBounds(for element: AXElementNode, targetWindowFrame: CGRect) -> Bool {
        guard let bounds = element.boundsRect else {
            return false
        }

        return validatedOverlayFrame(for: bounds, targetWindowFrame: targetWindowFrame) != nil
    }

    private func liveWindowFrameHasMateriallyShifted(from snapshotFrame: CGRect, to liveFrame: CGRect) -> Bool {
        let original = snapshotFrame.standardized
        let current = liveFrame.standardized

        let deltaX = abs(original.minX - current.minX)
        let deltaY = abs(original.minY - current.minY)
        let widthDeltaRatio = abs(original.width - current.width) / max(original.width, 1)
        let heightDeltaRatio = abs(original.height - current.height) / max(original.height, 1)

        return deltaX > 32
            || deltaY > 32
            || widthDeltaRatio > 0.12
            || heightDeltaRatio > 0.12
    }

    private func targetType(for candidate: GuidedStepGroundingCandidate) -> OwlGuideGuidedStepTargetType {
        if candidate.source == .actionable || isControlRole(candidate.element.role) {
            return .control
        }

        return .contentArea
    }

    private func preciseGroundingReason(for candidate: GuidedStepGroundingCandidate) -> String {
        switch targetType(for: candidate) {
        case .control:
            return "Owl Guide matched the next step to a local control with usable AX bounds from the same analysis snapshot."
        case .contentArea:
            return "Owl Guide matched the next step to a locally grounded content area with usable AX bounds from the same analysis snapshot."
        }
    }

    private var capturedProcessIdentifier: pid_t? {
        Int32(capturedExternalTargetDebugInfo.processIdentifier)
    }

    private enum AutoAnalysisRefreshAction {
        case proceed
        case restartCountdown
    }

    private func currentCapturedTargetSignature() -> OwlInvocationTargetSignature? {
        guard let processIdentifier = optionalValue(from: capturedExternalTargetDebugInfo.processIdentifier) else {
            return nil
        }

        return OwlInvocationTargetSignature(
            processIdentifier: processIdentifier,
            windowTitle: optionalValue(from: capturedExternalTargetDebugInfo.windowTitle) ?? "Unavailable",
            windowRole: optionalValue(from: capturedExternalTargetDebugInfo.windowRole) ?? "Unavailable",
            windowSubrole: optionalValue(from: capturedExternalTargetDebugInfo.windowSubrole) ?? "Unavailable",
            frame: sanitizedTargetWindowFrame()
        )
    }

    private func targetSignature(
        from debugInfo: FrontmostAppDebugInfo,
        frame: CGRect?
    ) -> OwlInvocationTargetSignature? {
        guard let processIdentifier = optionalValue(from: debugInfo.processIdentifier) else {
            return nil
        }

        let sanitizedFrame = frame?.standardized.integral

        return OwlInvocationTargetSignature(
            processIdentifier: processIdentifier,
            windowTitle: optionalValue(from: debugInfo.windowTitle) ?? "Unavailable",
            windowRole: optionalValue(from: debugInfo.windowRole) ?? "Unavailable",
            windowSubrole: optionalValue(from: debugInfo.windowSubrole) ?? "Unavailable",
            frame: sanitizedFrame
        )
    }

    private func detectFreshExternalTarget() -> (debugInfo: FrontmostAppDebugInfo, windowElement: AXUIElement?, windowFrame: CGRect?, statusText: String)? {
        let currentApplication = frontmostAppDetector.currentFrontmostApplication()
        currentFrontmostAppDebugInfo = frontmostAppDetector.captureDebugInfo(for: currentApplication)

        if let currentApplication, !frontmostAppDetector.isOwlGuide(currentApplication) {
            lastNonSelfRunningApplication = currentApplication
            let capturedTarget = frontmostAppDetector.captureTarget(for: currentApplication)
            return (
                debugInfo: capturedTarget.debugInfo,
                windowElement: capturedTarget.windowElement,
                windowFrame: capturedTarget.windowFrame,
                statusText: "Captured the current external target before Owl Guide became frontmost."
            )
        }

        if let lastNonSelfRunningApplication, !lastNonSelfRunningApplication.isTerminated {
            let capturedTarget = frontmostAppDetector.captureTarget(for: lastNonSelfRunningApplication)
            return (
                debugInfo: capturedTarget.debugInfo,
                windowElement: capturedTarget.windowElement,
                windowFrame: capturedTarget.windowFrame,
                statusText: "Owl Guide is frontmost, so the most recent non-OwlGuide target is being preserved."
            )
        }

        return nil
    }

    private func applyDetectedExternalTarget(
        _ target: (debugInfo: FrontmostAppDebugInfo, windowElement: AXUIElement?, windowFrame: CGRect?, statusText: String),
        resetDependentState: Bool
    ) {
        capturedExternalTargetDebugInfo = target.debugInfo
        capturedExternalWindowElement = target.windowElement
        capturedExternalWindowFrame = target.windowFrame
        capturedExternalTargetStatusText = target.statusText

        if resetDependentState {
            hideOverlayPreview(statusText: "Overlay preview was hidden because the captured external target changed.")
            hideWindowAnchor(statusText: "Window anchor was hidden because the captured external target changed.")
            resetScanState()
            resetScreenUnderstandingState(message: "Captured target updated. Run a fresh AX scan before asking Gemini to analyze this screen.")
        }

        refreshScreenUnderstandingReadiness()
    }

    private func targetHasMateriallyChanged(from oldSignature: OwlInvocationTargetSignature?, to newSignature: OwlInvocationTargetSignature?) -> Bool {
        guard let oldSignature, let newSignature else {
            return oldSignature?.processIdentifier != newSignature?.processIdentifier
        }

        guard oldSignature.processIdentifier == newSignature.processIdentifier else {
            return true
        }

        if oldSignature.windowTitle != newSignature.windowTitle
            || oldSignature.windowRole != newSignature.windowRole
            || oldSignature.windowSubrole != newSignature.windowSubrole {
            return true
        }

        switch (oldSignature.frame, newSignature.frame) {
        case let (.some(oldFrame), .some(newFrame)):
            return liveWindowFrameHasMateriallyShifted(from: oldFrame, to: newFrame)
        case (.none, .none):
            return false
        default:
            return true
        }
    }

    private func clearCurrentRelayPresentationForTargetChange(reason: String) {
        analysisPresentationTargetWindowFrame = nil
        clearRelayPresentation()
        hideOverlayPreview(statusText: reason)
        hideWindowAnchor(statusText: reason)
    }

    private func refreshCapturedContextForAutoAnalysis() -> AutoAnalysisRefreshAction {
        guard let freshTarget = detectFreshExternalTarget() else {
            owlInteractionState = .fallbackShown
            owlFallbackMessage = "I can't read this window reliably yet, so I do not want to guess. You can also tell me what you want to do."
            screenUnderstandingProgressStage = .failed
            screenUnderstandingState = .failure("Owl Guide could not refresh the captured target before automatic analysis.")
            return .restartCountdown
        }

        let previousSignature = owlInvocationTargetSignature ?? currentCapturedTargetSignature()
        applyDetectedExternalTarget(freshTarget, resetDependentState: false)
        let freshSignature = currentCapturedTargetSignature()

        if targetHasMateriallyChanged(from: previousSignature, to: freshSignature) {
            owlTimerRestartedDueToContextChange = true
            owlAutoAnalysisFired = false
            owlInvocationMode = .none
            owlInteractionState = .awaitingUserIntent
            isInspectorPresented = false
            isOwlInvocationPromptPresented = true
            owlInvocationTargetSignature = freshSignature
            // 已禁用自动30秒无输入扫描功能
            // startOwlIdleCountdown()
            return .restartCountdown
        }

        owlInvocationTargetSignature = freshSignature
        performCapturedTargetScan(
            resetAnalysisState: false,
            restoreOverlayPreview: false,
            restoreWindowAnchor: false
        )
        return .proceed
    }

    private func detectedLanguageCode(for text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private func makeScreenUnderstandingTargetSnapshot() -> ScreenUnderstandingTargetSnapshot {
        ScreenUnderstandingTargetSnapshot(
            appName: optionalValue(from: capturedExternalTargetDebugInfo.localizedName) ?? "Unknown App",
            bundleIdentifier: optionalValue(from: capturedExternalTargetDebugInfo.bundleIdentifier) ?? "Unavailable",
            processIdentifier: capturedExternalTargetDebugInfo.processIdentifier,
            windowTitle: optionalValue(from: capturedExternalTargetDebugInfo.windowTitle) ?? "Unavailable",
            windowRole: optionalValue(from: capturedExternalTargetDebugInfo.windowRole) ?? "Unavailable",
            windowSubrole: optionalValue(from: capturedExternalTargetDebugInfo.windowSubrole) ?? "Unavailable"
        )
    }

    private func determinePayloadRouting() -> ScreenUnderstandingPayloadRoutingDecision {
        let sampleActionable = Array(topActionableElements.prefix(Self.normalActionablePayloadLimit))
        let sampleReadable = Array(topReadableElements.prefix(Self.normalReadablePayloadLimit))
        let sampledCandidates = dedupedRankedElements(sampleActionable + sampleReadable)
        let topDominanceSample = dedupedRankedElements(Array(topActionableElements.prefix(3)) + Array(topReadableElements.prefix(3)))

        let genericCandidateCount = sampledCandidates.filter(isGenericCandidate).count
        let containerOrWindowControlCount = sampledCandidates.filter { rankedElement in
            rankedElement.element.isContainerLike || isLikelyWindowControl(rankedElement)
        }.count
        let meaningfulReadableCandidateCount = sampleReadable.filter(isMeaningfulReadableCandidate).count
        let topGenericCount = topDominanceSample.filter(isGenericCandidate).count

        let totalCandidatesEvaluated = sampledCandidates.count
        let genericCandidateRatio = ratio(numerator: genericCandidateCount, denominator: totalCandidatesEvaluated)
        let containerOrWindowControlRatio = ratio(
            numerator: containerOrWindowControlCount,
            denominator: totalCandidatesEvaluated
        )
        let topCandidatesMostlyGeneric = !topDominanceSample.isEmpty && topGenericCount * 2 >= topDominanceSample.count

        let shouldPreferMinimal =
            readableCandidateCount < 5
            || meaningfulReadableCandidateCount < 3
            || genericCandidateRatio >= 0.5
            || containerOrWindowControlRatio >= 0.45
            || topCandidatesMostlyGeneric

        let reason: String
        if shouldPreferMinimal {
            if meaningfulReadableCandidateCount < 3 {
                reason = "Minimal payload chosen because the local AX sample has too few meaningful readable candidates."
            } else if topCandidatesMostlyGeneric {
                reason = "Minimal payload chosen because the highest-ranked local candidates are mostly generic."
            } else if genericCandidateRatio >= 0.5 {
                reason = "Minimal payload chosen because generic AX candidates dominate the local sample."
            } else if containerOrWindowControlRatio >= 0.45 {
                reason = "Minimal payload chosen because container-like or window-control candidates dominate the local sample."
            } else {
                reason = "Minimal payload chosen because the local AX candidate set is sparse."
            }
        } else {
            reason = "Normal payload chosen because the local AX sample has enough meaningful readable candidates and low generic dominance."
        }

        return ScreenUnderstandingPayloadRoutingDecision(
            mode: shouldPreferMinimal ? .minimal : .normal,
            diagnostics: ScreenUnderstandingPayloadRoutingDiagnostics(
                reason: reason,
                totalCandidatesEvaluated: totalCandidatesEvaluated,
                genericCandidateCount: genericCandidateCount,
                genericCandidateRatio: genericCandidateRatio,
                containerOrWindowControlCount: containerOrWindowControlCount,
                containerOrWindowControlRatio: containerOrWindowControlRatio,
                topCandidatesMostlyGeneric: topCandidatesMostlyGeneric,
                meaningfulReadableCandidateCount: meaningfulReadableCandidateCount
            )
        )
    }

    private func determineAnalysisMode(
        payloadRouting: ScreenUnderstandingPayloadRoutingDiagnostics,
        scenarioContext: OwlGuideScenarioContext,
        sendImage: GeminiSendImage,
        userRequestPresent: Bool
    ) -> ScreenUnderstandingAnalysisDecision {
        let sampledCandidateCount = payloadRouting.totalCandidatesEvaluated
        let filteredCount = filteredUsefulElements.count
        let totalRankedCandidates = actionableCandidateCount + readableCandidateCount
        let screenshotLongEdge = max(sendImage.pixelWidth, sendImage.pixelHeight)

        let shouldSimplify =
            userRequestPresent
            || filteredCount >= 20
            || totalRankedCandidates >= 18
            || sampledCandidateCount >= 10
            || (payloadRouting.topCandidatesMostlyGeneric && totalRankedCandidates >= 10)
            || (payloadRouting.containerOrWindowControlRatio >= 0.45 && totalRankedCandidates >= 10)
            || (payloadRouting.genericCandidateRatio >= 0.55 && totalRankedCandidates >= 10)
            || (sendImage.byteCount >= 1_000_000 && screenshotLongEdge >= 1400)
            || (scenarioContext.confidence == .low && totalRankedCandidates >= 14)

        let reason: String
        if shouldSimplify {
            if userRequestPresent {
                reason = "Simplified analysis mode chosen because the user asked a direct question and Owl Guide should answer with a smaller, safer result."
            } else if filteredCount >= 20 {
                reason = "Dense screen detected because the filtered useful-element set is large."
            } else if totalRankedCandidates >= 18 {
                reason = "Dense screen detected because Owl Guide found many ranked local candidates."
            } else if sampledCandidateCount >= 10 && payloadRouting.topCandidatesMostlyGeneric {
                reason = "Dense screen detected because the top local candidate sample is large and mostly generic."
            } else if payloadRouting.containerOrWindowControlRatio >= 0.45 && totalRankedCandidates >= 10 {
                reason = "Dense screen detected because container-like or window-control candidates dominate a large local sample."
            } else if payloadRouting.genericCandidateRatio >= 0.55 && totalRankedCandidates >= 10 {
                reason = "Dense screen detected because a large local sample is heavily generic."
            } else if sendImage.byteCount >= 1_000_000 && screenshotLongEdge >= 1400 {
                reason = "Dense screen detected because the Gemini send-image is still relatively large after optimization."
            } else {
                reason = "Dense screen detected because routing confidence is low on a screen with many ranked candidates."
            }
        } else {
            reason = "Standard analysis mode chosen because local complexity signals stayed within the normal one-request budget."
        }

        return ScreenUnderstandingAnalysisDecision(
            mode: shouldSimplify ? .simplifiedHighComplexity : .normal,
            diagnostics: ScreenUnderstandingComplexityDiagnostics(
                reason: reason,
                sampledCandidateCount: sampledCandidateCount,
                filteredUsefulElementCount: filteredCount,
                actionableCandidateCount: actionableCandidateCount,
                readableCandidateCount: readableCandidateCount,
                genericCandidateRatio: payloadRouting.genericCandidateRatio,
                containerOrWindowControlRatio: payloadRouting.containerOrWindowControlRatio,
                topCandidatesMostlyGeneric: payloadRouting.topCandidatesMostlyGeneric,
                screenshotLongEdge: screenshotLongEdge,
                sendImageByteCount: sendImage.byteCount,
                routingConfidence: scenarioContext.confidence
            )
        )
    }

    private func makeScreenUnderstandingContext(
        payloadMode: ScreenUnderstandingPayloadMode,
        analysisMode: ScreenUnderstandingAnalysisMode,
        scenarioContext: OwlGuideScenarioContext,
        browserCapture: BrowserCaptureAttemptResult,
        userRequest: String?,
        preferredResponseLanguageCode: String?
    ) -> ScreenUnderstandingContext {
        let candidateLimits = browserAwareCandidateLimits(
            payloadMode: payloadMode,
            analysisMode: analysisMode,
            scenarioContext: scenarioContext,
            browserCapture: browserCapture
        )
        let actionableLimit = candidateLimits.actionable
        let readableLimit = candidateLimits.readable
        let actionableSource = Array(topActionableElements.prefix(actionableLimit))
        let readableSource = Array(topReadableElements.prefix(readableLimit))

        return ScreenUnderstandingContext(
            userRequest: userRequest?.isEmpty == false ? userRequest : nil,
            preferredResponseLanguageCode: preferredResponseLanguageCode,
            appName: optionalValue(from: capturedExternalTargetDebugInfo.localizedName),
            bundleIdentifier: optionalValue(from: capturedExternalTargetDebugInfo.bundleIdentifier),
            windowTitle: optionalValue(from: capturedExternalTargetDebugInfo.windowTitle),
            browserHostname: scenarioContext.browserHostname,
            browserContext: browserCapture.context,
            scenarioContext: scenarioContext,
            actionableCandidatesAvailable: actionableCandidateCount,
            readableCandidatesAvailable: readableCandidateCount,
            topActionableElements: actionableSource.enumerated().map { index, rankedElement in
                makeScreenUnderstandingCandidate(
                    from: rankedElement,
                    rank: index + 1,
                    prefix: "actionable"
                )
            },
            topReadableElements: readableSource.enumerated().map { index, rankedElement in
                makeScreenUnderstandingCandidate(
                    from: rankedElement,
                    rank: index + 1,
                    prefix: "readable"
                )
            }
        )
    }

    private func browserAwareCandidateLimits(
        payloadMode: ScreenUnderstandingPayloadMode,
        analysisMode: ScreenUnderstandingAnalysisMode,
        scenarioContext: OwlGuideScenarioContext,
        browserCapture: BrowserCaptureAttemptResult
    ) -> (actionable: Int, readable: Int) {
        let baseActionable = analysisActionableLimit(for: payloadMode, analysisMode: analysisMode)
        let baseReadable = analysisReadableLimit(for: payloadMode, analysisMode: analysisMode)

        guard browserCapture.context != nil else {
            return (baseActionable, baseReadable)
        }

        let pageType = scenarioContext.likelyPageType
        if pageType == "Home page / navigation hub" || pageType == "Menu-heavy directory or portal page" {
            return (min(baseActionable, 3), min(baseReadable, 4))
        }

        if pageType == "Information / guide page" {
            return (min(baseActionable, 3), min(baseReadable, 5))
        }

        return (baseActionable, baseReadable)
    }

    private func detectScenarioContext(
        targetSnapshot: ScreenUnderstandingTargetSnapshot,
        browserCapture: BrowserCaptureAttemptResult,
        userRequest: String?
    ) -> OwlGuideScenarioContext {
        scenarioSkillRouter.detectContext(
            userRequest: userRequest,
            appName: targetSnapshot.appName,
            bundleIdentifier: targetSnapshot.bundleIdentifier,
            windowTitle: targetSnapshot.windowTitle,
            browserCapture: browserCapture.context,
            actionableCandidates: topActionableElements,
            readableCandidates: topReadableElements,
            rawElements: rawScannedElements
        )
    }

    private func shouldTreatAnalysisAsAnswered(
        scenarioGuidance: OwlGuideScenarioGuidance?,
        result: ScreenUnderstandingResult,
        userRequest: String?
    ) -> Bool {
        let hasDirectUserQuestion = userRequest?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasAnswerText = !result.pageSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasDirectUserQuestion && hasAnswerText {
            return true
        }

        return scenarioGuidance?.firstResponse.clarificationQuestion == nil
    }

    private func dedupedRankedElements(_ rankedElements: [AXRankedElement]) -> [AXRankedElement] {
        var seenPaths = Set<String>()

        return rankedElements.filter { rankedElement in
            seenPaths.insert(rankedElement.element.path).inserted
        }
    }

    private func isMeaningfulReadableCandidate(_ rankedElement: AXRankedElement) -> Bool {
        rankedElement.element.hasUsefulText
            && !rankedElement.element.isContainerLike
            && !isLikelyWindowControl(rankedElement)
            && !isGenericCandidate(rankedElement)
    }

    private func isGenericCandidate(_ rankedElement: AXRankedElement) -> Bool {
        let label = compactCandidateLabel(for: rankedElement.element).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = label.lowercased()
        let readableFallback = readableRoleFallback(for: rankedElement.element.role).lowercased()
        let genericLabels: Set<String> = [
            "button",
            "text",
            "link",
            "text field",
            "group",
            "layout area",
            "scroll area",
            "toolbar",
            "list",
            "browser"
        ]

        if !rankedElement.element.hasUsefulText && (rankedElement.element.isContainerLike || isControlRole(rankedElement.element.role)) {
            return true
        }

        if normalizedLabel == readableFallback || normalizedLabel == rankedElement.element.role.lowercased() {
            return true
        }

        return genericLabels.contains(normalizedLabel)
    }

    private func ratio(numerator: Int, denominator: Int) -> Double {
        guard denominator > 0 else {
            return 0
        }

        return Double(numerator) / Double(denominator)
    }

    private func percentageString(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func makeScreenUnderstandingCandidate(
        from rankedElement: AXRankedElement,
        rank: Int,
        prefix: String
    ) -> ScreenUnderstandingCandidate {
        ScreenUnderstandingCandidate(
            id: candidateIdentifier(for: rankedElement, prefix: prefix),
            rank: rank,
            label: compactCandidateLabel(for: rankedElement.element),
            semanticHint: compactSemanticHint(for: rankedElement.element),
            role: rankedElement.element.role,
            subrole: optionalValue(from: rankedElement.element.subrole),
            bounds: boundsPayload(for: rankedElement.element),
            score: rankedElement.score,
            signals: compactSignals(for: rankedElement)
        )
    }

    private func candidateIdentifier(for rankedElement: AXRankedElement, prefix: String) -> String {
        "\(prefix):\(rankedElement.element.path)"
    }

    private func compactCandidateLabel(for element: AXElementNode) -> String {
        let preferredText = [element.title, element.label, element.value, element.displayName]
            .first(where: { candidate in
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed != "Unavailable" && !trimmed.isEmpty
            }) ?? readableRoleFallback(for: element.role)

        return truncatedCaption(preferredText)
    }

    private func compactSemanticHint(for element: AXElementNode) -> String {
        let preferredText = [element.title, element.label, element.value]
            .first(where: { candidate in
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed != "Unavailable" && !trimmed.isEmpty
            }) ?? readableRoleFallback(for: element.role)

        return truncatedSemanticHint(preferredText)
    }

    private func compactSignals(for rankedElement: AXRankedElement) -> [String] {
        var signals: [String] = []

        if rankedElement.element.hasUsefulText {
            signals.append("text")
        }

        if isControlRole(rankedElement.element.role) {
            signals.append("control")
        }

        if rankedElement.reasonTags.contains("window control down-rank") {
            signals.append("windowControl")
        }

        if rankedElement.element.isContainerLike {
            signals.append("container")
        }

        if rankedElement.element.hasMeaningfulBounds {
            signals.append("meaningfulBounds")
        }

        return Array(signals.prefix(5))
    }

    private func linkedElementInspection(for target: ScreenUnderstandingRecommendedTarget) -> AXSelectedElementInspection? {
        guard let resolvedTarget = resolveRecommendedTarget(for: target) else {
            return nil
        }

        return AXSelectedElementInspection(
            source: resolvedTarget.source,
            element: resolvedTarget.element,
            score: resolvedTarget.score,
            reasonTags: resolvedTarget.reasonTags
        )
    }

    private func boundsPayload(for element: AXElementNode) -> ScreenUnderstandingBounds? {
        guard let bounds = element.boundsRect else {
            return nil
        }

        return ScreenUnderstandingBounds(
            x: bounds.origin.x,
            y: bounds.origin.y,
            width: bounds.size.width,
            height: bounds.size.height
        )
    }

    private func groundedRecommendedTargetIdentifiers(
        for grounding: OwlGuideGuidedStepGrounding
    ) -> (primary: String?, fallback: String?) {
        guard let result = screenUnderstandingResult else {
            return (
                grounding.primaryTargetLocalElementID,
                grounding.fallbackTargetLocalElementID
            )
        }

        let primary = result.recommendedTargets.first.flatMap { resolveRecommendedTarget(for: $0)?.candidateIdentifier }
        let fallback = result.recommendedTargets.dropFirst().first.flatMap { resolveRecommendedTarget(for: $0)?.candidateIdentifier }
        return (
            primary ?? grounding.primaryTargetLocalElementID,
            fallback ?? grounding.fallbackTargetLocalElementID
        )
    }

    private func resolveRecommendedTarget(
        for target: ScreenUnderstandingRecommendedTarget
    ) -> ResolvedRecommendedTarget? {
//        print("[ArrowGuide] 🔍 Trying to resolve target: label=\"\(target.label)\" relatedLocalElement=\"\(target.relatedLocalElement)\"")

        if let identifierMatch = resolveRecommendedTargetByIdentifier(target.relatedLocalElement) {
//            print("[ArrowGuide]   ✅ Identifier match found: \"\(identifierMatch.element.displayName)\" role=\(identifierMatch.element.role) bounds=\(String(describing: identifierMatch.bounds))")
            return identifierMatch
        }
//        print("[ArrowGuide]   ℹ️ No identifier match, trying label fallback...")

        // Log all top candidates for diagnosis
//        print("[ArrowGuide]   📋 Top actionable elements (\(topActionableElements.count) total):")
//        for (i, ranked) in topActionableElements.prefix(10).enumerated() {
//            let elem = ranked.element
//            print("[ArrowGuide]     [\(i)] \"\(elem.displayName)\" role=\(elem.role) title=\"\(elem.title)\" label=\"\(elem.label)\" bounds=\(String(describing: elem.boundsRect))")
//        }

        if let labelMatch = resolveRecommendedTargetByLabel(target.label) {
//            print("[ArrowGuide]   ✅ Label match found: \"\(labelMatch.element.displayName)\" role=\(labelMatch.element.role) bounds=\(String(describing: labelMatch.bounds))")
            return labelMatch
        } else {
//            print("[ArrowGuide]   ❌ No label match found for \"\(target.label)\"")
        }
        return nil
    }

    private func updateGroundedTargetState(from recommendedTargets: [ScreenUnderstandingRecommendedTarget]) {
        let groundedTargetState = resolvedGroundedTargetState(
            for: recommendedTargets,
            targetWindowFrame: sanitizedTargetWindowFrame()
        )
        DispatchQueue.main.async { [weak self] in
            self?.applyGroundedTargetState(groundedTargetState)
            self?.triggerAutopilotIfEnabled()
            self?.refreshOverlayPresentationRequest()
        }
    }

    private func resolveRecommendedTargetByIdentifier(_ identifier: String) -> ResolvedRecommendedTarget? {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else {
            return nil
        }

        if let actionableMatch = exactRecommendedTargetMatch(
            in: topActionableElements,
            prefix: "actionable",
            source: .actionable,
            identifier: trimmedIdentifier
        ) {
            return actionableMatch
        }

        return exactRecommendedTargetMatch(
            in: topReadableElements,
            prefix: "readable",
            source: .readable,
            identifier: trimmedIdentifier
        )
    }

    private func resolveRecommendedTargetByLabel(_ label: String) -> ResolvedRecommendedTarget? {
        let normalizedLabel = normalizedSemanticText(label)
        guard !normalizedLabel.isEmpty else {
            return nil
        }

        let actionableMatch = scoredRecommendedTargetLabelMatches(
            in: topActionableElements,
            prefix: "actionable",
            source: .actionable,
            targetLabel: label
        ).first?.match
        if let actionableMatch {
            return actionableMatch
        }

        return scoredRecommendedTargetLabelMatches(
            in: topReadableElements,
            prefix: "readable",
            source: .readable,
            targetLabel: label
        ).first?.match
    }

    private func exactRecommendedTargetMatch(
        in rankedElements: [AXRankedElement],
        prefix: String,
        source: AXSelectionSource,
        identifier: String
    ) -> ResolvedRecommendedTarget? {
        guard let rankedElement = rankedElements.first(where: {
            candidateIdentifier(for: $0, prefix: prefix) == identifier
        }),
        let bounds = rankedElement.element.boundsRect?.standardized else {
            return nil
        }

        return ResolvedRecommendedTarget(
            candidateIdentifier: candidateIdentifier(for: rankedElement, prefix: prefix),
            source: source,
            element: rankedElement.element,
            score: rankedElement.score,
            reasonTags: rankedElement.reasonTags,
            strategy: .relatedLocalElement,
            bounds: bounds
        )
    }

    private func scoredRecommendedTargetLabelMatches(
        in rankedElements: [AXRankedElement],
        prefix: String,
        source: AXSelectionSource,
        targetLabel: String
    ) -> [(match: ResolvedRecommendedTarget, score: Int, sortScore: Int)] {
        rankedElements.compactMap { rankedElement in
            let candidate = makeGroundingCandidate(from: rankedElement, prefix: prefix, source: source)
            guard !isLikelyWindowControl(candidate),
                  let bounds = rankedElement.element.boundsRect?.standardized else {
                return nil
            }

            let score = recommendedTargetLabelMatchScore(targetLabel: targetLabel, candidate: candidate)
            guard score >= 5 else {
                return nil
            }

            return (
                match: ResolvedRecommendedTarget(
                    candidateIdentifier: candidate.candidateIdentifier,
                    source: source,
                    element: rankedElement.element,
                    score: rankedElement.score,
                    reasonTags: rankedElement.reasonTags,
                    strategy: .labelFallback,
                    bounds: bounds
                ),
                score: score,
                sortScore: candidateSortScore(candidate)
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.sortScore > rhs.sortScore
            }

            return lhs.score > rhs.score
        }
    }

    private func recommendedTargetLabelMatchScore(
        targetLabel: String,
        candidate: GuidedStepGroundingCandidate
    ) -> Int {
        let normalizedTarget = normalizedSemanticText(targetLabel)
        guard !normalizedTarget.isEmpty else {
            return 0
        }

        let candidateTexts = [
            candidate.element.displayName,
            candidate.element.title,
            candidate.element.label,
            candidate.element.value
        ]
        .map(normalizedSemanticText)
        .filter { !$0.isEmpty }

        guard !candidateTexts.isEmpty else {
            return 0
        }

        let exactMatch = candidateTexts.contains(normalizedTarget)
        let containsMatch = candidateTexts.contains { $0.contains(normalizedTarget) || normalizedTarget.contains($0) }

        var score = semanticMatchScore(targetText: targetLabel, candidate: candidate)
        if exactMatch {
            score += 6
        } else if containsMatch {
            score += 3
        }

        if candidate.source == .actionable {
            score += 2
        }

        return score
    }

    private func optionalValue(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "Unavailable", !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func pendingRequestSummary(
        for context: ScreenUnderstandingContext,
        modelConfiguration: GeminiModelConfiguration,
        payloadRouting: ScreenUnderstandingPayloadRoutingDiagnostics,
        payloadMode: ScreenUnderstandingPayloadMode,
        analysisMode: ScreenUnderstandingAnalysisMode,
        complexityDiagnostics: ScreenUnderstandingComplexityDiagnostics,
        browserCapture: BrowserCaptureAttemptResult,
        originalScreenshot: WindowScreenshot,
        sendImage: GeminiSendImage
    ) -> String {
        let contextSize = contextCharacterCount(for: context)

        return """
        Model: \(modelConfiguration.name)
        Model source: \(modelConfiguration.source.rawValue)
        Invocation mode: \(owlInvocationMode.rawValue)
        User request present: \((context.userRequest?.isEmpty == false) ? "Yes" : "No")
        Auto-analysis fired: \(owlAutoAnalysisFired ? "Yes" : "No")
        Idle timeout seconds: \(Self.owlPassiveAutoLookDelaySeconds)
        Focus lock active: \(owlFocusLockActive ? "Yes" : "No")
        Draft text preserved: \(owlDraftTextPreserved ? "Yes" : "No")
        Auto-analysis used fresh capture: \(owlAutoAnalysisUsedFreshCapture ? "Yes" : "No")
        Timer restarted due to context change: \(owlTimerRestartedDueToContextChange ? "Yes" : "No")
        Reply language mode: \(owlReplyLanguageMode.rawValue)
        Preferred response language: \(owlPreferredResponseLanguageCode ?? "System default")
        Payload mode: \(payloadMode.rawValue)
        Payload routing: \(payloadRouting.reason)
        Analysis mode: \(analysisMode.rawValue)
        Analysis mode detail: \(complexityDiagnostics.reason)
        App name: \(context.appName ?? "Unavailable")
        Bundle identifier: \(context.bundleIdentifier ?? "Unavailable")
        Window title: \(context.windowTitle ?? "Unavailable")
        Browser hostname: \(context.browserHostname ?? "Unavailable")
        Browser-aware capture attempted: \(browserCapture.attempted ? "Yes" : "No")
        Browser name: \(browserCapture.browserName ?? "Unavailable")
        Browser failure category: \(browserCapture.failureCategory?.rawValue ?? "None")
        Browser context mode: \(browserCapture.contextUsageDescription)
        Browser URL retrieval: \(browserCapture.urlRetrievalStatus)
        Browser URL: \(browserCapture.context?.currentURL ?? "Unavailable")
        Browser title retrieval: \(browserCapture.titleRetrievalStatus)
        Browser page title: \(browserCapture.context?.pageTitle ?? "Unavailable")
        Browser text summary: \(browserCapture.textSummaryStatus)
        Browser page identity: \(browserCapture.context?.pageIdentity ?? "Unavailable")
        Browser likely audience: \(browserCapture.context?.likelyAudience ?? "Unavailable")
        Browser primary entry points: \(browserCapture.context?.primaryEntryPoints.joined(separator: " | ") ?? "Unavailable")
        Browser safe starting point: \(browserCapture.context?.likelySafeStartingPoint ?? "Unavailable")
        Browser ambiguity note: \(browserCapture.context?.notableRiskOrAmbiguity ?? "Unavailable")
        User request: \(context.userRequest?.isEmpty == false ? context.userRequest! : "None")
        Original screenshot MIME type: \(originalScreenshot.mimeType)
        Original screenshot size: \(originalScreenshot.pixelWidth) × \(originalScreenshot.pixelHeight)
        Original screenshot bytes: \(originalScreenshot.byteCount)
        Original screenshot processing: \(originalScreenshot.processingDescription)
        Gemini send-image MIME type: \(sendImage.mimeType)
        Gemini send-image size: \(sendImage.pixelWidth) × \(sendImage.pixelHeight)
        Gemini send-image bytes: \(sendImage.byteCount)
        Gemini send-image downscaled: \(sendImage.didDownscale ? "Yes" : "No")
        Gemini send-image lossy compression: \(sendImage.usedLossyCompression ? "Yes" : "No")
        Gemini send-image processing: \(sendImage.processingDescription)
        Routed skill: \(context.scenarioContext.selectedSkill.displayName)
        Routed page type: \(context.scenarioContext.likelyPageType)
        Routed primary task: \(context.scenarioContext.likelyPrimaryTask)
        Routed backup task: \(context.scenarioContext.likelyBackupTask)
        Actionable available: \(context.actionableCandidatesAvailable)
        Readable available: \(context.readableCandidatesAvailable)
        Actionable candidates sent: \(context.topActionableElements.count)
        Readable candidates sent: \(context.topReadableElements.count)
        Routing sample size: \(payloadRouting.totalCandidatesEvaluated)
        Meaningful readable candidates: \(payloadRouting.meaningfulReadableCandidateCount)
        Generic candidates: \(payloadRouting.genericCandidateCount) (\(percentageString(payloadRouting.genericCandidateRatio)))
        Container/window-control candidates: \(payloadRouting.containerOrWindowControlCount) (\(percentageString(payloadRouting.containerOrWindowControlRatio)))
        Top candidates mostly generic: \(payloadRouting.topCandidatesMostlyGeneric ? "Yes" : "No")
        Filtered useful elements: \(complexityDiagnostics.filteredUsefulElementCount)
        Sampled candidate count: \(complexityDiagnostics.sampledCandidateCount)
        Send-image long edge: \(complexityDiagnostics.screenshotLongEdge)
        Send-image bytes: \(complexityDiagnostics.sendImageByteCount)
        Routing confidence: \(complexityDiagnostics.routingConfidence.displayName)
        Compact context characters: \(contextSize)
        """
    }

    private func contextCharacterCount(for context: ScreenUnderstandingContext) -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(context) else {
            return 0
        }

        return String(decoding: data, as: UTF8.self).count
    }

    private func debugInfo(
        for error: Error,
        totalElapsedTimeMilliseconds: Int? = nil
    ) -> ScreenUnderstandingDebugInfo {
        let modelConfiguration = geminiScreenUnderstandingService.currentModelConfiguration()
        let baseInfo = ScreenUnderstandingDebugInfo(
            keySource: geminiScreenUnderstandingService.currentKeySource(),
            modelName: modelConfiguration.name,
            modelSource: modelConfiguration.source,
            invocationMode: screenUnderstandingDebugInfo.invocationMode,
            userRequestPresent: screenUnderstandingDebugInfo.userRequestPresent,
            autoAnalysisFired: screenUnderstandingDebugInfo.autoAnalysisFired,
            idleTimeoutSeconds: screenUnderstandingDebugInfo.idleTimeoutSeconds,
            focusLockActive: screenUnderstandingDebugInfo.focusLockActive,
            draftTextPreserved: screenUnderstandingDebugInfo.draftTextPreserved,
            autoAnalysisUsedFreshCapture: screenUnderstandingDebugInfo.autoAnalysisUsedFreshCapture,
            timerRestartedDueToContextChange: screenUnderstandingDebugInfo.timerRestartedDueToContextChange,
            replyLanguageMode: screenUnderstandingDebugInfo.replyLanguageMode,
            preferredResponseLanguageCode: screenUnderstandingDebugInfo.preferredResponseLanguageCode,
            payloadMode: screenUnderstandingPayloadMode,
            analysisMode: screenUnderstandingDebugInfo.analysisMode,
            payloadRouting: screenUnderstandingDebugInfo.payloadRouting,
            complexityDiagnostics: screenUnderstandingDebugInfo.complexityDiagnostics,
            screenshotCaptured: false,
            originalScreenshotMimeType: screenUnderstandingDebugInfo.originalScreenshotMimeType,
            originalScreenshotWidth: screenUnderstandingDebugInfo.originalScreenshotWidth,
            originalScreenshotHeight: screenUnderstandingDebugInfo.originalScreenshotHeight,
            originalScreenshotByteCount: screenUnderstandingDebugInfo.originalScreenshotByteCount,
            originalScreenshotProcessingDescription: screenUnderstandingDebugInfo.originalScreenshotProcessingDescription,
            sendImageMimeType: screenUnderstandingDebugInfo.sendImageMimeType,
            sendImageWidth: screenUnderstandingDebugInfo.sendImageWidth,
            sendImageHeight: screenUnderstandingDebugInfo.sendImageHeight,
            sendImageByteCount: screenUnderstandingDebugInfo.sendImageByteCount,
            sendImageDidDownscale: screenUnderstandingDebugInfo.sendImageDidDownscale,
            sendImageUsedLossyCompression: screenUnderstandingDebugInfo.sendImageUsedLossyCompression,
            sendImageProcessingDescription: screenUnderstandingDebugInfo.sendImageProcessingDescription,
            actionableCandidatesAvailable: actionableCandidateCount,
            readableCandidatesAvailable: readableCandidateCount,
            actionableCandidatesSent: currentPayloadActionableCount,
            readableCandidatesSent: currentPayloadReadableCount,
            contextCharacterCount: 0,
            failureSource: failureSource(for: error),
            responseMimeType: GeminiScreenUnderstandingService.responseMimeType,
            responseSchemaModeEnabled: GeminiScreenUnderstandingService.responseSchemaModeEnabled,
            requestDiagnosticsNote: GeminiScreenUnderstandingService.requestDiagnosticsNote,
            maxOutputTokens: GeminiScreenUnderstandingService.maxOutputTokens,
            finishReason: nil,
            finishMessage: nil,
            promptTokenCount: nil,
            outputTokenCount: nil,
            totalTokenCount: nil,
            totalElapsedTimeMilliseconds: totalElapsedTimeMilliseconds ?? screenUnderstandingDebugInfo.totalElapsedTimeMilliseconds,
            screenshotPreparationTimeMilliseconds: screenUnderstandingDebugInfo.screenshotPreparationTimeMilliseconds,
            geminiRoundTripTimeMilliseconds: screenUnderstandingDebugInfo.geminiRoundTripTimeMilliseconds,
            httpStatusCode: nil,
            transportError: nil,
            rawResponseLength: 0,
            parserOutcome: .none,
            requestSummary: "No Gemini request yet.",
            rawResponseText: "No Gemini response yet.",
            recoveredJSONText: "No recovered JSON yet."
        )

        if let screenshotError = error as? WindowScreenshotError {
            return ScreenUnderstandingDebugInfo(
                keySource: baseInfo.keySource,
                modelName: baseInfo.modelName,
                modelSource: baseInfo.modelSource,
                invocationMode: baseInfo.invocationMode,
                userRequestPresent: baseInfo.userRequestPresent,
                autoAnalysisFired: baseInfo.autoAnalysisFired,
                idleTimeoutSeconds: baseInfo.idleTimeoutSeconds,
                focusLockActive: baseInfo.focusLockActive,
                draftTextPreserved: baseInfo.draftTextPreserved,
                autoAnalysisUsedFreshCapture: baseInfo.autoAnalysisUsedFreshCapture,
                timerRestartedDueToContextChange: baseInfo.timerRestartedDueToContextChange,
                replyLanguageMode: baseInfo.replyLanguageMode,
                preferredResponseLanguageCode: baseInfo.preferredResponseLanguageCode,
                payloadMode: baseInfo.payloadMode,
                analysisMode: baseInfo.analysisMode,
                payloadRouting: baseInfo.payloadRouting,
                complexityDiagnostics: baseInfo.complexityDiagnostics,
                browserCaptureAttempted: baseInfo.browserCaptureAttempted,
                browserName: baseInfo.browserName,
                browserFailureCategory: baseInfo.browserFailureCategory,
                browserContextUsageDescription: baseInfo.browserContextUsageDescription,
                browserCurrentURL: baseInfo.browserCurrentURL,
                browserURLRetrievalStatus: baseInfo.browserURLRetrievalStatus,
                browserPageTitle: baseInfo.browserPageTitle,
                browserTitleRetrievalStatus: baseInfo.browserTitleRetrievalStatus,
                browserVisibleTextSummaryAvailable: baseInfo.browserVisibleTextSummaryAvailable,
                browserTextSummaryStatus: baseInfo.browserTextSummaryStatus,
                browserPrimaryEntryPointCount: baseInfo.browserPrimaryEntryPointCount,
                screenshotCaptured: false,
                originalScreenshotMimeType: baseInfo.originalScreenshotMimeType,
                originalScreenshotWidth: baseInfo.originalScreenshotWidth,
                originalScreenshotHeight: baseInfo.originalScreenshotHeight,
                originalScreenshotByteCount: baseInfo.originalScreenshotByteCount,
                originalScreenshotProcessingDescription: baseInfo.originalScreenshotProcessingDescription,
                sendImageMimeType: baseInfo.sendImageMimeType,
                sendImageWidth: baseInfo.sendImageWidth,
                sendImageHeight: baseInfo.sendImageHeight,
                sendImageByteCount: baseInfo.sendImageByteCount,
                sendImageDidDownscale: baseInfo.sendImageDidDownscale,
                sendImageUsedLossyCompression: baseInfo.sendImageUsedLossyCompression,
                sendImageProcessingDescription: baseInfo.sendImageProcessingDescription,
                actionableCandidatesAvailable: baseInfo.actionableCandidatesAvailable,
                readableCandidatesAvailable: baseInfo.readableCandidatesAvailable,
                actionableCandidatesSent: baseInfo.actionableCandidatesSent,
                readableCandidatesSent: baseInfo.readableCandidatesSent,
                contextCharacterCount: baseInfo.contextCharacterCount,
                failureSource: .screenshotCapture,
                responseMimeType: baseInfo.responseMimeType,
                responseSchemaModeEnabled: baseInfo.responseSchemaModeEnabled,
                requestDiagnosticsNote: baseInfo.requestDiagnosticsNote,
                maxOutputTokens: baseInfo.maxOutputTokens,
                finishReason: nil,
                finishMessage: nil,
                promptTokenCount: nil,
                outputTokenCount: nil,
                totalTokenCount: nil,
                totalElapsedTimeMilliseconds: baseInfo.totalElapsedTimeMilliseconds,
                screenshotPreparationTimeMilliseconds: baseInfo.screenshotPreparationTimeMilliseconds,
                geminiRoundTripTimeMilliseconds: baseInfo.geminiRoundTripTimeMilliseconds,
                httpStatusCode: nil,
                transportError: screenshotError.localizedDescription,
                rawResponseLength: screenshotError.localizedDescription.count,
                parserOutcome: .none,
                requestSummary: baseInfo.requestSummary,
                rawResponseText: screenshotError.localizedDescription,
                recoveredJSONText: "No recovered JSON yet."
            )
        }

        guard let geminiError = error as? GeminiScreenUnderstandingError else {
            return baseInfo
        }

        switch geminiError {
        case .missingAPIKey:
            return ScreenUnderstandingDebugInfo(
                keySource: baseInfo.keySource,
                modelName: baseInfo.modelName,
                modelSource: baseInfo.modelSource,
                invocationMode: baseInfo.invocationMode,
                userRequestPresent: baseInfo.userRequestPresent,
                autoAnalysisFired: baseInfo.autoAnalysisFired,
                idleTimeoutSeconds: baseInfo.idleTimeoutSeconds,
                focusLockActive: baseInfo.focusLockActive,
                draftTextPreserved: baseInfo.draftTextPreserved,
                autoAnalysisUsedFreshCapture: baseInfo.autoAnalysisUsedFreshCapture,
                timerRestartedDueToContextChange: baseInfo.timerRestartedDueToContextChange,
                replyLanguageMode: baseInfo.replyLanguageMode,
                preferredResponseLanguageCode: baseInfo.preferredResponseLanguageCode,
                payloadMode: baseInfo.payloadMode,
                analysisMode: baseInfo.analysisMode,
                payloadRouting: baseInfo.payloadRouting,
                complexityDiagnostics: baseInfo.complexityDiagnostics,
                screenshotCaptured: false,
                originalScreenshotMimeType: baseInfo.originalScreenshotMimeType,
                originalScreenshotWidth: baseInfo.originalScreenshotWidth,
                originalScreenshotHeight: baseInfo.originalScreenshotHeight,
                originalScreenshotByteCount: baseInfo.originalScreenshotByteCount,
                originalScreenshotProcessingDescription: baseInfo.originalScreenshotProcessingDescription,
                sendImageMimeType: baseInfo.sendImageMimeType,
                sendImageWidth: baseInfo.sendImageWidth,
                sendImageHeight: baseInfo.sendImageHeight,
                sendImageByteCount: baseInfo.sendImageByteCount,
                sendImageDidDownscale: baseInfo.sendImageDidDownscale,
                sendImageUsedLossyCompression: baseInfo.sendImageUsedLossyCompression,
                sendImageProcessingDescription: baseInfo.sendImageProcessingDescription,
                actionableCandidatesAvailable: baseInfo.actionableCandidatesAvailable,
                readableCandidatesAvailable: baseInfo.readableCandidatesAvailable,
                actionableCandidatesSent: baseInfo.actionableCandidatesSent,
                readableCandidatesSent: baseInfo.readableCandidatesSent,
                contextCharacterCount: baseInfo.contextCharacterCount,
                failureSource: .missingKey,
                responseMimeType: baseInfo.responseMimeType,
                responseSchemaModeEnabled: baseInfo.responseSchemaModeEnabled,
                requestDiagnosticsNote: baseInfo.requestDiagnosticsNote,
                maxOutputTokens: baseInfo.maxOutputTokens,
                finishReason: nil,
                finishMessage: nil,
                promptTokenCount: nil,
                outputTokenCount: nil,
                totalTokenCount: nil,
                totalElapsedTimeMilliseconds: baseInfo.totalElapsedTimeMilliseconds,
                screenshotPreparationTimeMilliseconds: baseInfo.screenshotPreparationTimeMilliseconds,
                geminiRoundTripTimeMilliseconds: baseInfo.geminiRoundTripTimeMilliseconds,
                httpStatusCode: nil,
                transportError: nil,
                rawResponseLength: 50,
                parserOutcome: .none,
                requestSummary: baseInfo.requestSummary,
                rawResponseText: "No Gemini request was sent because no API key was available.",
                recoveredJSONText: "No recovered JSON yet."
            )
        case .serviceError(_, _, let diagnostics):
            return diagnosticsWithFailureSource(diagnostics, failureSource: .networkOrAPI)
        case .invalidStructuredOutput(_, _, let diagnostics):
            return diagnosticsWithFailureSource(diagnostics, failureSource: failureSource(for: geminiError))
        case .networkFailure(_, let diagnostics):
            return diagnosticsWithFailureSource(
                diagnostics ?? baseInfo,
                failureSource: .networkOrAPI,
                transportErrorOverride: error.localizedDescription
            )
        case .requestEncodingFailed, .invalidResponse:
            return diagnosticsWithFailureSource(
                baseInfo,
                failureSource: .networkOrAPI,
                transportErrorOverride: error.localizedDescription
            )
        case .emptyResponse(let diagnostics):
            return diagnosticsWithFailureSource(
                diagnostics,
                failureSource: .networkOrAPI,
                transportErrorOverride: nil
            )
        }
    }

    private func failureSource(for error: Error) -> ScreenUnderstandingFailureSource {
        if error is WindowScreenshotError {
            return .screenshotCapture
        }

        guard let geminiError = error as? GeminiScreenUnderstandingError else {
            return .unknown
        }

        switch geminiError {
        case .missingAPIKey:
            return .missingKey
        case .invalidStructuredOutput(let kind, _, _):
            switch kind {
            case .nonJSONText:
                return .modelReturnedNonJSONText
            case .partialJSON:
                return .modelReturnedPartialJSON
            case .invalidSchemaShape:
                return .modelReturnedInvalidSchemaShape
            }
        case .networkFailure, .serviceError, .requestEncodingFailed, .invalidResponse, .emptyResponse:
            return .networkOrAPI
        }
    }

    private func diagnosticsWithFailureSource(
        _ diagnostics: ScreenUnderstandingDebugInfo,
        failureSource: ScreenUnderstandingFailureSource,
        transportErrorOverride: String? = nil
    ) -> ScreenUnderstandingDebugInfo {
        ScreenUnderstandingDebugInfo(
            keySource: diagnostics.keySource,
            modelName: diagnostics.modelName,
            modelSource: diagnostics.modelSource,
            invocationMode: diagnostics.invocationMode,
            userRequestPresent: diagnostics.userRequestPresent,
            autoAnalysisFired: diagnostics.autoAnalysisFired,
            idleTimeoutSeconds: diagnostics.idleTimeoutSeconds,
            focusLockActive: diagnostics.focusLockActive,
            draftTextPreserved: diagnostics.draftTextPreserved,
            autoAnalysisUsedFreshCapture: diagnostics.autoAnalysisUsedFreshCapture,
            timerRestartedDueToContextChange: diagnostics.timerRestartedDueToContextChange,
            replyLanguageMode: diagnostics.replyLanguageMode,
            preferredResponseLanguageCode: diagnostics.preferredResponseLanguageCode,
            payloadMode: diagnostics.payloadMode,
            analysisMode: diagnostics.analysisMode,
            payloadRouting: diagnostics.payloadRouting,
            complexityDiagnostics: diagnostics.complexityDiagnostics,
            browserCaptureAttempted: diagnostics.browserCaptureAttempted || screenUnderstandingDebugInfo.browserCaptureAttempted,
            browserName: diagnostics.browserName ?? screenUnderstandingDebugInfo.browserName,
            browserFailureCategory: diagnostics.browserFailureCategory ?? screenUnderstandingDebugInfo.browserFailureCategory,
            browserContextUsageDescription: diagnostics.browserContextUsageDescription == "Generic screenshot + AX context only" ? screenUnderstandingDebugInfo.browserContextUsageDescription : diagnostics.browserContextUsageDescription,
            browserCurrentURL: diagnostics.browserCurrentURL ?? screenUnderstandingDebugInfo.browserCurrentURL,
            browserURLRetrievalStatus: diagnostics.browserURLRetrievalStatus == "Not attempted." ? screenUnderstandingDebugInfo.browserURLRetrievalStatus : diagnostics.browserURLRetrievalStatus,
            browserPageTitle: diagnostics.browserPageTitle ?? screenUnderstandingDebugInfo.browserPageTitle,
            browserTitleRetrievalStatus: diagnostics.browserTitleRetrievalStatus == "Not attempted." ? screenUnderstandingDebugInfo.browserTitleRetrievalStatus : diagnostics.browserTitleRetrievalStatus,
            browserVisibleTextSummaryAvailable: diagnostics.browserVisibleTextSummaryAvailable || screenUnderstandingDebugInfo.browserVisibleTextSummaryAvailable,
            browserTextSummaryStatus: diagnostics.browserTextSummaryStatus == "Not attempted." ? screenUnderstandingDebugInfo.browserTextSummaryStatus : diagnostics.browserTextSummaryStatus,
            browserPrimaryEntryPointCount: max(diagnostics.browserPrimaryEntryPointCount, screenUnderstandingDebugInfo.browserPrimaryEntryPointCount),
            screenshotCaptured: diagnostics.screenshotCaptured,
            originalScreenshotMimeType: diagnostics.originalScreenshotMimeType,
            originalScreenshotWidth: diagnostics.originalScreenshotWidth,
            originalScreenshotHeight: diagnostics.originalScreenshotHeight,
            originalScreenshotByteCount: diagnostics.originalScreenshotByteCount,
            originalScreenshotProcessingDescription: diagnostics.originalScreenshotProcessingDescription,
            sendImageMimeType: diagnostics.sendImageMimeType,
            sendImageWidth: diagnostics.sendImageWidth,
            sendImageHeight: diagnostics.sendImageHeight,
            sendImageByteCount: diagnostics.sendImageByteCount,
            sendImageDidDownscale: diagnostics.sendImageDidDownscale,
            sendImageUsedLossyCompression: diagnostics.sendImageUsedLossyCompression,
            sendImageProcessingDescription: diagnostics.sendImageProcessingDescription,
            actionableCandidatesAvailable: diagnostics.actionableCandidatesAvailable,
            readableCandidatesAvailable: diagnostics.readableCandidatesAvailable,
            actionableCandidatesSent: diagnostics.actionableCandidatesSent,
            readableCandidatesSent: diagnostics.readableCandidatesSent,
            contextCharacterCount: diagnostics.contextCharacterCount,
            failureSource: failureSource,
            responseMimeType: diagnostics.responseMimeType,
            responseSchemaModeEnabled: diagnostics.responseSchemaModeEnabled,
            requestDiagnosticsNote: diagnostics.requestDiagnosticsNote,
            maxOutputTokens: diagnostics.maxOutputTokens,
            finishReason: diagnostics.finishReason,
            finishMessage: diagnostics.finishMessage,
            promptTokenCount: diagnostics.promptTokenCount,
            outputTokenCount: diagnostics.outputTokenCount,
            totalTokenCount: diagnostics.totalTokenCount,
            totalElapsedTimeMilliseconds: diagnostics.totalElapsedTimeMilliseconds,
            screenshotPreparationTimeMilliseconds: diagnostics.screenshotPreparationTimeMilliseconds,
            geminiRoundTripTimeMilliseconds: diagnostics.geminiRoundTripTimeMilliseconds,
            httpStatusCode: diagnostics.httpStatusCode,
            transportError: transportErrorOverride ?? diagnostics.transportError,
            rawResponseLength: diagnostics.rawResponseLength,
            parserOutcome: diagnostics.parserOutcome,
            requestSummary: diagnostics.requestSummary,
            rawResponseText: diagnostics.rawResponseText,
            recoveredJSONText: diagnostics.recoveredJSONText
        )
    }

    private func makeOverlayPreviewItems() -> [OverlayPreviewItem] {
        let maxOverlayItems = 3
        guard let targetWindowFrame = overlayTargetWindowFrame() else {
            return []
        }

        if selectedRecommendedTargetID != nil {
            guard let highlightedRecommendationItem = makeRecommendedOverlayPreviewItem(targetWindowFrame: targetWindowFrame) else {
                return []
            }

            return [highlightedRecommendationItem]
        }

        if guidedStepResponse != nil {
            guard let guidedStepItem = makeGuidedStepOverlayPreviewItem(targetWindowFrame: targetWindowFrame) else {
                return []
            }

            return [guidedStepItem]
        }

        return topActionableElements
            .filter { rankedElement in
                guard rankedElement.element.hasMeaningfulBounds,
                      let bounds = rankedElement.element.boundsRect,
                      bounds.width >= 24,
                      bounds.height >= 16 else {
                    return false
                }

                guard !isLikelyWindowControl(rankedElement) else {
                    return false
                }

                return validatedOverlayFrame(for: bounds, targetWindowFrame: targetWindowFrame) != nil
            }
            .prefix(maxOverlayItems)
            .enumerated()
            .compactMap { index, rankedElement in
                guard let bounds = rankedElement.element.boundsRect,
                      let validatedFrame = validatedOverlayFrame(for: bounds, targetWindowFrame: targetWindowFrame) else {
                    return nil
                }

                return OverlayPreviewItem(
                    id: rankedElement.element.id,
                    rank: index + 1,
                    label: rankedElement.element.displayName,
                    caption: overlayCaption(for: rankedElement.element),
                    frame: validatedFrame,
                    targetWindowFrame: targetWindowFrame,
                    style: .precise
                )
            }
    }

    private func makeGuidedStepOverlayPreviewItem(targetWindowFrame: CGRect) -> OverlayPreviewItem? {
        guard guidedStepResponse != nil,
              let effectiveGrounding = effectiveGuidedStepGrounding,
              let snapshot = analysisGroundingSnapshot,
              snapshot.contentRevision == targetContentRevision else {
            return nil
        }

        switch effectiveGrounding.status {
        case .axGroundedPreciseTarget, .regionLevelFallback:
            break
        case .textOnlyFallback:
            return nil
        }

        guard let candidateIdentifier = effectiveGrounding.primaryTargetLocalElementID,
              let candidate = resolveSnapshotCandidate(withIdentifier: candidateIdentifier, in: snapshot),
              let bounds = candidate.element.boundsRect,
              let validatedFrame = validatedOverlayFrame(for: bounds, targetWindowFrame: targetWindowFrame) else {
            return nil
        }

        let relayMode = effectiveGrounding.relayPresentationMode

        let overlayLabel = candidate.element.displayName
        let overlayCaption: String
        switch relayMode {
        case .preciseTargetOverlay:
            overlayCaption = truncatedCaption(overlayLabel)
        case .regionLevelGuidanceOverlay:
            overlayCaption = truncatedCaption("Start here: \(overlayLabel)")
        case .clarificationCardOnly:
            overlayCaption = truncatedCaption(overlayLabel)
        }

        let overlayFrame = relayMode == .regionLevelGuidanceOverlay
            ? expandedRegionOverlayFrame(for: validatedFrame, targetWindowFrame: targetWindowFrame)
            : validatedFrame

        return OverlayPreviewItem(
            id: candidate.element.id,
            rank: 1,
            label: overlayLabel,
            caption: overlayCaption,
            frame: overlayFrame,
            targetWindowFrame: targetWindowFrame,
            style: relayMode == .regionLevelGuidanceOverlay ? .region : .precise
        )
    }

    private func makeRecommendedOverlayPreviewItem(targetWindowFrame: CGRect) -> OverlayPreviewItem? {
        guard let result = screenUnderstandingResult,
              let selectedRecommendedTargetID,
              let selectedTarget = result.recommendedTargets.first(where: { $0.id == selectedRecommendedTargetID }),
              let resolvedTarget = resolveRecommendedTarget(for: selectedTarget),
              let validatedFrame = validatedOverlayFrame(for: resolvedTarget.bounds, targetWindowFrame: targetWindowFrame) else {
            return nil
        }

        return OverlayPreviewItem(
            id: resolvedTarget.element.id,
            rank: selectedTarget.rank,
            label: selectedTarget.label,
            caption: truncatedCaption(selectedTarget.label),
            frame: validatedFrame,
            targetWindowFrame: targetWindowFrame,
            style: .precise
        )
    }

    private func expandedRegionOverlayFrame(for frame: CGRect, targetWindowFrame: CGRect) -> CGRect {
        let expanded = frame.insetBy(dx: -18, dy: -14)
        let clipped = expanded.intersection(targetWindowFrame)
        guard clipped.width >= frame.width, clipped.height >= frame.height else {
            return frame
        }

        return clipped.integral
    }

    private func sanitizedTargetWindowFrame() -> CGRect? {
        guard let capturedExternalWindowFrame else {
            return nil
        }

        let standardized = capturedExternalWindowFrame.standardized.integral
        guard standardized.width >= 80, standardized.height >= 80 else {
            return nil
        }

        return standardized
    }

    private func overlayTargetWindowFrame() -> CGRect? {
        if let snapshot = analysisGroundingSnapshot,
           snapshot.contentRevision == targetContentRevision {
            return snapshot.targetWindowFrame
        }

        if let analysisPresentationTargetWindowFrame {
            return analysisPresentationTargetWindowFrame
        }

        return sanitizedTargetWindowFrame()
    }

    private func validatedOverlayFrame(for bounds: CGRect, targetWindowFrame: CGRect) -> CGRect? {
        let standardizedBounds = bounds.standardized
        guard standardizedBounds.width >= 24,
              standardizedBounds.height >= 16 else {
            return nil
        }

        let paddedWindowFrame = targetWindowFrame.insetBy(dx: -8, dy: -8)
        guard standardizedBounds.intersects(paddedWindowFrame) else {
            return nil
        }

        let clippedFrame = standardizedBounds.intersection(targetWindowFrame).integral
        guard clippedFrame.width >= 24,
              clippedFrame.height >= 16 else {
            return nil
        }

        let originalArea = standardizedBounds.width * standardizedBounds.height
        let clippedArea = clippedFrame.width * clippedFrame.height
        guard originalArea > 0, clippedArea / originalArea >= 0.55 else {
            return nil
        }

        return clippedFrame
    }

    private func overlayCaption(for element: AXElementNode) -> String {
        let preferredText = [element.title, element.label, element.value]
            .first(where: { candidate in
                candidate != "Unavailable" && !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })

        let caption = preferredText ?? readableRoleFallback(for: element.role)
        return truncatedCaption(caption)
    }

    private func readableRoleFallback(for role: String) -> String {
        role
            .replacingOccurrences(of: "AX", with: "")
            .replacingOccurrences(of: "PopUp", with: "Popup ")
            .replacingOccurrences(of: "RadioButton", with: "Radio Button")
            .replacingOccurrences(of: "TextField", with: "Text Field")
            .replacingOccurrences(of: "StaticText", with: "Text")
    }

    private func truncatedCaption(_ caption: String) -> String {
        let normalized = caption
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        guard normalized.count > 28 else {
            return normalized
        }

        return String(normalized.prefix(25)) + "..."
    }

    private func truncatedSemanticHint(_ text: String) -> String {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        guard normalized.count > 56 else {
            return normalized
        }

        return String(normalized.prefix(53)) + "..."
    }

    private func isLikelyWindowControl(_ rankedElement: AXRankedElement) -> Bool {
        if rankedElement.reasonTags.contains("window control down-rank") {
            return true
        }

        let hints = [
            rankedElement.element.role,
            rankedElement.element.subrole,
            rankedElement.element.title,
            rankedElement.element.label,
            rankedElement.element.value
        ]
        .joined(separator: " ")
        .lowercased()

        let blockedTerms = ["close", "minimize", "zoom", "fullscreen", "toolbar button"]
        return blockedTerms.contains { hints.contains($0) }
    }

    private func isControlRole(_ role: String) -> Bool {
        let normalizedRole = role.lowercased()
        return normalizedRole.contains("button")
            || normalizedRole.contains("textfield")
            || normalizedRole.contains("checkbox")
            || normalizedRole.contains("radio")
            || normalizedRole.contains("link")
            || normalizedRole.contains("popup")
            || normalizedRole.contains("menuitem")
            || normalizedRole.contains("tab")
            || normalizedRole.contains("slider")
            || normalizedRole.contains("stepper")
    }
}
