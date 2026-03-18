import Foundation

struct BackendScreenUnderstandingResponse {
    let result: ScreenUnderstandingResult
    let guidePlan: GuidePlanViewModel
    let rawResponseText: String
    let statusCode: Int?
    let sourceMode: BackendDataSourceMode
}

struct BackendScreenUnderstandingService {
    private let client: BackendClient
    private let mapper: GuidePlanMapper
    private let windowScreenshotService: WindowScreenshotService

    init(
        client: BackendClient = BackendClient(),
        mapper: GuidePlanMapper = GuidePlanMapper(),
        windowScreenshotService: WindowScreenshotService = WindowScreenshotService()
    ) {
        self.client = client
        self.mapper = mapper
        self.windowScreenshotService = windowScreenshotService
    }

    func health(mode: BackendDataSourceMode) async throws -> BackendHTTPResponse<BackendHealthResponse> {
        try await client.health(mode: mode)
    }

    func analyzeScreen(
        screenshot: WindowScreenshot,
        context: ScreenUnderstandingContext,
        sessionID: String,
        mode: BackendDataSourceMode
    ) async throws -> BackendScreenUnderstandingResponse {
        let backendUploadImage = try await windowScreenshotService.prepareBackendUploadImage(from: screenshot)
        let request = AnalyzeScreenRequest(
            sessionID: sessionID,
            userGoal: context.userRequest?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Help me continue safely",
            appName: context.appName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Unknown App",
            windowTitle: context.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled Window",
            screenshotBase64: backendUploadImage.data.base64EncodedString(),
            actionableCandidates: context.topActionableElements.map(backendCandidate(from:)),
            readableCandidates: context.topReadableElements.map(backendCandidate(from:))
        )

        logAnalyzeRequest(request, mode: mode, uploadImage: backendUploadImage)

        let response = try await client.analyzeScreen(request: request, mode: mode)
        logAnalyzeResponse(response.value, rawBody: response.rawBody, mode: mode)
        let mapped = mapper.map(response.value)
        logGuideCardSource(response: response.value, mapped: mapped.guidePlan, mode: mode)
        return BackendScreenUnderstandingResponse(
            result: mapped.screenUnderstandingResult,
            guidePlan: mapped.guidePlan,
            rawResponseText: response.rawBody,
            statusCode: response.statusCode,
            sourceMode: mode
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension BackendScreenUnderstandingService {
    func logAnalyzeRequest(
        _ request: AnalyzeScreenRequest,
        mode: BackendDataSourceMode,
        uploadImage: BackendUploadImage
    ) {
        let screenshotLength = request.screenshotBase64.count
        let screenshotState = screenshotLength > 0 ? "non-empty" : "empty"
        let userGoalWarning = request.userGoal.count < 8 ? " [WARN: user_goal is very short]" : ""
        let appNameWarning = request.appName == "Unknown App" ? " [WARN: app_name missing/fallback]" : ""
        let windowTitleWarning = request.windowTitle == "Untitled Window" ? " [WARN: window_title missing/fallback]" : ""
        let screenshotWarning: String
        if screenshotLength == 0 {
            screenshotWarning = " [WARN: screenshot_base64 empty]"
        } else if screenshotLength <= 16 {
            screenshotWarning = " [WARN: screenshot_base64 is unusually short / may be dummy]"
        } else {
            screenshotWarning = ""
        }

        print(
            """
            [BackendDiag][Request][\(mode.rawValue)]
            session_id: \(request.sessionID)
            user_goal: \(request.userGoal)\(userGoalWarning)
            app_name: \(request.appName)\(appNameWarning)
            window_title: \(request.windowTitle)\(windowTitleWarning)
            screenshot_base64: \(screenshotState), length=\(screenshotLength)\(screenshotWarning)
            screenshot_upload_mime_type: \(uploadImage.mimeType)
            screenshot_upload_size: \(uploadImage.pixelWidth)x\(uploadImage.pixelHeight)
            screenshot_upload_bytes: \(uploadImage.byteCount)
            screenshot_upload_downscaled: \(uploadImage.didDownscale ? "yes" : "no")
            screenshot_upload_processing: \(uploadImage.processingDescription)
            actionable_candidates_sent: \(request.actionableCandidates.count)
            readable_candidates_sent: \(request.readableCandidates.count)
            payload_consistency_note: Request shape is identical across local_sample / local_backend / cloud_backend. Only the data source changes.
            """
        )
    }

    func logAnalyzeResponse(_ response: AnalyzeScreenResponse, rawBody: String, mode: BackendDataSourceMode) {
        print(
            """
            [BackendDiag][Response][\(mode.rawValue)] RAW JSON
            \(rawBody)
            [BackendDiag][Response][\(mode.rawValue)] Parsed fields
            context: \(response.context)
            likely_task: \(response.likelyTask)
            safe_first_step: \(response.safeFirstStep)
            confirmation_question: \(response.confirmationQuestion)
            action_plan: \(String(describing: response.actionPlan.map { ["type": $0.type, "target": $0.target ?? "", "text": $0.text ?? "", "requires_confirmation": String($0.requiresConfirmation), "value": $0.value ?? "", "related_local_element": $0.relatedLocalElement ?? "", "visual_bounding_box": $0.visualBoundingBox ?? []] }))
            guide_card: \(String(describing: response.guideCard))
            target_info: \(String(describing: response.targetInfo))
            meta: \(String(describing: response.meta))
            """
        )
    }

    func backendCandidate(from candidate: ScreenUnderstandingCandidate) -> BackendAnalysisCandidate {
        BackendAnalysisCandidate(
            id: candidate.id,
            rank: candidate.rank,
            label: candidate.label,
            semanticHint: candidate.semanticHint,
            role: candidate.role,
            subrole: candidate.subrole,
            bounds: candidate.bounds,
            score: candidate.score,
            signals: candidate.signals
        )
    }

    func logGuideCardSource(response: AnalyzeScreenResponse, mapped: GuidePlanViewModel, mode: BackendDataSourceMode) {
        let source: String
        if response.guideCard?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || response.guideCard?.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || response.guideCard?.primaryAction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            source = "guide_card"
        } else if !response.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !response.likelyTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !response.safeFirstStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            source = "legacy_fields"
        } else {
            source = "local_fallback"
        }

        print(
            """
            [BackendDiag][CardSource][\(mode.rawValue)]
            source: \(source)
            title: \(mapped.title)
            body: \(mapped.body)
            primary_action_text: \(mapped.primaryActionText)
            """
        )
    }
}
