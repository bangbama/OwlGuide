import Foundation

struct ScenarioSkillRouter {
    struct TaskThreadTransition {
        let thread: OwlGuideTaskThread
        let guidedStep: OwlGuideGuidedStep
        let note: String
    }

    func detectContext(
        userRequest: String?,
        appName: String,
        bundleIdentifier: String,
        windowTitle: String,
        browserCapture: BrowserCaptureContext?,
        actionableCandidates: [AXRankedElement],
        readableCandidates: [AXRankedElement],
        rawElements: [AXElementNode]
    ) -> OwlGuideScenarioContext {
        let titleCorpus = (browserCapture?.pageTitle ?? windowTitle).lowercased()
        let axBodyCorpus = makeBodyCorpus(
            actionableCandidates: actionableCandidates,
            readableCandidates: readableCandidates,
            rawElements: rawElements
        )
        let browserBodyCorpus = makeBrowserBodyCorpus(from: browserCapture)
        let bodyCorpus = [browserBodyCorpus, axBodyCorpus]
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        let fullCorpus = [titleCorpus, bodyCorpus].joined(separator: " | ")
        let hostname = browserCapture?.hostname ?? detectHostname(from: fullCorpus)
        let medicalScore = scoreSignals(
            titleCorpus: titleCorpus,
            bodyCorpus: bodyCorpus,
            keywords: medicalKeywords,
            genericKeywords: [],
            hostname: hostname,
            hostnameKeywords: medicalHostnameKeywords
        )
        let bankingScore = scoreSignals(
            titleCorpus: titleCorpus,
            bodyCorpus: bodyCorpus,
            keywords: bankingStrongKeywords,
            genericKeywords: bankingGenericKeywords,
            hostname: hostname,
            hostnameKeywords: bankingHostnameKeywords
        )
        let governmentScore = scoreSignals(
            titleCorpus: titleCorpus,
            bodyCorpus: bodyCorpus,
            keywords: governmentStrongKeywords,
            genericKeywords: governmentGenericKeywords,
            hostname: hostname,
            hostnameKeywords: governmentHostnameKeywords
        )
        let caregiverScore = scoreSignals(
            titleCorpus: titleCorpus,
            bodyCorpus: bodyCorpus,
            keywords: caregiverKeywords,
            genericKeywords: [],
            hostname: hostname,
            hostnameKeywords: caregiverHostnameKeywords
        )

        let rankedSkills: [(OwlGuideScenarioSkill, Int)] = [
            (.medicalPortal, medicalScore),
            (.banking, bankingScore),
            (.governmentBenefits, governmentScore),
            (.caregiverProxy, caregiverScore)
        ].sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.rawValue < rhs.0.rawValue
            }
            return lhs.1 > rhs.1
        }

        let bestSkill = rankedSkills.first(where: { $0.1 > 0 })
        let bestScore = bestSkill?.1 ?? 0
        let secondScore = rankedSkills.dropFirst().first?.1 ?? 0
        let confidence: OwlGuideScenarioConfidence
        if bestScore >= 7 && bestScore >= secondScore + 3 {
            confidence = .high
        } else if bestScore >= 4 {
            confidence = .medium
        } else {
            confidence = .low
        }

        let selectedSkill: OwlGuideScenarioSkill
        if confidence == .low {
            selectedSkill = .general
        } else {
            selectedSkill = bestSkill?.0 ?? .general
        }

        let matchedSignals = matchedSignals(for: selectedSkill, in: fullCorpus, hostname: hostname)
        let likelyPageType = coarsePageType(
            for: selectedSkill,
            in: fullCorpus,
            confidence: confidence,
            browserCapture: browserCapture
        )
        let tasks = coarseLikelyTasks(pageType: likelyPageType)

        return OwlGuideScenarioContext(
            userRequest: userRequest,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            browserHostname: hostname,
            likelyPageType: likelyPageType,
            selectedSkill: selectedSkill,
            confidence: confidence,
            matchedSignals: Array(matchedSignals.prefix(6)),
            likelyPrimaryTask: tasks.primary,
            likelyBackupTask: tasks.backup
        )
    }

    private func coarsePageType(
        for skill: OwlGuideScenarioSkill,
        in textCorpus: String,
        confidence: OwlGuideScenarioConfidence,
        browserCapture: BrowserCaptureContext?
    ) -> String {
        if let browserCapture {
            let entryPointCount = browserCapture.primaryEntryPoints.count
            let path = URL(string: browserCapture.currentURL ?? "")?.path ?? ""

            if (path.isEmpty || path == "/") && entryPointCount >= 4 {
                return "Home page / navigation hub"
            }

            if entryPointCount >= 5 && containsAny(in: textCorpus, keywords: ["services", "departments", "find care", "resources", "locations", "patients", "programs", "portal"]) {
                return "Menu-heavy directory or portal page"
            }

            if containsAny(in: textCorpus, keywords: ["about", "overview", "services", "preparation", "resources", "instructions", "learn more", "what to expect", "faq", "imaging services"]) {
                return "Information / guide page"
            }
        }

        if containsAny(in: textCorpus, keywords: ["sign in", "login", "password", "sign-in", "verification", "security code"]) {
            return "Sign-in style page"
        }

        if containsAny(in: textCorpus, keywords: medicalServiceKeywords + ["services", "resources", "information", "overview", "locations"]) {
            return "Information / guide page"
        }

        if containsAny(in: textCorpus, keywords: ["results", "status", "tracking", "wait time", "wait times", "lab", "test", "dashboard", "account summary", "summary"]) {
            return "Status / account summary page"
        }

        if containsAny(in: textCorpus, keywords: ["application", "form", "upload", "documents", "choose file"]) {
            return "Application form"
        }

        if containsAny(in: textCorpus, keywords: ["submit", "continue", "reset password", "verify now", "book now", "apply now", "upload now"]) {
            return "Action page"
        }

        if containsAny(in: textCorpus, keywords: ["dashboard", "home", "overview", "summary", "menu", "messages", "appointments"]) {
            return "Home page / navigation hub"
        }

        if confidence == .high {
            switch skill {
            case .medicalPortal, .banking, .governmentBenefits, .caregiverProxy:
                return "Task or account page"
            case .general:
                return "General page"
            }
        }

        return "General page"
    }

    private func makeBrowserBodyCorpus(from browserCapture: BrowserCaptureContext?) -> String {
        guard let browserCapture else {
            return ""
        }

        let parts: [String?] = [
            browserCapture.currentURL,
            browserCapture.pageTitle,
            browserCapture.visibleTextSummary,
            browserCapture.primaryEntryPoints.joined(separator: " | ")
        ]

        return parts
            .compactMap { part in
                guard let part else { return nil }
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " | ")
            .lowercased()
    }

    private func coarseLikelyTasks(pageType: String) -> (primary: String, backup: String) {
        switch pageType {
        case "Sign-in style page":
            return ("Get into the right account or starting point", "Recover access or confirm the correct entry option")
        case "Information / guide page":
            return ("Find the main information or service entry point", "Open the most relevant resource or next link")
        case "Status / account summary page":
            return ("Review the main information shown on this page", "Find the next useful detail or related section")
        case "Application form":
            return ("Find where to continue or review the form", "Check what information or document is needed next")
        case "Home page / navigation hub":
            return ("Choose the main area to open first", "Find the most relevant section for your goal")
        case "Menu-heavy directory or portal page":
            return ("Choose the best patient-facing section to open first", "Ignore lower-value organizational links for now")
        case "Action page":
            return ("Find the main safe action to start with", "Check the visible instructions before continuing")
        case "Task or account page":
            return ("Find the safest place to begin on this page", "Open the most relevant task entry point")
        default:
            return ("Understand what this page is for", "Find the safest place to begin")
        }
    }

    func buildFirstResponse(
        from context: OwlGuideScenarioContext,
        result: ScreenUnderstandingResult
    ) -> OwlGuideScenarioGuidance {
        let hasDirectUserQuestion = context.userRequest?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        if hasDirectUserQuestion {
            let answer = trimmed(result.pageSummary, limit: 140)
            let likelyGoal = trimmed(result.likelyUserGoal, limit: 90)
            let followUp = result.recommendedTargets.first.map { trimmed($0.whyThisMatters, limit: 100) }

            return OwlGuideScenarioGuidance(
                context: context,
                firstResponse: OwlGuideFirstResponse(
                    contextRecognition: answer,
                    primaryLikelyTask: likelyGoal.isEmpty ? "Answer the user's question about this page" : likelyGoal,
                    backupLikelyTask: "Find the safest next step on this page",
                    safeFirstStep: (followUp?.isEmpty == false ? followUp! : answer).replacingOccurrences(of: "\n", with: " "),
                    clarificationQuestion: nil
                )
            )
        }

        let safeFirstStep: String
        if let target = result.recommendedTargets.first {
            let targetLabel = trimmed(target.label, limit: 60)
            if target.relatedLocalElement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                safeFirstStep = "Start by reviewing \"\(targetLabel)\" first. Owl Guide sees that as the safest place to orient yourself on this screen."
            } else {
                safeFirstStep = "Start with \"\(targetLabel)\". Owl Guide can inspect and highlight that local element on screen."
            }
        } else {
            safeFirstStep = fallbackSafeFirstStep(for: context)
        }

        let nextQuestion: String?
        if context.confidence == .high {
            nextQuestion = nil
        } else {
            nextQuestion = clarificationQuestion(for: context)
        }

        let recognition = contextRecognition(for: context)

        return OwlGuideScenarioGuidance(
            context: context,
            firstResponse: OwlGuideFirstResponse(
                contextRecognition: recognition,
                primaryLikelyTask: context.likelyPrimaryTask,
                backupLikelyTask: context.likelyBackupTask,
                safeFirstStep: safeFirstStep.replacingOccurrences(of: "\n", with: ""),
                clarificationQuestion: nextQuestion
            )
        )
    }

    func refineContext(
        base context: OwlGuideScenarioContext,
        result: ScreenUnderstandingResult
    ) -> OwlGuideScenarioContext {
        let resultCorpus = [
            result.pageSummary,
            result.likelyUserGoal
        ]
        + result.recommendedTargets.map(\.label)
        + result.recommendedTargets.map(\.whyThisMatters)

        let combinedCorpus = ([context.windowTitle] + resultCorpus)
            .joined(separator: " | ")
            .lowercased()

        let likelyMedicalServicesPage = containsAny(in: combinedCorpus, keywords: medicalServiceKeywords)
        let likelyVisitingInfoPage = containsAny(in: combinedCorpus, keywords: visitingInfoKeywords)
        let selectedSkill = (likelyMedicalServicesPage || likelyVisitingInfoPage) ? OwlGuideScenarioSkill.medicalPortal : context.selectedSkill
        let confidence: OwlGuideScenarioConfidence
        if (likelyMedicalServicesPage || likelyVisitingInfoPage) && context.confidence == .low {
            confidence = .medium
        } else {
            confidence = context.confidence
        }

        let likelyPageType: String
        if likelyVisitingInfoPage {
            likelyPageType = "Information / guide page"
        } else if likelyMedicalServicesPage {
            likelyPageType = "Medical services page"
        } else {
            likelyPageType = classifyPageType(for: selectedSkill, in: combinedCorpus)
        }

        let tasks: (primary: String, backup: String)
        if likelyVisitingInfoPage {
            tasks = (
                "Find visiting information or patient guidance",
                "Open the most relevant visitor or patient resource"
            )
        } else {
            tasks = likelyTasks(for: selectedSkill, pageType: likelyPageType)
        }

        let extraSignal: [String]
        if likelyVisitingInfoPage {
            extraSignal = ["gemini:visiting-info-page"]
        } else if likelyMedicalServicesPage {
            extraSignal = ["gemini:medical-services-page"]
        } else {
            extraSignal = []
        }

        return OwlGuideScenarioContext(
            userRequest: context.userRequest,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            browserHostname: context.browserHostname,
            likelyPageType: likelyPageType,
            selectedSkill: selectedSkill,
            confidence: confidence,
            matchedSignals: Array((context.matchedSignals + extraSignal).prefix(6)),
            likelyPrimaryTask: tasks.primary,
            likelyBackupTask: tasks.backup
        )
    }

    func intentOptions(for context: OwlGuideScenarioContext) -> [OwlGuideIntentOption] {
        if context.userRequest?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return [
                OwlGuideIntentOption(
                    intent: .understandPage,
                    title: OwlGuideUserIntent.understandPage.displayName,
                    summary: "Answer the user's question first, then suggest the safest next step if needed.",
                    isPrimary: true
                )
            ]
        }

        let intents: [OwlGuideUserIntent]

        switch context.selectedSkill {
        case .medicalPortal:
            switch context.likelyPageType {
            case "Home page / navigation hub", "Menu-heavy directory or portal page":
                intents = [.findResources, .learnServices, .accessMedicalImages]
            case "Information / guide page":
                if containsAny(in: context.likelyPrimaryTask.lowercased(), keywords: visitingInfoKeywords)
                    || containsAny(in: context.likelyBackupTask.lowercased(), keywords: visitingInfoKeywords) {
                    intents = [.findResources, .understandPage, .learnServices]
                } else {
                    intents = [.learnServices, .findResources, .accessMedicalImages]
                }
            case "Medical services page":
                intents = [.learnServices, .findResources, .accessMedicalImages]
            case "Wait-times page":
                intents = [.findDoctor, .checkStatus, .understandPage]
            case "Sign-in page":
                intents = [.signIn, .recoverAccount, .understandPage]
            case "Appointments page":
                intents = [.bookAppointment, .findDoctor, .understandPage]
            case "Results page":
                intents = [.checkResults, .sendMessage, .understandPage]
            case "Messages page":
                intents = [.sendMessage, .checkResults, .understandPage]
            default:
                intents = [.learnServices, .findDoctor, .understandPage]
            }
        case .banking:
            switch context.likelyPageType {
            case "Sign-in page", "Verification page":
                intents = [.signIn, .recoverAccount, .understandPage]
            case "Bill-pay page":
                intents = [.payBill, .checkStatus, .understandPage]
            default:
                intents = [.signIn, .payBill, .checkStatus]
            }
        case .governmentBenefits:
            switch context.likelyPageType {
            case "Sign-in page":
                intents = [.signIn, .recoverAccount, .understandPage]
            case "Application form", "Document upload page":
                intents = [.continueApplication, .checkStatus, .understandPage]
            case "Status page", "Status / account summary page":
                intents = [.checkStatus, .continueApplication, .understandPage]
            default:
                intents = [.signIn, .continueApplication, .checkStatus]
            }
        case .caregiverProxy:
            intents = [.confirmProfile, .signIn, .understandPage]
        case .general:
            intents = generalIntentOptions(for: context)
        }

        return Array(intents.prefix(3)).enumerated().map { index, intent in
            OwlGuideIntentOption(
                intent: intent,
                title: intent.displayName,
                summary: intentSummary(for: intent, in: context),
                isPrimary: index == 0
            )
        }
    }

    func startTaskThread(
        from context: OwlGuideScenarioContext,
        result: ScreenUnderstandingResult
    ) -> TaskThreadTransition {
        let options = intentOptions(for: context)
        let selectedIntent = options.first?.intent ?? .understandPage
        let guidedStep = buildGuidedStep(
            for: context,
            result: result,
            intent: selectedIntent,
            isConfirmed: false
        )

        return TaskThreadTransition(
            thread: OwlGuideTaskThread(
                selectedSkill: context.selectedSkill,
                confidence: context.confidence,
                chosenIntent: selectedIntent,
                currentPageType: context.likelyPageType,
                currentSuggestedNextStep: guidedStep.nextStep,
                isConfirmed: false,
                appName: context.appName,
                bundleIdentifier: context.bundleIdentifier,
                browserHostname: context.browserHostname,
                continuationSummary: "A tentative task thread was started from the current first response."
            ),
            guidedStep: guidedStep,
            note: "Started a tentative task thread from the current first response."
        )
    }

    func confirmTaskThread(
        intent: OwlGuideUserIntent,
        from context: OwlGuideScenarioContext,
        result: ScreenUnderstandingResult
    ) -> TaskThreadTransition {
        let guidedStep = buildGuidedStep(
            for: context,
            result: result,
            intent: intent,
            isConfirmed: true
        )

        return TaskThreadTransition(
            thread: OwlGuideTaskThread(
                selectedSkill: context.selectedSkill,
                confidence: context.confidence,
                chosenIntent: intent,
                currentPageType: context.likelyPageType,
                currentSuggestedNextStep: guidedStep.nextStep,
                isConfirmed: true,
                appName: context.appName,
                bundleIdentifier: context.bundleIdentifier,
                browserHostname: context.browserHostname,
                continuationSummary: "The user confirmed this task, so Owl Guide is guiding one safe step at a time."
            ),
            guidedStep: guidedStep,
            note: "The current task thread is confirmed."
        )
    }

    func continueTaskThread(
        existing thread: OwlGuideTaskThread,
        newContext: OwlGuideScenarioContext,
        result: ScreenUnderstandingResult
    ) -> TaskThreadTransition {
        let options = intentOptions(for: newContext)
        let availableIntents = Set(options.map(\.intent))
        let sameApp = thread.bundleIdentifier == newContext.bundleIdentifier
        let sameHost = thread.browserHostname == newContext.browserHostname
        let continuityPreserved = sameApp || (sameHost && newContext.browserHostname != nil)
        let pageStillFitsIntent = availableIntents.contains(thread.chosenIntent) && isIntentCompatible(thread.chosenIntent, with: newContext)
        let nextStepStillFits = hasCompatibleNextStep(
            for: thread.chosenIntent,
            context: newContext,
            result: result
        )
        let canContinue = continuityPreserved && pageStillFitsIntent && nextStepStillFits

        if canContinue {
            let guidedStep = buildGuidedStep(
                for: newContext,
                result: result,
                intent: thread.chosenIntent,
                isConfirmed: thread.isConfirmed
            )
            let note = thread.isConfirmed
                ? "This still looks like the same \(flowName(for: thread.chosenIntent)), so Owl Guide is continuing the current task."
                : "This still looks like the same \(flowName(for: thread.chosenIntent)), so Owl Guide is keeping the tentative task."

            return TaskThreadTransition(
                thread: OwlGuideTaskThread(
                    selectedSkill: thread.selectedSkill == .general ? newContext.selectedSkill : thread.selectedSkill,
                    confidence: newContext.confidence,
                    chosenIntent: thread.chosenIntent,
                    currentPageType: newContext.likelyPageType,
                    currentSuggestedNextStep: guidedStep.nextStep,
                    isConfirmed: thread.isConfirmed,
                    appName: newContext.appName,
                    bundleIdentifier: newContext.bundleIdentifier,
                    browserHostname: newContext.browserHostname,
                    continuationSummary: note
                ),
                guidedStep: guidedStep,
                note: note
            )
        }

        let fallback = startTaskThread(from: newContext, result: result)
        let resetReason: String
        if !continuityPreserved {
            resetReason = "This page appears to come from a different app or site, so Owl Guide started a new tentative task."
        } else if !pageStillFitsIntent {
            resetReason = "This page no longer matches the previous \(flowName(for: thread.chosenIntent)), so Owl Guide started a new tentative task."
        } else {
            resetReason = "Owl Guide could not find a clear next step for the previous \(flowName(for: thread.chosenIntent)) on this page, so it started a new tentative task."
        }

        return TaskThreadTransition(
            thread: OwlGuideTaskThread(
                selectedSkill: fallback.thread.selectedSkill,
                confidence: fallback.thread.confidence,
                chosenIntent: fallback.thread.chosenIntent,
                currentPageType: fallback.thread.currentPageType,
                currentSuggestedNextStep: fallback.thread.currentSuggestedNextStep,
                isConfirmed: false,
                appName: fallback.thread.appName,
                bundleIdentifier: fallback.thread.bundleIdentifier,
                browserHostname: fallback.thread.browserHostname,
                continuationSummary: resetReason
            ),
            guidedStep: fallback.guidedStep,
            note: resetReason
        )
    }

    private let medicalKeywords = [
        "mychart", "patient portal", "appointments", "appointment", "test results", "results", "medications", "doctor", "clinic", "hospital", "wait time", "wait times", "urgent care", "emergency", "lab", "medical imaging", "diagnostic imaging", "imaging services", "medical images"
    ]
    private let medicalServiceKeywords = [
        "medical imaging", "diagnostic imaging", "imaging services", "medical images",
        "access medical images", "patient resources", "x-ray", "ultrasound", "mri",
        "ct scan", "mammography", "locations", "service overview", "patient preparation"
    ]
    private let visitingInfoKeywords = [
        "visiting hours", "visitor hours", "visitor rules", "visitor guidance",
        "visiting information", "patient visit", "patient visiting", "visiting policy",
        "visitor policy", "visitors", "visiting"
    ]
    private let medicalHostnameKeywords = ["mychart", "hospital", "clinic", "health", "medical", "urgentcare"]
    private let bankingStrongKeywords = [
        "bank", "statement", "transfer", "checking", "savings", "account summary", "credit card", "routing number", "account balance"
    ]
    private let bankingGenericKeywords = ["pay bill", "bill pay", "security code", "verify", "verification", "sign in", "login", "password"]
    private let bankingHostnameKeywords = ["bank", "creditunion", "rbc", "td", "bmo", "cibc", "scotiabank", "chase", "capitalone", "amex"]
    private let governmentStrongKeywords = [
        "service account", "pension", "benefits", "service canada", "government", "benefit payment", "tax benefit"
    ]
    private let governmentGenericKeywords = ["application", "upload documents", "upload", "status", "submit", "verify identity"]
    private let governmentHostnameKeywords = ["gov", "canada", "servicecanada", "benefits", "pension"]
    private let caregiverKeywords = [
        "proxy", "caregiver", "family member", "dependent", "representative", "delegate", "authorized user", "authorized"
    ]
    private let caregiverHostnameKeywords = ["proxy", "caregiver", "family"]

    private func makeBodyCorpus(
        actionableCandidates: [AXRankedElement],
        readableCandidates: [AXRankedElement],
        rawElements: [AXElementNode]
    ) -> String {
        let rankedTexts = actionableCandidates.prefix(6).map { candidateText(from: $0.element) }
            + readableCandidates.prefix(10).map { candidateText(from: $0.element) }
        let rawTexts = rawElements.prefix(12).map { element in
            [element.title, element.label, element.value, element.displayName]
                .joined(separator: " ")
        }

        return (rankedTexts + rawTexts)
            .joined(separator: " | ")
            .lowercased()
    }

    private func candidateText(from element: AXElementNode) -> String {
        [element.title, element.label, element.value, element.displayName, element.role]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "Unavailable" }
            .joined(separator: " ")
    }

    private func detectHostname(from textCorpus: String) -> String? {
        let pattern = #"\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(textCorpus.startIndex..<textCorpus.endIndex, in: textCorpus)
        let ignoredHosts = ["ai.perplexity.comet", "perplexity.ai", "perplexity.comet"]
        let matches = regex.matches(in: textCorpus, options: [], range: range)

        for match in matches {
            guard let matchRange = Range(match.range, in: textCorpus) else {
                continue
            }

            let host = String(textCorpus[matchRange])
            if host.contains("ax") || ignoredHosts.contains(where: { host.contains($0) }) {
                continue
            }

            return host
        }

        return nil
    }

    private func scoreSignals(
        titleCorpus: String,
        bodyCorpus: String,
        keywords: [String],
        genericKeywords: [String],
        hostname: String?,
        hostnameKeywords: [String]
    ) -> Int {
        let hostnameScore = hostnameKeywords.reduce(into: 0) { total, keyword in
            if hostname?.contains(keyword) == true {
                total += 8
            }
        }

        let titleKeywordScore = weightedMatchScore(in: titleCorpus, keywords: keywords, weight: 4)
        let bodyKeywordScore = weightedMatchScore(in: bodyCorpus, keywords: keywords, weight: 1)
        let genericTitleScore = weightedMatchScore(in: titleCorpus, keywords: genericKeywords, weight: 1)
        let genericBodyScore = weightedMatchScore(in: bodyCorpus, keywords: genericKeywords, weight: 0)

        return hostnameScore + titleKeywordScore + bodyKeywordScore + genericTitleScore + genericBodyScore
    }

    private func matchedSignals(
        for skill: OwlGuideScenarioSkill,
        in textCorpus: String,
        hostname: String?
    ) -> [String] {
        let keywords: [String]
        switch skill {
        case .medicalPortal:
            keywords = medicalKeywords + medicalHostnameKeywords
        case .banking:
            keywords = bankingStrongKeywords + bankingGenericKeywords + bankingHostnameKeywords
        case .governmentBenefits:
            keywords = governmentStrongKeywords + governmentGenericKeywords + governmentHostnameKeywords
        case .caregiverProxy:
            keywords = caregiverKeywords + caregiverHostnameKeywords
        case .general:
            keywords = []
        }

        var signals: [String] = []

        if let hostname {
            signals.append("host:\(hostname)")
        }

        for keyword in keywords where textCorpus.contains(keyword) {
            signals.append(keyword)
        }

        return signals.isEmpty ? ["generic-fallback"] : signals
    }

    private func classifyPageType(for skill: OwlGuideScenarioSkill, in textCorpus: String) -> String {
        if containsAny(in: textCorpus, keywords: ["wait time", "wait times", "urgent care", "emergency"]) {
            return "Wait-times page"
        }

        if containsAny(in: textCorpus, keywords: medicalServiceKeywords) {
            return "Medical services page"
        }

        if containsAny(in: textCorpus, keywords: ["services", "resources", "preparation", "instructions", "what to expect", "overview", "learn more", "faq"]) {
            return "Information / guide page"
        }

        if containsAny(in: textCorpus, keywords: ["departments", "locations", "programs", "services", "portal", "find care"]) &&
            containsAny(in: textCorpus, keywords: ["home", "overview", "menu", "patients"]) {
            return "Menu-heavy directory or portal page"
        }

        if containsAny(in: textCorpus, keywords: ["security code", "verify", "verification", "two-factor"]) {
            return "Verification page"
        }

        if containsAny(in: textCorpus, keywords: ["sign in", "login", "password", "sign-in"]) {
            return "Sign-in page"
        }

        if containsAny(in: textCorpus, keywords: ["upload", "documents", "choose file"]) {
            return "Document upload page"
        }

        if containsAny(in: textCorpus, keywords: ["application", "form", "submit"]) {
            return "Application form"
        }

        if containsAny(in: textCorpus, keywords: ["status", "tracking", "review status", "account summary", "summary"]) {
            return "Status / account summary page"
        }

        if containsAny(in: textCorpus, keywords: ["continue", "reset password", "apply now", "book now", "upload now"]) {
            return "Action page"
        }

        if containsAny(in: textCorpus, keywords: ["proxy", "caregiver", "family member", "dependent", "representative", "switch profile"]) {
            return "Proxy / profile page"
        }

        if containsAny(in: textCorpus, keywords: ["appointments", "schedule", "book", "reschedule"]) {
            return "Appointments page"
        }

        if containsAny(in: textCorpus, keywords: ["results", "lab", "test"]) {
            return "Results page"
        }

        if containsAny(in: textCorpus, keywords: ["messages", "message center"]) {
            return "Messages page"
        }

        if containsAny(in: textCorpus, keywords: ["medications", "refill", "pharmacy"]) {
            return "Medications page"
        }

        if containsAny(in: textCorpus, keywords: ["bill pay", "pay bill", "payment"]) {
            return "Bill-pay page"
        }

        if containsAny(in: textCorpus, keywords: ["transfer", "move money"]) {
            return "Transfer page"
        }

        if containsAny(in: textCorpus, keywords: ["dashboard", "home", "overview", "account summary"]) {
            return "Home page / navigation hub"
        }

        switch skill {
        case .medicalPortal:
            return "Medical page"
        case .banking:
            return "Finance page"
        case .governmentBenefits:
            return "Benefits page"
        case .caregiverProxy:
            return "Caregiver / proxy page"
        case .general:
            return "General page"
        }
    }

    private func likelyTasks(for skill: OwlGuideScenarioSkill, pageType: String) -> (primary: String, backup: String) {
        switch skill {
        case .medicalPortal:
            switch pageType {
            case "Home page / navigation hub", "Menu-heavy directory or portal page":
                return ("Find the best patient-facing starting area", "Open the most relevant service or resource section")
            case "Information / guide page":
                return ("Learn the main information shown on this page", "Find the most relevant patient resource or next link")
            case "Medical services page":
                return ("Learn about imaging or service options", "Find patient resources or access medical images")
            case "Wait-times page":
                return ("Compare urgent-care or emergency wait options", "Check the current wait-time details before deciding where to go")
            case "Sign-in page":
                return ("Sign in to a medical account", "Recover access to the medical portal")
            case "Appointments page":
                return ("Book or change an appointment", "Review scheduling options before continuing")
            case "Results page":
                return ("Check test or lab results", "Review other parts of the medical account")
            case "Messages page":
                return ("Read or send a message to the care team", "Review related medical account options")
            case "Medications page":
                return ("Review or renew medications", "Check another part of the care account")
            default:
                return ("Find the main medical task on this page", "Check appointments, results, or messages")
            }
        case .banking:
            switch pageType {
            case "Verification page":
                return ("Complete a security verification step", "Confirm you are on the expected sign-in path")
            case "Sign-in page":
                return ("Sign in securely", "Recover account access without using the wrong link")
            case "Bill-pay page":
                return ("Pay a bill", "Review payment details before confirming")
            case "Transfer page":
                return ("Move money between accounts", "Check balances and account names first")
            default:
                return ("Find the safest banking entry point", "Review balances, payments, or transfers")
            }
        case .governmentBenefits:
            switch pageType {
            case "Sign-in page":
                return ("Sign in to a benefits or service account", "Create or recover account access")
            case "Application form":
                return ("Continue an application", "Review the current form step before submitting")
            case "Document upload page":
                return ("Upload the requested document", "Check which file or form is needed first")
            case "Status page":
                return ("Check application or benefits status", "Review the next step requested by the service")
            default:
                return ("Find the main benefits task on this page", "Sign in, apply, upload documents, or check status")
            }
        case .caregiverProxy:
            return ("Confirm whose account or profile is active", "Switch to the correct family member or proxy view")
        case .general:
            switch pageType {
            case "Home page / navigation hub", "Menu-heavy directory or portal page":
                return ("Choose the most relevant section to open first", "Ignore lower-value navigation until the main path is clear")
            case "Information / guide page":
                return ("Understand the main information on this page", "Open the most relevant next link or resource")
            case "Application form":
                return ("Continue the form safely", "Check what information is needed next")
            case "Status / account summary page":
                return ("Review the main status or summary first", "Find the next useful detail or section")
            case "Action page":
                return ("Find the safest action to start with", "Read the main instruction before continuing")
            default:
                return ("Understand the main task on this screen", "Identify the safest place to start")
            }
        }
    }

    private func fallbackSafeFirstStep(for context: OwlGuideScenarioContext) -> String {
        switch context.selectedSkill {
        case .medicalPortal:
            if ["Home page / navigation hub", "Menu-heavy directory or portal page"].contains(context.likelyPageType) {
                return "Start with the main patient-facing section before opening smaller navigation links."
            }
            if context.likelyPageType == "Information / guide page" {
                return "Start with the main information or patient resources area before opening smaller links."
            }
            if context.likelyPageType == "Medical services page" {
                return "Start with the main service overview or patient resources area before using smaller links."
            }
            if context.likelyPageType == "Wait-times page" {
                return "Start by reading the current wait-time area before choosing another hospital or care option."
            }
            return "Start with the main medical account area and avoid secondary links until the page purpose is clear."
        case .banking:
            return "Start with the main sign-in or account area and avoid side links until the primary task is clear."
        case .governmentBenefits:
            return "Start by finding the main sign-in, application, or status area before reviewing smaller page details."
        case .caregiverProxy:
            return "Start by confirming whose profile or account is active before doing anything else."
        case .general:
            return "Start by reviewing the main visible content area before choosing a button or link."
        }
    }

    private func clarificationQuestion(for context: OwlGuideScenarioContext) -> String? {
        if context.userRequest?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return nil
        }

        switch context.selectedSkill {
        case .medicalPortal:
            if ["Home page / navigation hub", "Menu-heavy directory or portal page"].contains(context.likelyPageType) {
                return "Are you trying to find patient resources, learn about services, or access something specific?"
            }
            if context.likelyPageType == "Information / guide page" {
                return "Do you want help understanding this information page, or finding the best next link to open?"
            }
            if context.likelyPageType == "Medical services page" {
                return "Are you trying to learn about the service, find patient resources, or access your medical images?"
            }
            if context.likelyPageType == "Wait-times page" {
                return "Are you comparing wait times, or are you looking for one hospital's current status?"
            }
            return "Do you want help understanding this page, or finding the safest next step?"
        case .banking:
            return "Are you trying to sign in, pay a bill, or move money?"
        case .governmentBenefits:
            return "Are you trying to sign in, continue an application, or check your status?"
        case .caregiverProxy:
            return "Is this task for you or for a family member?"
        case .general:
            return "Do you want help understanding this page, or finding the safest next step?"
        }
    }

    private func generalIntentOptions(for context: OwlGuideScenarioContext) -> [OwlGuideUserIntent] {
        switch context.likelyPageType {
        case "Home page / navigation hub", "Menu-heavy directory or portal page":
            return [.findResources, .understandPage, .checkStatus]
        case "Information / guide page":
            return [.understandPage, .findResources, .accessMedicalImages]
        case "Medical services page":
            return [.understandPage, .findResources, .accessMedicalImages]
        case "Sign-in page":
            return [.signIn, .recoverAccount, .understandPage]
        case "Status page", "Status / account summary page":
            return [.checkStatus, .understandPage, .signIn]
        case "Application form", "Document upload page":
            return [.continueApplication, .understandPage, .checkStatus]
        case "Proxy / profile page":
            return [.confirmProfile, .understandPage, .signIn]
        default:
            return [.understandPage, .checkStatus, .signIn]
        }
    }

    private func intentSummary(for intent: OwlGuideUserIntent, in context: OwlGuideScenarioContext) -> String {
        switch intent {
        case .signIn:
            return "Use the main account entry point for this \(context.likelyPageType.lowercased())."
        case .recoverAccount:
            return "Look for the safe account-recovery path instead of the main submit action."
        case .bookAppointment:
            return "Look for scheduling or booking controls first."
        case .checkResults:
            return "Look for result, status, or update content before taking action."
        case .sendMessage:
            return "Open the message or contact area before deciding what to send."
        case .payBill:
            return "Review billing details before any payment confirmation."
        case .learnServices:
            return "Start with the main service overview or category area first."
        case .findResources:
            return "Look for patient resources, preparation, or instructions first."
        case .accessMedicalImages:
            return "Look for the image-access entry point before using smaller links."
        case .findDoctor:
            return "Compare the main care or wait-time options before choosing."
        case .continueApplication:
            return "Find the next safe form or upload step."
        case .checkStatus:
            return "Look for the current status or account summary first."
        case .confirmProfile:
            return "Confirm the correct person or profile before continuing."
        case .understandPage:
            return "Orient yourself on the page before choosing a button or form."
        }
    }

    private func buildGuidedStep(
        for context: OwlGuideScenarioContext,
        result: ScreenUnderstandingResult,
        intent: OwlGuideUserIntent,
        isConfirmed: Bool
    ) -> OwlGuideGuidedStep {
        let target = result.recommendedTargets.first
        let targetLabel = target.map { trimmed($0.label, limit: 48) }

        let nextStep: String
        if let targetLabel {
            switch intent {
            case .signIn:
                nextStep = "Start by opening or reviewing \"\(targetLabel)\" before entering account information."
            case .recoverAccount:
                nextStep = "Start with \"\(targetLabel)\" and follow the recovery path instead of the standard sign-in path."
            case .bookAppointment:
                nextStep = "Start with \"\(targetLabel)\" to find the safest scheduling path."
            case .checkResults:
                nextStep = "Start with \"\(targetLabel)\" to review the main result area first."
            case .sendMessage:
                nextStep = "Start with \"\(targetLabel)\" to reach the message area before taking other actions."
            case .payBill:
                nextStep = "Start with \"\(targetLabel)\" and review the billing details before confirming anything."
            case .learnServices:
                nextStep = "Start with \"\(targetLabel)\" to understand the main service options before using smaller links."
            case .findResources:
                nextStep = "Start with \"\(targetLabel)\" to review the patient resources or instructions first."
            case .accessMedicalImages:
                nextStep = "Start with \"\(targetLabel)\" to reach the safest medical-image access path."
            case .findDoctor:
                nextStep = "Start with \"\(targetLabel)\" to compare care or provider options first."
            case .continueApplication:
                nextStep = "Start with \"\(targetLabel)\" to find the next safe form step."
            case .checkStatus:
                nextStep = "Start with \"\(targetLabel)\" to confirm the current status before choosing another action."
            case .confirmProfile:
                nextStep = "Start with \"\(targetLabel)\" so you can confirm the correct person or account view."
            case .understandPage:
                nextStep = "Start with \"\(targetLabel)\" to orient yourself before taking the next action."
            }
        } else {
            nextStep = fallbackGuidedStep(for: intent, in: context)
        }

        return OwlGuideGuidedStep(
            title: isConfirmed ? "Guided Step" : "Tentative Next Step",
            nextStep: nextStep,
            safetyNote: safetyNote(for: context.selectedSkill, intent: intent),
            clarificationQuestion: isConfirmed ? nil : clarificationQuestion(for: context),
            grounding: OwlGuideGuidedStepGrounding(
                primaryTargetLocalElementID: result.recommendedTargets.first?.relatedLocalElement.nilIfBlank,
                fallbackTargetLocalElementID: result.recommendedTargets.dropFirst().first?.relatedLocalElement.nilIfBlank,
                status: .textOnlyFallback,
                origin: .unknown,
                targetType: nil,
                reason: "Owl Guide has not resolved this next step to a trustworthy local target yet.",
                confidenceNote: "Owl Guide will only draw a strong highlight when it can ground the next step to a stable local target.",
                downgradeReason: "The guided step still needs grounded local resolution before a reliable on-screen highlight can be shown."
            )
        )
    }

    private func fallbackGuidedStep(for intent: OwlGuideUserIntent, in context: OwlGuideScenarioContext) -> String {
        switch intent {
        case .signIn:
            return "Start with the main sign-in area and avoid smaller side links until the path is clear."
        case .recoverAccount:
            return "Look for the account-recovery path before using the regular sign-in fields."
        case .bookAppointment:
            return "Find the main scheduling or appointment area before choosing a date or provider."
        case .checkResults:
            return "Start with the main information area before opening secondary links."
        case .sendMessage:
            return "Look for the message or contact area before entering details."
        case .payBill:
            return "Find the main billing area first and review the amount and account before confirming."
        case .learnServices:
            return "Start with the main service overview or category area before choosing a smaller link."
        case .findResources:
            return "Look for the patient resources or preparation area before opening secondary links."
        case .accessMedicalImages:
            return "Look for the access-medical-images or portal entry point before opening other links."
        case .findDoctor:
            if context.likelyPageType == "Wait-times page" {
                return "Read the current wait-time or care options first before choosing a location."
            }
            return "Look for the main provider or care-options area before choosing a next action."
        case .continueApplication:
            return "Find the next visible form or upload step before trying to submit anything."
        case .checkStatus:
            return "Look for the current status, summary, or dashboard area first."
        case .confirmProfile:
            return "Confirm whose profile or account is active before continuing."
        case .understandPage:
            return "Start by reviewing the main visible content area before choosing a button or link."
        }
    }

    private func safetyNote(for skill: OwlGuideScenarioSkill, intent: OwlGuideUserIntent) -> String? {
        switch skill {
        case .medicalPortal:
            if intent == .findDoctor || intent == .checkResults || intent == .bookAppointment || intent == .accessMedicalImages {
                return "Owl Guide can help with navigation, but it is not medical advice."
            }
            return "Use caution before sending medical messages or changing care details."
        case .banking:
            return "Review the account, amount, and payee before confirming anything financial."
        case .governmentBenefits:
            return "Review the current step before uploading documents or submitting information."
        case .caregiverProxy:
            return "Confirm the correct person or account before making any changes."
        case .general:
            return nil
        }
    }

    private func isIntentCompatible(_ intent: OwlGuideUserIntent, with context: OwlGuideScenarioContext) -> Bool {
        switch intent {
        case .signIn:
            return ["Sign-in page", "Verification page"].contains(context.likelyPageType)
        case .recoverAccount:
            return ["Sign-in page", "Verification page"].contains(context.likelyPageType)
        case .bookAppointment:
            return ["Appointments page", "Dashboard", "Medical page", "Action page"].contains(context.likelyPageType)
        case .checkResults:
            return ["Results page", "Dashboard", "Medical page", "Status / account summary page"].contains(context.likelyPageType)
        case .sendMessage:
            return ["Messages page", "Dashboard", "Medical page"].contains(context.likelyPageType)
        case .payBill:
            return ["Bill-pay page", "Finance page", "Action page"].contains(context.likelyPageType)
        case .learnServices:
            return ["Medical services page", "Medical page", "Information / guide page", "Home page / navigation hub", "Menu-heavy directory or portal page"].contains(context.likelyPageType)
        case .findResources:
            return ["Medical services page", "Medical page", "Results page", "Information / guide page", "Home page / navigation hub", "Menu-heavy directory or portal page"].contains(context.likelyPageType)
        case .accessMedicalImages:
            return ["Medical services page", "Medical page", "Results page", "Information / guide page", "Home page / navigation hub", "Menu-heavy directory or portal page", "Action page"].contains(context.likelyPageType)
        case .findDoctor:
            return ["Wait-times page", "Appointments page", "Medical page", "Home page / navigation hub", "Menu-heavy directory or portal page"].contains(context.likelyPageType)
        case .continueApplication:
            return ["Application form", "Document upload page", "Benefits page", "Action page"].contains(context.likelyPageType)
        case .checkStatus:
            return ["Status page", "Status / account summary page", "Dashboard", "Benefits page", "Medical page", "Finance page"].contains(context.likelyPageType)
        case .confirmProfile:
            return ["Proxy / profile page", "Caregiver / proxy page"].contains(context.likelyPageType)
        case .understandPage:
            return true
        }
    }

    private func hasCompatibleNextStep(
        for intent: OwlGuideUserIntent,
        context: OwlGuideScenarioContext,
        result: ScreenUnderstandingResult
    ) -> Bool {
        if intent == .understandPage {
            return true
        }

        guard let target = result.recommendedTargets.first else {
            return false
        }

        let normalizedLabel = target.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedLabel.isEmpty {
            return false
        }

        let genericLabels: Set<String> = ["button", "link", "text", "page", "screen", "area"]
        if genericLabels.contains(normalizedLabel) {
            return false
        }

        return isIntentCompatible(intent, with: context)
    }

    private func flowName(for intent: OwlGuideUserIntent) -> String {
        switch intent {
        case .signIn:
            return "sign-in flow"
        case .recoverAccount:
            return "account recovery flow"
        case .bookAppointment:
            return "appointment flow"
        case .checkResults:
            return "results flow"
        case .sendMessage:
            return "message flow"
        case .payBill:
            return "payment flow"
        case .learnServices:
            return "service-information flow"
        case .findResources:
            return "patient-resources flow"
        case .accessMedicalImages:
            return "medical-image access flow"
        case .findDoctor:
            return "care-selection flow"
        case .continueApplication:
            return "application flow"
        case .checkStatus:
            return "status-check flow"
        case .confirmProfile:
            return "profile-confirmation flow"
        case .understandPage:
            return "page-understanding flow"
        }
    }

    private func contextRecognition(for context: OwlGuideScenarioContext) -> String {
        switch context.confidence {
        case .high:
            return highConfidenceRecognition(for: context)
        case .medium:
            return mediumConfidenceRecognition(for: context)
        case .low:
            return lowConfidenceRecognition(for: context)
        }
    }

    private func highConfidenceRecognition(for context: OwlGuideScenarioContext) -> String {
        let hostText = context.browserHostname.map { " on \($0)" } ?? ""

        switch context.selectedSkill {
        case .medicalPortal:
            return "This looks like a medical or hospital page\(hostText). It appears to be a \(context.likelyPageType.lowercased())."
        case .banking:
            return "This looks like a banking or payment page\(hostText). It appears to be a \(context.likelyPageType.lowercased())."
        case .governmentBenefits:
            return "This looks like a government benefits or service page\(hostText). It appears to be a \(context.likelyPageType.lowercased())."
        case .caregiverProxy:
            return "This looks like a page about helping yourself or another person\(hostText). It appears to be a \(context.likelyPageType.lowercased())."
        case .general:
            return "This looks like a \(context.likelyPageType.lowercased()) in \(context.appName)."
        }
    }

    private func mediumConfidenceRecognition(for context: OwlGuideScenarioContext) -> String {
        switch context.selectedSkill {
        case .medicalPortal:
            return "This may be a medical or hospital page. It looks more like a \(context.likelyPageType.lowercased()) than a general page."
        case .banking:
            return "This may be a banking or payment page. It looks more like a \(context.likelyPageType.lowercased()) than a general page."
        case .governmentBenefits:
            return "This may be a government or benefits page. It looks more like a \(context.likelyPageType.lowercased()) than a general page."
        case .caregiverProxy:
            return "This may be a page about helping yourself or another person. It looks more like a \(context.likelyPageType.lowercased()) than a general page."
        case .general:
            return "This looks like a \(context.likelyPageType.lowercased()) in \(context.appName)."
        }
    }

    private func lowConfidenceRecognition(for context: OwlGuideScenarioContext) -> String {
        switch context.likelyPageType {
        case "Sign-in page":
            return "This looks like a webpage with sign-in or navigation options."
        case "Verification page":
            return "This looks like a page asking for sign-in or verification information."
        case "Wait-times page":
            return "This looks like a webpage showing wait-time or status information."
        case "Dashboard":
            return "I can see an account-style page, but I’m not fully sure what kind of site it is yet."
        case "Application form":
            return "This looks like a form page with fields or next-step options."
        case "Document upload page":
            return "This looks like a page for choosing or uploading documents."
        case "Status page":
            return "This looks like a page showing account or status information."
        case "Proxy / profile page":
            return "This looks like a page for choosing a profile or account view."
        default:
            if context.browserHostname != nil {
                return "I can see a webpage with account or navigation options, but I’m not fully sure what kind of site it is yet."
            }

            return "I can see a page with account or navigation options, but I’m not fully sure what kind of site it is yet."
        }
    }

    private func containsAny(in textCorpus: String, keywords: [String]) -> Bool {
        keywords.contains { textCorpus.contains($0) }
    }

    private func weightedMatchScore(in textCorpus: String, keywords: [String], weight: Int) -> Int {
        guard weight > 0 else {
            return 0
        }

        return keywords.reduce(into: 0) { total, keyword in
            if textCorpus.contains(keyword) {
                total += weight
            }
        }
    }

    private func trimmed(_ value: String, limit: Int) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else {
            return collapsed
        }
        return String(collapsed.prefix(limit - 1)) + "…"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
