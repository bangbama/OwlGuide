import Foundation

enum GeminiStructuredOutputFailureKind {
    case nonJSONText
    case partialJSON
    case invalidSchemaShape
}

enum GeminiScreenUnderstandingError: LocalizedError {
    case missingAPIKey
    case requestEncodingFailed
    case invalidResponse
    case networkFailure(String, diagnostics: ScreenUnderstandingDebugInfo?)
    case serviceError(message: String, responsePreview: String, diagnostics: ScreenUnderstandingDebugInfo)
    case emptyResponse(diagnostics: ScreenUnderstandingDebugInfo)
    case invalidStructuredOutput(
        kind: GeminiStructuredOutputFailureKind,
        message: String,
        diagnostics: ScreenUnderstandingDebugInfo
    )

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add a Gemini API key in Owl Guide before analyzing the current screen."
        case .requestEncodingFailed:
            return "The Gemini request payload could not be encoded."
        case .invalidResponse:
            return "Gemini returned an unexpected response format."
        case .networkFailure(let message, _):
            return message
        case .serviceError(let message, _, _):
            return message
        case .emptyResponse:
            return "Gemini returned no analysis text."
        case .invalidStructuredOutput(_, let message, _):
            return message
        }
    }
}

struct GeminiScreenUnderstandingResponse {
    let result: ScreenUnderstandingResult
    let keySource: GeminiAPIKeySource
    let diagnostics: ScreenUnderstandingDebugInfo
}

struct GeminiScreenUnderstandingService {
    static let previewModel = "gemini-3.1-pro-preview"
    static let builtInDefaultModel = GeminiScreenUnderstandingService.previewModel
    static let responseMimeType = "application/json"
    static let responseSchemaModeEnabled = true
    static let maxOutputTokens = 1024
    static let requestDiagnosticsNote = AnalysisPromptKnowledge.requestDiagnosticsNote
    static let owlGuideSystemInstruction = AnalysisPromptKnowledge.owlGuideSystemInstruction

    private let session: URLSession
    private let keyStore: GeminiAPIKeyStore
    private let modelSelectionStore: GeminiModelSelectionStore
    private let defaultModelName: String

    init(
        session: URLSession = .shared,
        keyStore: GeminiAPIKeyStore = GeminiAPIKeyStore(),
        defaultModelName: String = GeminiScreenUnderstandingService.builtInDefaultModel
    ) {
        self.session = session
        self.keyStore = keyStore
        self.modelSelectionStore = GeminiModelSelectionStore()
        self.defaultModelName = defaultModelName
        // The MVP Gemini path is fixed to gemini-3.1-pro-preview.
        // Clear any older saved model override so it cannot surface as the active model.
        try? self.modelSelectionStore.clear()
    }

    func analyzeScreen(
        originalScreenshot: WindowScreenshot,
        sendImage: GeminiSendImage,
        context: ScreenUnderstandingContext,
        invocationMode: OwlInvocationMode,
        userRequestPresent: Bool,
        autoAnalysisFired: Bool,
        idleTimeoutSeconds: Int,
        focusLockActive: Bool,
        draftTextPreserved: Bool,
        autoAnalysisUsedFreshCapture: Bool,
        timerRestartedDueToContextChange: Bool,
        replyLanguageMode: OwlReplyLanguageMode,
        preferredResponseLanguageCode: String?,
        payloadMode: ScreenUnderstandingPayloadMode,
        analysisMode: ScreenUnderstandingAnalysisMode,
        complexityDiagnostics: ScreenUnderstandingComplexityDiagnostics
    ) async throws -> GeminiScreenUnderstandingResponse {
        let resolvedKey = try currentAPIKey()
        let modelConfiguration = currentModelConfiguration()
        let contextJSON = try encodedContextJSON(context)
        let baseRequestSummary = makeRequestSummary(
            modelConfiguration: modelConfiguration,
            invocationMode: invocationMode,
            userRequestPresent: userRequestPresent,
            autoAnalysisFired: autoAnalysisFired,
            idleTimeoutSeconds: idleTimeoutSeconds,
            focusLockActive: focusLockActive,
            draftTextPreserved: draftTextPreserved,
            autoAnalysisUsedFreshCapture: autoAnalysisUsedFreshCapture,
            timerRestartedDueToContextChange: timerRestartedDueToContextChange,
            replyLanguageMode: replyLanguageMode,
            preferredResponseLanguageCode: preferredResponseLanguageCode,
            context: context,
            payloadMode: payloadMode,
            analysisMode: analysisMode,
            complexityDiagnostics: complexityDiagnostics,
            originalScreenshot: originalScreenshot,
            sendImage: sendImage,
            contextCharacterCount: contextJSON.count
        )
        let requestBody = try makeRequestBody(
            sendImage: sendImage,
            context: context,
            contextJSON: contextJSON,
            analysisMode: analysisMode
        )

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelConfiguration.name):generateContent") else {
            throw GeminiScreenUnderstandingError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(resolvedKey.value, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = requestBody

        let executeAttempt: (_ attemptNumber: Int, _ totalAttempts: Int) async throws -> GeminiScreenUnderstandingResponse = { attemptNumber, totalAttempts in
            let requestSummary = self.requestSummaryWithAttempt(
                baseRequestSummary,
                attemptNumber: attemptNumber,
                totalAttempts: totalAttempts
            )
            let requestDiagnosticsNote = self.requestDiagnosticsNoteWithAttempt(
                attemptNumber: attemptNumber,
                totalAttempts: totalAttempts
            )
            let requestDiagnostics = makeDiagnostics(
                keySource: resolvedKey.source,
                modelConfiguration: modelConfiguration,
                invocationMode: invocationMode,
                userRequestPresent: userRequestPresent,
                autoAnalysisFired: autoAnalysisFired,
                idleTimeoutSeconds: idleTimeoutSeconds,
                focusLockActive: focusLockActive,
                draftTextPreserved: draftTextPreserved,
                autoAnalysisUsedFreshCapture: autoAnalysisUsedFreshCapture,
                timerRestartedDueToContextChange: timerRestartedDueToContextChange,
                replyLanguageMode: replyLanguageMode,
                preferredResponseLanguageCode: preferredResponseLanguageCode,
                payloadMode: payloadMode,
                analysisMode: analysisMode,
                complexityDiagnostics: complexityDiagnostics,
                browserCaptureAttempted: context.browserContext != nil,
                browserName: context.browserContext?.browserName,
                browserContextUsageDescription: context.browserContext != nil ? "Browser-aware context + generic grounding" : "Generic screenshot + AX context only",
                browserCurrentURL: context.browserContext?.currentURL,
                browserURLRetrievalStatus: context.browserContext?.currentURL != nil ? "Retrieved" : "Unavailable",
                browserPageTitle: context.browserContext?.pageTitle,
                browserTitleRetrievalStatus: context.browserContext?.pageTitle != nil ? "Retrieved" : "Unavailable",
                browserVisibleTextSummaryAvailable: context.browserContext?.visibleTextSummary != nil,
                browserTextSummaryStatus: context.browserContext?.visibleTextSummary != nil ? "Retrieved" : "Unavailable",
                browserPrimaryEntryPointCount: context.browserContext?.primaryEntryPoints.count ?? 0,
                actionableCandidatesAvailable: context.actionableCandidatesAvailable,
                readableCandidatesAvailable: context.readableCandidatesAvailable,
                actionableCandidatesSent: context.topActionableElements.count,
                readableCandidatesSent: context.topReadableElements.count,
                contextCharacterCount: contextJSON.count,
                screenshotCaptured: false,
                originalScreenshotMimeType: originalScreenshot.mimeType,
                originalScreenshotWidth: originalScreenshot.pixelWidth,
                originalScreenshotHeight: originalScreenshot.pixelHeight,
                originalScreenshotByteCount: originalScreenshot.byteCount,
                originalScreenshotProcessingDescription: originalScreenshot.processingDescription,
                sendImageMimeType: sendImage.mimeType,
                sendImageWidth: sendImage.pixelWidth,
                sendImageHeight: sendImage.pixelHeight,
                sendImageByteCount: sendImage.byteCount,
                sendImageDidDownscale: sendImage.didDownscale,
                sendImageUsedLossyCompression: sendImage.usedLossyCompression,
                sendImageProcessingDescription: sendImage.processingDescription,
                httpStatusCode: nil,
                transportError: nil,
                finishReason: nil,
                finishMessage: nil,
                promptTokenCount: nil,
                outputTokenCount: nil,
                totalTokenCount: nil,
                totalElapsedTimeMilliseconds: nil,
                screenshotPreparationTimeMilliseconds: nil,
                geminiRoundTripTimeMilliseconds: nil,
                parserOutcome: .none,
                requestSummary: requestSummary,
                requestDiagnosticsNoteOverride: requestDiagnosticsNote,
                rawResponseText: "No Gemini response yet.",
                recoveredJSONText: "No recovered JSON yet."
            )

            let data: Data
            let response: URLResponse

            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw GeminiScreenUnderstandingError.networkFailure(
                    "Owl Guide could not reach Gemini. Check your network connection and try again.",
                    diagnostics: diagnosticsWithParserOutcome(
                        requestDiagnostics,
                        parserOutcome: .none,
                        rawResponseText: error.localizedDescription,
                        recoveredJSONText: "No recovered JSON yet."
                    )
                )
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiScreenUnderstandingError.invalidResponse
            }

            let responseBodyText = String(data: data, encoding: .utf8) ?? "No response body."
            let baseDiagnostics = makeDiagnostics(
            keySource: resolvedKey.source,
            modelConfiguration: modelConfiguration,
            invocationMode: invocationMode,
            userRequestPresent: userRequestPresent,
            autoAnalysisFired: autoAnalysisFired,
            idleTimeoutSeconds: idleTimeoutSeconds,
            focusLockActive: focusLockActive,
            draftTextPreserved: draftTextPreserved,
            autoAnalysisUsedFreshCapture: autoAnalysisUsedFreshCapture,
            timerRestartedDueToContextChange: timerRestartedDueToContextChange,
            replyLanguageMode: replyLanguageMode,
            preferredResponseLanguageCode: preferredResponseLanguageCode,
            payloadMode: payloadMode,
            analysisMode: analysisMode,
            complexityDiagnostics: complexityDiagnostics,
            browserCaptureAttempted: context.browserContext != nil,
            browserName: context.browserContext?.browserName,
            browserContextUsageDescription: context.browserContext != nil ? "Browser-aware context + generic grounding" : "Generic screenshot + AX context only",
            browserCurrentURL: context.browserContext?.currentURL,
            browserURLRetrievalStatus: context.browserContext?.currentURL != nil ? "Retrieved" : "Unavailable",
            browserPageTitle: context.browserContext?.pageTitle,
            browserTitleRetrievalStatus: context.browserContext?.pageTitle != nil ? "Retrieved" : "Unavailable",
            browserVisibleTextSummaryAvailable: context.browserContext?.visibleTextSummary != nil,
            browserTextSummaryStatus: context.browserContext?.visibleTextSummary != nil ? "Retrieved" : "Unavailable",
            browserPrimaryEntryPointCount: context.browserContext?.primaryEntryPoints.count ?? 0,
            actionableCandidatesAvailable: context.actionableCandidatesAvailable,
            readableCandidatesAvailable: context.readableCandidatesAvailable,
            actionableCandidatesSent: context.topActionableElements.count,
            readableCandidatesSent: context.topReadableElements.count,
            contextCharacterCount: contextJSON.count,
            screenshotCaptured: true,
            originalScreenshotMimeType: originalScreenshot.mimeType,
            originalScreenshotWidth: originalScreenshot.pixelWidth,
            originalScreenshotHeight: originalScreenshot.pixelHeight,
            originalScreenshotByteCount: originalScreenshot.byteCount,
            originalScreenshotProcessingDescription: originalScreenshot.processingDescription,
            sendImageMimeType: sendImage.mimeType,
            sendImageWidth: sendImage.pixelWidth,
            sendImageHeight: sendImage.pixelHeight,
            sendImageByteCount: sendImage.byteCount,
            sendImageDidDownscale: sendImage.didDownscale,
            sendImageUsedLossyCompression: sendImage.usedLossyCompression,
            sendImageProcessingDescription: sendImage.processingDescription,
            httpStatusCode: httpResponse.statusCode,
            transportError: nil,
            finishReason: nil,
            finishMessage: nil,
            promptTokenCount: nil,
            outputTokenCount: nil,
            totalTokenCount: nil,
            totalElapsedTimeMilliseconds: nil,
            screenshotPreparationTimeMilliseconds: nil,
            geminiRoundTripTimeMilliseconds: nil,
            parserOutcome: .none,
            requestSummary: requestSummary,
            requestDiagnosticsNoteOverride: requestDiagnosticsNote,
            rawResponseText: responseBodyText,
            recoveredJSONText: "No recovered JSON yet."
        )

            if !(200...299).contains(httpResponse.statusCode) {
                let message = decodeServiceError(from: data) ?? "Gemini request failed with HTTP \(httpResponse.statusCode)."
                throw GeminiScreenUnderstandingError.serviceError(
                    message: message,
                    responsePreview: makePreview(from: data),
                    diagnostics: baseDiagnostics
                )
            }

            let envelope = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
            guard let rawText = envelope.candidates?
            .first?
            .content?
            .parts?
            .compactMap(\.text)
            .joined(),
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GeminiScreenUnderstandingError.emptyResponse(diagnostics: baseDiagnostics)
            }

            let finishReason = envelope.candidates?.first?.finishReason
            let finishMessage = envelope.candidates?.first?.finishMessage
            let promptTokenCount = envelope.usageMetadata?.promptTokenCount
            let outputTokenCount = envelope.usageMetadata?.candidatesTokenCount
            let totalTokenCount = envelope.usageMetadata?.totalTokenCount
            let responseDiagnostics = makeDiagnostics(
            keySource: resolvedKey.source,
            modelConfiguration: modelConfiguration,
            invocationMode: invocationMode,
            userRequestPresent: userRequestPresent,
            autoAnalysisFired: autoAnalysisFired,
            idleTimeoutSeconds: idleTimeoutSeconds,
            focusLockActive: focusLockActive,
            draftTextPreserved: draftTextPreserved,
            autoAnalysisUsedFreshCapture: autoAnalysisUsedFreshCapture,
            timerRestartedDueToContextChange: timerRestartedDueToContextChange,
            replyLanguageMode: replyLanguageMode,
            preferredResponseLanguageCode: preferredResponseLanguageCode,
            payloadMode: payloadMode,
            analysisMode: analysisMode,
            complexityDiagnostics: complexityDiagnostics,
            browserCaptureAttempted: context.browserContext != nil,
            browserName: context.browserContext?.browserName,
            browserContextUsageDescription: context.browserContext != nil ? "Browser-aware context + generic grounding" : "Generic screenshot + AX context only",
            browserCurrentURL: context.browserContext?.currentURL,
            browserURLRetrievalStatus: context.browserContext?.currentURL != nil ? "Retrieved" : "Unavailable",
            browserPageTitle: context.browserContext?.pageTitle,
            browserTitleRetrievalStatus: context.browserContext?.pageTitle != nil ? "Retrieved" : "Unavailable",
            browserVisibleTextSummaryAvailable: context.browserContext?.visibleTextSummary != nil,
            browserTextSummaryStatus: context.browserContext?.visibleTextSummary != nil ? "Retrieved" : "Unavailable",
            browserPrimaryEntryPointCount: context.browserContext?.primaryEntryPoints.count ?? 0,
            actionableCandidatesAvailable: context.actionableCandidatesAvailable,
            readableCandidatesAvailable: context.readableCandidatesAvailable,
            actionableCandidatesSent: context.topActionableElements.count,
            readableCandidatesSent: context.topReadableElements.count,
            contextCharacterCount: contextJSON.count,
            screenshotCaptured: true,
            originalScreenshotMimeType: originalScreenshot.mimeType,
            originalScreenshotWidth: originalScreenshot.pixelWidth,
            originalScreenshotHeight: originalScreenshot.pixelHeight,
            originalScreenshotByteCount: originalScreenshot.byteCount,
            originalScreenshotProcessingDescription: originalScreenshot.processingDescription,
            sendImageMimeType: sendImage.mimeType,
            sendImageWidth: sendImage.pixelWidth,
            sendImageHeight: sendImage.pixelHeight,
            sendImageByteCount: sendImage.byteCount,
            sendImageDidDownscale: sendImage.didDownscale,
            sendImageUsedLossyCompression: sendImage.usedLossyCompression,
            sendImageProcessingDescription: sendImage.processingDescription,
            httpStatusCode: httpResponse.statusCode,
            transportError: nil,
            finishReason: finishReason,
            finishMessage: finishMessage,
            promptTokenCount: promptTokenCount,
            outputTokenCount: outputTokenCount,
            totalTokenCount: totalTokenCount,
            totalElapsedTimeMilliseconds: nil,
            screenshotPreparationTimeMilliseconds: nil,
            geminiRoundTripTimeMilliseconds: nil,
            parserOutcome: .none,
            requestSummary: requestSummary,
            requestDiagnosticsNoteOverride: requestDiagnosticsNote,
            rawResponseText: rawText,
            recoveredJSONText: "No recovered JSON yet."
        )

            let recoveredJSON = try recoverStructuredJSON(from: rawText, diagnostics: responseDiagnostics)
            let result = try decodeStructuredResult(from: recoveredJSON, rawText: rawText, diagnostics: responseDiagnostics)

            return GeminiScreenUnderstandingResponse(
                result: result,
                keySource: resolvedKey.source,
                diagnostics: makeDiagnostics(
                keySource: resolvedKey.source,
                modelConfiguration: modelConfiguration,
                invocationMode: invocationMode,
                userRequestPresent: userRequestPresent,
                autoAnalysisFired: autoAnalysisFired,
                idleTimeoutSeconds: idleTimeoutSeconds,
                focusLockActive: focusLockActive,
                draftTextPreserved: draftTextPreserved,
                autoAnalysisUsedFreshCapture: autoAnalysisUsedFreshCapture,
                timerRestartedDueToContextChange: timerRestartedDueToContextChange,
                replyLanguageMode: replyLanguageMode,
                preferredResponseLanguageCode: preferredResponseLanguageCode,
                payloadMode: payloadMode,
                analysisMode: analysisMode,
                complexityDiagnostics: complexityDiagnostics,
                browserCaptureAttempted: context.browserContext != nil,
                browserName: context.browserContext?.browserName,
                browserContextUsageDescription: context.browserContext != nil ? "Browser-aware context + generic grounding" : "Generic screenshot + AX context only",
                browserCurrentURL: context.browserContext?.currentURL,
                browserURLRetrievalStatus: context.browserContext?.currentURL != nil ? "Retrieved" : "Unavailable",
                browserPageTitle: context.browserContext?.pageTitle,
                browserTitleRetrievalStatus: context.browserContext?.pageTitle != nil ? "Retrieved" : "Unavailable",
                browserVisibleTextSummaryAvailable: context.browserContext?.visibleTextSummary != nil,
                browserTextSummaryStatus: context.browserContext?.visibleTextSummary != nil ? "Retrieved" : "Unavailable",
                browserPrimaryEntryPointCount: context.browserContext?.primaryEntryPoints.count ?? 0,
                actionableCandidatesAvailable: context.actionableCandidatesAvailable,
                readableCandidatesAvailable: context.readableCandidatesAvailable,
                actionableCandidatesSent: context.topActionableElements.count,
                readableCandidatesSent: context.topReadableElements.count,
                contextCharacterCount: contextJSON.count,
                screenshotCaptured: true,
                originalScreenshotMimeType: originalScreenshot.mimeType,
                originalScreenshotWidth: originalScreenshot.pixelWidth,
                originalScreenshotHeight: originalScreenshot.pixelHeight,
                originalScreenshotByteCount: originalScreenshot.byteCount,
                originalScreenshotProcessingDescription: originalScreenshot.processingDescription,
                sendImageMimeType: sendImage.mimeType,
                sendImageWidth: sendImage.pixelWidth,
                sendImageHeight: sendImage.pixelHeight,
                sendImageByteCount: sendImage.byteCount,
                sendImageDidDownscale: sendImage.didDownscale,
                sendImageUsedLossyCompression: sendImage.usedLossyCompression,
                sendImageProcessingDescription: sendImage.processingDescription,
                httpStatusCode: httpResponse.statusCode,
                transportError: nil,
                finishReason: finishReason,
                finishMessage: finishMessage,
                promptTokenCount: promptTokenCount,
                outputTokenCount: outputTokenCount,
                totalTokenCount: totalTokenCount,
                totalElapsedTimeMilliseconds: nil,
                screenshotPreparationTimeMilliseconds: nil,
                geminiRoundTripTimeMilliseconds: nil,
                parserOutcome: .fullJSON,
                requestSummary: requestSummary,
                requestDiagnosticsNoteOverride: requestDiagnosticsNote,
                rawResponseText: rawText,
                recoveredJSONText: recoveredJSON
                )
            )
        }

        do {
            return try await executeAttempt(1, 2)
        } catch {
            guard shouldRetryAfterTruncation(error) else {
                throw error
            }

            return try await executeAttempt(2, 2)
        }
    }

    func hasAPIKey() -> Bool {
        (try? currentAPIKey()) != nil
    }

    func currentKeySource() -> GeminiAPIKeySource {
        (try? currentAPIKey().source) ?? .none
    }

    func hasUserProvidedAPIKey() -> Bool {
        keyStore.containsKey()
    }

    func currentModelConfiguration() -> GeminiModelConfiguration {
        return GeminiModelConfiguration(name: defaultModelName, source: .builtInDefault)
    }

    func hasSavedModelSelection() -> Bool {
        modelSelectionStore.containsValue()
    }

    func saveUserSelectedModel(_ modelName: String) throws {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GeminiScreenUnderstandingError.invalidResponse
        }

        try modelSelectionStore.save(trimmed)
    }

    func clearUserSelectedModel() throws {
        try modelSelectionStore.clear()
    }

    func saveUserProvidedAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GeminiScreenUnderstandingError.missingAPIKey
        }

        try keyStore.save(trimmed)
    }

    func clearUserProvidedAPIKey() throws {
        try keyStore.clear()
    }

    private func currentAPIKey() throws -> ResolvedAPIKey {
        let environmentValue = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentValue, !environmentValue.isEmpty {
            return ResolvedAPIKey(value: environmentValue, source: .environment)
        }

        if let storedValue = keyStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !storedValue.isEmpty {
            return ResolvedAPIKey(value: storedValue, source: .keychain)
        }

        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String {
            let trimmed = bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return ResolvedAPIKey(value: trimmed, source: .infoPlist)
            }
        }

        throw GeminiScreenUnderstandingError.missingAPIKey
    }

    private func encodedContextJSON(_ context: ScreenUnderstandingContext) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(context)
        return String(decoding: data, as: UTF8.self)
    }

    private func makeRequestBody(
        sendImage: GeminiSendImage,
        context: ScreenUnderstandingContext,
        contextJSON: String,
        analysisMode: ScreenUnderstandingAnalysisMode
    ) throws -> Data {
        let maxRecommendationCount = 1
        let promptModeNote = AnalysisPromptKnowledge.promptModeNote(for: analysisMode)

        let prompt = """
        Analyze this macOS screen for read-only understanding.
        Work in two internal stages:
        Stage A: infer pageSummary and likelyUserGoal from the screenshot first.
        Stage B: choose up to \(maxRecommendationCount) recommendedTargets using screenshot evidence first, then the local candidate context for grounding and linking.

        \(AnalysisPromptKnowledge.sharedAnalysisRules)
        - \(promptModeNote.replacingOccurrences(of: "\n", with: " "))

        Compact local candidate context:
        \(contextJSON)
        """

        let directUserQuestion = context.userRequest?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // The current REST generateContent path supports structured output via
        // generationConfig.responseMimeType and generationConfig.responseJsonSchema.
        // Use the JSON-schema path directly so the wire contract matches the result model.
        var userParts: [[String: Any]] = []
        if let directUserQuestion, !directUserQuestion.isEmpty {
            userParts.append([
                "text": """
                DIRECT USER QUESTION. Answer this first and keep the reply aligned to it:
                \(directUserQuestion)
                """
            ])
        }
        userParts.append(["text": prompt])
        userParts.append(
            [
                "inlineData": [
                    "mimeType": sendImage.mimeType,
                    "data": sendImage.data.base64EncodedString()
                ]
            ]
        )

        let requestObject: [String: Any] = [
            "systemInstruction": [
                "parts": [
                    [
                        "text": Self.owlGuideSystemInstruction
                    ]
                ]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": userParts
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "candidateCount": 1,
                "maxOutputTokens": Self.maxOutputTokens,
                "responseMimeType": Self.responseMimeType,
                "responseJsonSchema": responseJSONSchema(for: analysisMode)
            ]
        ]

        guard JSONSerialization.isValidJSONObject(requestObject) else {
            throw GeminiScreenUnderstandingError.requestEncodingFailed
        }

        return try JSONSerialization.data(withJSONObject: requestObject)
    }

    private func responseJSONSchema(for analysisMode: ScreenUnderstandingAnalysisMode) -> [String: Any] {
        let maxRecommendationCount = 1
        let pageSummaryMaxLength = analysisMode == .simplifiedHighComplexity ? 70 : 90
        let likelyTaskMaxLength = analysisMode == .simplifiedHighComplexity ? 55 : 70
        let targetLabelMaxLength = analysisMode == .simplifiedHighComplexity ? 40 : 50
        let whyThisMattersMaxLength = analysisMode == .simplifiedHighComplexity ? 60 : 70
        let cautionNotesMaxItems = 1
        let cautionNoteMaxLength = analysisMode == .simplifiedHighComplexity ? 60 : 70

        return [
            "type": "object",
            "required": ["pageSummary", "likelyUserGoal", "recommendedTargets", "cautionNotes"],
            "additionalProperties": false,
            "properties": [
                "pageSummary": [
                    "type": "string",
                    "maxLength": pageSummaryMaxLength
                ],
                "likelyUserGoal": [
                    "type": "string",
                    "maxLength": likelyTaskMaxLength
                ],
                "recommendedTargets": [
                    "type": "array",
                    "maxItems": maxRecommendationCount,
                    "items": [
                        "type": "object",
                        "required": ["rank", "label", "whyThisMatters", "relatedLocalElement", "intendedAction", "visualBoundingBox"],
                        "additionalProperties": false,
                        "properties": [
                            "rank": [
                                "type": "integer"
                            ],
                            "label": [
                                "type": "string",
                                "maxLength": targetLabelMaxLength
                            ],
                            "whyThisMatters": [
                                "type": "string",
                                "maxLength": whyThisMattersMaxLength
                            ],
                            "intendedAction": [
                                "type": "string",
                                "enum": ["click", "type", "none"],
                                "description": "The type of action the user should perform on this element."
                            ],
                            "actionValue": [
                                "type": "string",
                                "maxLength": 100,
                                "description": "If intendedAction is 'type', the exact text the user needs to input here. Omit or leave empty if action is 'click' or 'none'."
                            ],
                            "relatedLocalElement": [
                                "type": "string",
                                "maxLength": 160
                            ],
                            "visualBoundingBox": [
                                "type": "array",
                                "description": "Normalized bounding box [y_min, x_min, y_max, x_max] where each value is 0-1000. 0=top/left edge, 1000=bottom/right edge of the screenshot.",
                                "items": [
                                    "type": "integer"
                                ],
                                "minItems": 4,
                                "maxItems": 4
                            ]
                        ]
                    ]
                ],
                "cautionNotes": [
                    "type": "array",
                    "maxItems": cautionNotesMaxItems,
                    "items": [
                        "type": "string",
                        "maxLength": cautionNoteMaxLength
                    ]
                ]
            ]
        ]
    }

    private func decodeServiceError(from data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data) else {
            return nil
        }

        return payload.error.message
    }

    private func recoverStructuredJSON(from rawText: String, diagnostics: ScreenUnderstandingDebugInfo) throws -> String {
        let attempts = candidateJSONPayloads(from: rawText)

        for attempt in attempts {
            for candidate in normalizedJSONCandidates(for: unwrapJSONStringPayloadIfNeeded(attempt)) {
                guard let data = candidate.data(using: .utf8) else {
                    continue
                }

                if let parsed = try? JSONSerialization.jsonObject(with: data),
                   parsed is [String: Any] {
                    return candidate
                }
            }
        }

        let failureKind = classifyStructuredOutputFailure(from: rawText, attempts: attempts)
        throw GeminiScreenUnderstandingError.invalidStructuredOutput(
            kind: failureKind,
            message: structuredOutputFailureMessage(for: failureKind),
            diagnostics: diagnosticsWithParserOutcome(
                diagnostics,
                parserOutcome: parserOutcome(for: failureKind),
                rawResponseText: rawText,
                recoveredJSONText: attempts.dropFirst().joined(separator: "\n\n")
            )
        )
    }

    private func candidateJSONPayloads(from rawText: String) -> [String] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = [trimmed]

        let fencedBlocks = fencedBlockPayloads(in: trimmed)
        candidates.append(contentsOf: fencedBlocks)

        if let extracted = firstJSONObject(in: trimmed) {
            candidates.append(extracted)
        }

        for fencedBlock in fencedBlocks {
            if let extracted = firstJSONObject(in: fencedBlock) {
                candidates.append(extracted)
            }
        }

        var seen = Set<String>()
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func fencedBlockPayloads(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "```(?:json)?\\s*([\\s\\S]*?)```", options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let blockRange = Range(match.range(at: 1), in: text) else {
                return nil
            }

            return String(text[blockRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func firstJSONObject(in text: String) -> String? {
        var startIndex: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                    continue
                }

                if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }

                continue
            }

            if character == "\"" {
                isInsideString = true
                continue
            }

            if character == "{" {
                if startIndex == nil {
                    startIndex = index
                }
                depth += 1
            } else if character == "}" {
                guard depth > 0 else {
                    continue
                }

                depth -= 1
                if depth == 0, let startIndex {
                    let endIndex = text.index(after: index)
                    return String(text[startIndex..<endIndex])
                }
            }
        }

        return nil
    }

    private func decodeStructuredResult(
        from jsonText: String,
        rawText: String,
        diagnostics: ScreenUnderstandingDebugInfo
    ) throws -> ScreenUnderstandingResult {
        guard let data = jsonText.data(using: .utf8) else {
            throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                kind: .invalidSchemaShape,
                message: "Gemini returned JSON text, but Owl Guide could not prepare it for decoding.",
                diagnostics: diagnosticsWithParserOutcome(
                    diagnostics,
                    parserOutcome: .schemaMismatch,
                    rawResponseText: rawText,
                    recoveredJSONText: jsonText
                )
            )
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            try validateStructuredPayload(
                jsonObject,
                analysisMode: diagnostics.analysisMode,
                diagnostics: diagnosticsWithParserOutcome(
                    diagnostics,
                    parserOutcome: .fullJSON,
                    rawResponseText: rawText,
                    recoveredJSONText: jsonText
                )
            )
            let result = try JSONDecoder().decode(ScreenUnderstandingResult.self, from: data)
            guard result.recommendedTargets.count <= maxRecommendationCount(for: diagnostics.analysisMode) else {
                throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                    kind: .invalidSchemaShape,
                    message: "Gemini returned JSON, but recommendedTargets exceeded Owl Guide's limit for this analysis mode.",
                    diagnostics: diagnosticsWithParserOutcome(
                        diagnostics,
                        parserOutcome: .schemaMismatch,
                        rawResponseText: rawText,
                        recoveredJSONText: jsonText
                    )
                )
            }

            return result
        } catch {
            if let geminiError = error as? GeminiScreenUnderstandingError {
                throw geminiError
            }

            throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                kind: .invalidSchemaShape,
                message: "Gemini returned JSON, but it did not match Owl Guide's required minimal schema.",
                diagnostics: diagnosticsWithParserOutcome(
                    diagnostics,
                    parserOutcome: .schemaMismatch,
                    rawResponseText: rawText,
                    recoveredJSONText: jsonText
                )
            )
        }
    }

    private func unwrapJSONStringPayloadIfNeeded(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let innerString = parsed as? String else {
            return text
        }

        return innerString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedJSONCandidates(for text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedJSONPrefix = trimmed.replacingOccurrences(
            of: #"^\s*json\s*"#,
            with: "",
            options: .regularExpression
        )
        let trailingCommaRepaired = strippedJSONPrefix.replacingOccurrences(
            of: #",\s*([}\]])"#,
            with: "$1",
            options: .regularExpression
        )

        var seen = Set<String>()
        return [trimmed, strippedJSONPrefix, trailingCommaRepaired]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func classifyStructuredOutputFailure(from rawText: String, attempts: [String]) -> GeminiStructuredOutputFailureKind {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasOpeningBrace = trimmed.contains("{")
        let hasClosingBrace = trimmed.contains("}")

        if hasOpeningBrace != hasClosingBrace || hasUnclosedJSONObject(in: trimmed) {
            return .partialJSON
        }

        if attempts.count > 1 || hasOpeningBrace || hasClosingBrace {
            return .invalidSchemaShape
        }

        return .nonJSONText
    }

    private func hasUnclosedJSONObject(in text: String) -> Bool {
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for character in text {
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                    continue
                }

                if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }

                continue
            }

            if character == "\"" {
                isInsideString = true
                continue
            }

            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth = max(0, depth - 1)
            }
        }

        return depth > 0
    }

    private func structuredOutputFailureMessage(for kind: GeminiStructuredOutputFailureKind) -> String {
        switch kind {
        case .nonJSONText:
            return "Gemini returned plain text instead of a JSON object Owl Guide could parse."
        case .partialJSON:
            return "Gemini returned JSON-like text, but it looked partial or truncated."
        case .invalidSchemaShape:
            return "Gemini returned JSON-like content, but it did not match Owl Guide's expected structure."
        }
    }

    private func parserOutcome(for kind: GeminiStructuredOutputFailureKind) -> GeminiParserOutcome {
        switch kind {
        case .nonJSONText:
            return .nonJSONText
        case .partialJSON:
            return .partialJSON
        case .invalidSchemaShape:
            return .schemaMismatch
        }
    }

    private func makeDiagnostics(
        keySource: GeminiAPIKeySource,
        modelConfiguration: GeminiModelConfiguration,
        invocationMode: OwlInvocationMode,
        userRequestPresent: Bool,
        autoAnalysisFired: Bool,
        idleTimeoutSeconds: Int,
        focusLockActive: Bool,
        draftTextPreserved: Bool,
        autoAnalysisUsedFreshCapture: Bool,
        timerRestartedDueToContextChange: Bool,
        replyLanguageMode: OwlReplyLanguageMode,
        preferredResponseLanguageCode: String?,
        payloadMode: ScreenUnderstandingPayloadMode,
        analysisMode: ScreenUnderstandingAnalysisMode,
        complexityDiagnostics: ScreenUnderstandingComplexityDiagnostics,
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
        actionableCandidatesAvailable: Int,
        readableCandidatesAvailable: Int,
        actionableCandidatesSent: Int,
        readableCandidatesSent: Int,
        contextCharacterCount: Int,
        screenshotCaptured: Bool,
        originalScreenshotMimeType: String,
        originalScreenshotWidth: Int?,
        originalScreenshotHeight: Int?,
        originalScreenshotByteCount: Int?,
        originalScreenshotProcessingDescription: String,
        sendImageMimeType: String,
        sendImageWidth: Int?,
        sendImageHeight: Int?,
        sendImageByteCount: Int?,
        sendImageDidDownscale: Bool?,
        sendImageUsedLossyCompression: Bool?,
        sendImageProcessingDescription: String,
        httpStatusCode: Int?,
        transportError: String?,
        finishReason: String?,
        finishMessage: String?,
        promptTokenCount: Int?,
        outputTokenCount: Int?,
        totalTokenCount: Int?,
        totalElapsedTimeMilliseconds: Int?,
        screenshotPreparationTimeMilliseconds: Int?,
        geminiRoundTripTimeMilliseconds: Int?,
        parserOutcome: GeminiParserOutcome,
        requestSummary: String,
        requestDiagnosticsNoteOverride: String? = nil,
        rawResponseText: String,
        recoveredJSONText: String
    ) -> ScreenUnderstandingDebugInfo {
        ScreenUnderstandingDebugInfo(
            keySource: keySource,
            modelName: modelConfiguration.name,
            modelSource: modelConfiguration.source,
            invocationMode: invocationMode,
            userRequestPresent: userRequestPresent,
            autoAnalysisFired: autoAnalysisFired,
            idleTimeoutSeconds: idleTimeoutSeconds,
            focusLockActive: focusLockActive,
            draftTextPreserved: draftTextPreserved,
            autoAnalysisUsedFreshCapture: autoAnalysisUsedFreshCapture,
            timerRestartedDueToContextChange: timerRestartedDueToContextChange,
            replyLanguageMode: replyLanguageMode,
            preferredResponseLanguageCode: preferredResponseLanguageCode,
            payloadMode: payloadMode,
            analysisMode: analysisMode,
            complexityDiagnostics: complexityDiagnostics,
            browserCaptureAttempted: browserCaptureAttempted,
            browserName: browserName,
            browserFailureCategory: browserFailureCategory,
            browserContextUsageDescription: browserContextUsageDescription,
            browserCurrentURL: browserCurrentURL,
            browserURLRetrievalStatus: browserURLRetrievalStatus,
            browserPageTitle: browserPageTitle,
            browserTitleRetrievalStatus: browserTitleRetrievalStatus,
            browserVisibleTextSummaryAvailable: browserVisibleTextSummaryAvailable,
            browserTextSummaryStatus: browserTextSummaryStatus,
            browserPrimaryEntryPointCount: browserPrimaryEntryPointCount,
            screenshotCaptured: screenshotCaptured,
            originalScreenshotMimeType: originalScreenshotMimeType,
            originalScreenshotWidth: originalScreenshotWidth,
            originalScreenshotHeight: originalScreenshotHeight,
            originalScreenshotByteCount: originalScreenshotByteCount,
            originalScreenshotProcessingDescription: originalScreenshotProcessingDescription,
            sendImageMimeType: sendImageMimeType,
            sendImageWidth: sendImageWidth,
            sendImageHeight: sendImageHeight,
            sendImageByteCount: sendImageByteCount,
            sendImageDidDownscale: sendImageDidDownscale,
            sendImageUsedLossyCompression: sendImageUsedLossyCompression,
            sendImageProcessingDescription: sendImageProcessingDescription,
            actionableCandidatesAvailable: actionableCandidatesAvailable,
            readableCandidatesAvailable: readableCandidatesAvailable,
            actionableCandidatesSent: actionableCandidatesSent,
            readableCandidatesSent: readableCandidatesSent,
            contextCharacterCount: contextCharacterCount,
            failureSource: nil,
            responseMimeType: Self.responseMimeType,
            responseSchemaModeEnabled: Self.responseSchemaModeEnabled,
            requestDiagnosticsNote: requestDiagnosticsNoteOverride ?? Self.requestDiagnosticsNote,
            maxOutputTokens: Self.maxOutputTokens,
            finishReason: finishReason,
            finishMessage: finishMessage,
            promptTokenCount: promptTokenCount,
            outputTokenCount: outputTokenCount,
            totalTokenCount: totalTokenCount,
            totalElapsedTimeMilliseconds: totalElapsedTimeMilliseconds,
            screenshotPreparationTimeMilliseconds: screenshotPreparationTimeMilliseconds,
            geminiRoundTripTimeMilliseconds: geminiRoundTripTimeMilliseconds,
            httpStatusCode: httpStatusCode,
            transportError: transportError,
            rawResponseLength: rawResponseText.count,
            parserOutcome: parserOutcome,
            requestSummary: requestSummary,
            rawResponseText: rawResponseText,
            recoveredJSONText: recoveredJSONText
        )
    }

    private func shouldRetryAfterTruncation(_ error: Error) -> Bool {
        guard let geminiError = error as? GeminiScreenUnderstandingError else {
            return false
        }

        switch geminiError {
        case .invalidStructuredOutput(let kind, _, let diagnostics):
            return kind == .partialJSON || diagnostics.finishReason == "MAX_TOKENS"
        case .emptyResponse(let diagnostics):
            return diagnostics.finishReason == "MAX_TOKENS"
        default:
            return false
        }
    }

    private func requestDiagnosticsNoteWithAttempt(
        attemptNumber: Int,
        totalAttempts: Int
    ) -> String {
        if attemptNumber == 1 {
            return Self.requestDiagnosticsNote + " Attempt 1 of \(totalAttempts)."
        }

        return Self.requestDiagnosticsNote + " Automatic retry triggered after truncation. Attempt \(attemptNumber) of \(totalAttempts)."
    }

    private func requestSummaryWithAttempt(
        _ baseSummary: String,
        attemptNumber: Int,
        totalAttempts: Int
    ) -> String {
        baseSummary + "\nRetry attempt: \(attemptNumber) of \(totalAttempts)"
    }

    private func diagnosticsWithParserOutcome(
        _ diagnostics: ScreenUnderstandingDebugInfo,
        parserOutcome: GeminiParserOutcome,
        rawResponseText: String,
        recoveredJSONText: String
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
            browserCaptureAttempted: diagnostics.browserCaptureAttempted,
            browserName: diagnostics.browserName,
            browserFailureCategory: diagnostics.browserFailureCategory,
            browserContextUsageDescription: diagnostics.browserContextUsageDescription,
            browserCurrentURL: diagnostics.browserCurrentURL,
            browserURLRetrievalStatus: diagnostics.browserURLRetrievalStatus,
            browserPageTitle: diagnostics.browserPageTitle,
            browserTitleRetrievalStatus: diagnostics.browserTitleRetrievalStatus,
            browserVisibleTextSummaryAvailable: diagnostics.browserVisibleTextSummaryAvailable,
            browserTextSummaryStatus: diagnostics.browserTextSummaryStatus,
            browserPrimaryEntryPointCount: diagnostics.browserPrimaryEntryPointCount,
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
            failureSource: diagnostics.failureSource,
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
            transportError: diagnostics.transportError,
            rawResponseLength: rawResponseText.count,
            parserOutcome: parserOutcome,
            requestSummary: diagnostics.requestSummary,
            rawResponseText: rawResponseText,
            recoveredJSONText: recoveredJSONText
        )
    }

    private func makeRequestSummary(
        modelConfiguration: GeminiModelConfiguration,
        invocationMode: OwlInvocationMode,
        userRequestPresent: Bool,
        autoAnalysisFired: Bool,
        idleTimeoutSeconds: Int,
        focusLockActive: Bool,
        draftTextPreserved: Bool,
        autoAnalysisUsedFreshCapture: Bool,
        timerRestartedDueToContextChange: Bool,
        replyLanguageMode: OwlReplyLanguageMode,
        preferredResponseLanguageCode: String?,
        context: ScreenUnderstandingContext,
        payloadMode: ScreenUnderstandingPayloadMode,
        analysisMode: ScreenUnderstandingAnalysisMode,
        complexityDiagnostics: ScreenUnderstandingComplexityDiagnostics,
        originalScreenshot: WindowScreenshot,
        sendImage: GeminiSendImage,
        contextCharacterCount: Int
    ) -> String {
        let actionableIDs = context.topActionableElements.map(\.id).joined(separator: ", ")
        let readableIDs = context.topReadableElements.map(\.id).joined(separator: ", ")
        let appName = context.appName ?? "Unavailable"
        let bundleIdentifier = context.bundleIdentifier ?? "Unavailable"
        let windowTitle = context.windowTitle ?? "Unavailable"
        let browserHostname = context.browserHostname ?? "Unavailable"
        let browserName = context.browserContext?.browserName ?? "Unavailable"
        let browserURL = context.browserContext?.currentURL ?? "Unavailable"
        let browserTitle = context.browserContext?.pageTitle ?? "Unavailable"
        let browserTextSummaryAvailable = context.browserContext?.visibleTextSummary?.isEmpty == false
        let browserEntryPoints = context.browserContext?.primaryEntryPoints.joined(separator: " | ") ?? ""
        let browserContextMode = context.browserContext != nil
            ? "Browser-aware context + generic grounding"
            : "Generic screenshot + AX context only"
        let browserPageIdentity = context.browserContext?.pageIdentity ?? "Unavailable"
        let browserLikelyAudience = context.browserContext?.likelyAudience ?? "Unavailable"
        let browserSafeStartingPoint = context.browserContext?.likelySafeStartingPoint ?? "Unavailable"
        let browserAmbiguity = context.browserContext?.notableRiskOrAmbiguity ?? "Unavailable"

        return """
        Model: \(modelConfiguration.name)
        Model source: \(modelConfiguration.source.rawValue)
        Invocation mode: \(invocationMode.rawValue)
        User request present: \(userRequestPresent ? "Yes" : "No")
        Auto-analysis fired: \(autoAnalysisFired ? "Yes" : "No")
        Idle timeout seconds: \(idleTimeoutSeconds)
        Focus lock active: \(focusLockActive ? "Yes" : "No")
        Draft text preserved: \(draftTextPreserved ? "Yes" : "No")
        Auto-analysis used fresh capture: \(autoAnalysisUsedFreshCapture ? "Yes" : "No")
        Timer restarted due to context change: \(timerRestartedDueToContextChange ? "Yes" : "No")
        Reply language mode: \(replyLanguageMode.rawValue)
        Preferred response language: \(preferredResponseLanguageCode ?? "System default")
        Payload mode: \(payloadMode.rawValue)
        Analysis mode: \(analysisMode.rawValue)
        Analysis mode detail: \(complexityDiagnostics.reason)
        Response MIME type: \(Self.responseMimeType)
        Response schema mode enabled: \(Self.responseSchemaModeEnabled ? "Yes" : "No")
        Request diagnostics note: \(Self.requestDiagnosticsNote)
        Max output tokens: \(Self.maxOutputTokens)
        App name: \(appName)
        Bundle identifier: \(bundleIdentifier)
        Window title: \(windowTitle)
        Browser hostname: \(browserHostname)
        Browser-aware capture attempted: \(context.browserContext != nil ? "Yes" : "No")
        Browser name: \(browserName)
        Browser-aware context mode: \(browserContextMode)
        Browser URL retrieval: \(context.browserContext?.currentURL != nil ? "Retrieved" : "Unavailable")
        Browser URL: \(browserURL)
        Browser title retrieval: \(context.browserContext?.pageTitle != nil ? "Retrieved" : "Unavailable")
        Browser page title: \(browserTitle)
        Browser text summary available: \(browserTextSummaryAvailable ? "Yes" : "No")
        Browser page identity: \(browserPageIdentity)
        Browser likely audience: \(browserLikelyAudience)
        Browser primary entry points: \(browserEntryPoints.isEmpty ? "None" : browserEntryPoints)
        Browser safe starting point: \(browserSafeStartingPoint)
        Browser ambiguity note: \(browserAmbiguity)
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
        Actionable candidates available: \(context.actionableCandidatesAvailable)
        Readable candidates available: \(context.readableCandidatesAvailable)
        Actionable candidates sent: \(context.topActionableElements.count)
        Readable candidates sent: \(context.topReadableElements.count)
        Filtered useful elements: \(complexityDiagnostics.filteredUsefulElementCount)
        Sampled candidate count: \(complexityDiagnostics.sampledCandidateCount)
        Generic candidate ratio: \(String(format: "%.0f%%", complexityDiagnostics.genericCandidateRatio * 100))
        Container/window-control ratio: \(String(format: "%.0f%%", complexityDiagnostics.containerOrWindowControlRatio * 100))
        Top candidates mostly generic: \(complexityDiagnostics.topCandidatesMostlyGeneric ? "Yes" : "No")
        Send-image long edge: \(complexityDiagnostics.screenshotLongEdge)
        Send-image bytes: \(complexityDiagnostics.sendImageByteCount)
        Routing confidence: \(complexityDiagnostics.routingConfidence.displayName)
        Compact context characters: \(contextCharacterCount)
        Actionable candidate ids: \(actionableIDs.isEmpty ? "None" : actionableIDs)
        Readable candidate ids: \(readableIDs.isEmpty ? "None" : readableIDs)
        """
    }

    private func validateStructuredPayload(
        _ jsonObject: Any,
        analysisMode: ScreenUnderstandingAnalysisMode,
        diagnostics: ScreenUnderstandingDebugInfo
    ) throws {
        let maxRecommendationCount = maxRecommendationCount(for: analysisMode)
        guard let root = jsonObject as? [String: Any] else {
            throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                kind: .invalidSchemaShape,
                message: "Gemini returned JSON, but the top level was not an object.",
                diagnostics: diagnosticsWithParserOutcome(
                    diagnostics,
                    parserOutcome: .schemaMismatch,
                    rawResponseText: "The model returned a JSON value that was not an object.",
                    recoveredJSONText: diagnostics.recoveredJSONText
                )
            )
        }

        let expectedRootKeys: Set<String> = ["pageSummary", "likelyUserGoal", "recommendedTargets", "cautionNotes"]
        guard Set(root.keys) == expectedRootKeys else {
            throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                kind: .invalidSchemaShape,
                message: "Gemini returned JSON, but the top-level keys did not match Owl Guide's required schema.",
                diagnostics: diagnosticsWithParserOutcome(
                    diagnostics,
                    parserOutcome: .schemaMismatch,
                    rawResponseText: "Unexpected top-level keys: \(root.keys.sorted().joined(separator: ", ")).",
                    recoveredJSONText: diagnostics.recoveredJSONText
                )
            )
        }

        guard root["pageSummary"] is String,
              root["likelyUserGoal"] is String else {
            throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                kind: .invalidSchemaShape,
                message: "Gemini returned JSON, but pageSummary or likelyUserGoal was not a string.",
                diagnostics: diagnosticsWithParserOutcome(
                    diagnostics,
                    parserOutcome: .schemaMismatch,
                    rawResponseText: "pageSummary and likelyUserGoal must both be strings.",
                    recoveredJSONText: diagnostics.recoveredJSONText
                )
            )
        }

        guard let recommendedTargets = root["recommendedTargets"] as? [Any] else {
            throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                kind: .invalidSchemaShape,
                message: "Gemini returned JSON, but recommendedTargets was not an array.",
                diagnostics: diagnosticsWithParserOutcome(
                    diagnostics,
                    parserOutcome: .schemaMismatch,
                    rawResponseText: "recommendedTargets must be an array of objects.",
                    recoveredJSONText: diagnostics.recoveredJSONText
                )
            )
        }

        guard recommendedTargets.count <= maxRecommendationCount else {
            throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                kind: .invalidSchemaShape,
                message: "Gemini returned JSON, but recommendedTargets contained more than \(maxRecommendationCount) items for this analysis mode.",
                diagnostics: diagnosticsWithParserOutcome(
                    diagnostics,
                    parserOutcome: .schemaMismatch,
                    rawResponseText: "recommendedTargets must contain at most \(maxRecommendationCount) items.",
                    recoveredJSONText: diagnostics.recoveredJSONText
                )
            )
        }

        let requiredTargetKeys: Set<String> = ["rank", "label", "whyThisMatters", "relatedLocalElement"]
        let allowedTargetKeys: Set<String> = ["rank", "label", "whyThisMatters", "relatedLocalElement", "visualBoundingBox", "intendedAction", "actionValue"]
        for candidate in recommendedTargets {
            guard let target = candidate as? [String: Any] else {
                throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                    kind: .invalidSchemaShape,
                    message: "Gemini returned JSON, but a recommended target was not an object.",
                    diagnostics: diagnosticsWithParserOutcome(
                        diagnostics,
                        parserOutcome: .schemaMismatch,
                        rawResponseText: "Each recommendedTargets item must be an object.",
                        recoveredJSONText: diagnostics.recoveredJSONText
                    )
                )
            }

            let keys = Set(target.keys)
            guard requiredTargetKeys.isSubset(of: keys), keys.isSubset(of: allowedTargetKeys) else {
                throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                    kind: .invalidSchemaShape,
                    message: "Gemini returned JSON, but a recommended target included unexpected or missing keys.",
                    diagnostics: diagnosticsWithParserOutcome(
                        diagnostics,
                        parserOutcome: .schemaMismatch,
                        rawResponseText: "Each recommendedTargets item must contain rank, label, whyThisMatters, relatedLocalElement, and optionally visualBoundingBox, intendedAction, actionValue.",
                        recoveredJSONText: diagnostics.recoveredJSONText
                    )
                )
            }

            guard isJSONInteger(target["rank"]),
                  target["label"] is String,
                  target["whyThisMatters"] is String,
                  target["relatedLocalElement"] is String else {
                throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                    kind: .invalidSchemaShape,
                    message: "Gemini returned JSON, but a recommended target used the wrong value types.",
                    diagnostics: diagnosticsWithParserOutcome(
                        diagnostics,
                        parserOutcome: .schemaMismatch,
                        rawResponseText: "rank must be an integer, and label, whyThisMatters, and relatedLocalElement must be strings.",
                        recoveredJSONText: diagnostics.recoveredJSONText
                    )
                )
            }
        }

        guard let cautionNotes = root["cautionNotes"] as? [Any],
              cautionNotes.allSatisfy({ $0 is String }) else {
            throw GeminiScreenUnderstandingError.invalidStructuredOutput(
                kind: .invalidSchemaShape,
                message: "Gemini returned JSON, but cautionNotes was not an array of strings.",
                diagnostics: diagnosticsWithParserOutcome(
                    diagnostics,
                    parserOutcome: .schemaMismatch,
                    rawResponseText: "cautionNotes must be an array of strings.",
                    recoveredJSONText: diagnostics.recoveredJSONText
                )
            )
        }
    }

    private func maxRecommendationCount(for analysisMode: ScreenUnderstandingAnalysisMode) -> Int {
        1
    }

    private func isJSONInteger(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else {
            return false
        }

        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return false
        }

        return floor(number.doubleValue) == number.doubleValue
    }

    private func makePreview(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return "No response body."
        }

        return truncatedText(text)
    }

    private func truncatedText(_ text: String) -> String {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        guard normalized.count > 240 else {
            return normalized
        }

        return String(normalized.prefix(237)) + "..."
    }
}

private struct ResolvedAPIKey {
    let value: String
    let source: GeminiAPIKeySource
}

struct GeminiModelConfiguration {
    let name: String
    let source: GeminiModelSource
}

private struct GeminiModelSelectionStore {
    private let defaults = UserDefaults.standard
    private let key = "owlguide.gemini.selected-model"

    func load() -> String? {
        defaults.string(forKey: key)
    }

    func containsValue() -> Bool {
        load()?.isEmpty == false
    }

    func save(_ modelName: String) throws {
        defaults.set(modelName, forKey: key)
    }

    func clear() throws {
        defaults.removeObject(forKey: key)
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [GeminiCandidate]?
    let usageMetadata: GeminiUsageMetadata?
    let modelVersion: String?
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContent?
    let finishReason: String?
    let finishMessage: String?
}

private struct GeminiContent: Decodable {
    let parts: [GeminiPart]?
}

private struct GeminiPart: Decodable {
    let text: String?
}

private struct GeminiUsageMetadata: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
}

private struct GeminiErrorEnvelope: Decodable {
    let error: GeminiServiceError
}

private struct GeminiServiceError: Decodable {
    let message: String
}
