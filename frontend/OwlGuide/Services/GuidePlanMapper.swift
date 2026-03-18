import Foundation

struct GuidePlanMappingResult {
    let screenUnderstandingResult: ScreenUnderstandingResult
    let guidePlan: GuidePlanViewModel
}

struct GuidePlanMapper {
    func map(_ response: AnalyzeScreenResponse) -> GuidePlanMappingResult {
        let mappedActions = response.actionPlan.map(mapAction)
        let unsupportedActionTypes = mappedActions
            .filter { !$0.isSupportedByFrontend }
            .map(\.kind)
            .filter { $0 == .unsupported }

        let recommendedTargets = makeRecommendedTargets(from: response, mappedActions: mappedActions)
        let cautionNotes = makeCautionNotes(from: response)

        let screenUnderstandingResult = ScreenUnderstandingResult(
            pageSummary: nonEmpty(response.guideCard?.body) ?? nonEmpty(response.context) ?? nonEmpty(response.safeFirstStep) ?? FrontendActionKnowledge.mappedResultFallbackPageSummary,
            likelyUserGoal: nonEmpty(response.guideCard?.title) ?? nonEmpty(response.likelyTask) ?? FrontendActionKnowledge.mappedResultFallbackLikelyTask,
            recommendedTargets: recommendedTargets,
            cautionNotes: cautionNotes
        )

        let guidePlan = GuidePlanViewModel(
            title: nonEmpty(response.guideCard?.title) ?? nonEmpty(response.likelyTask) ?? FrontendActionKnowledge.mappedGuidePlanFallbackTitle,
            body: nonEmpty(response.guideCard?.body) ?? nonEmpty(response.context) ?? nonEmpty(response.safeFirstStep) ?? "",
            primaryActionText: nonEmpty(response.guideCard?.primaryAction) ?? nonEmpty(response.safeFirstStep) ?? "",
            confirmationQuestion: response.confirmationQuestion,
            actions: mappedActions,
            targetLabel: nonEmpty(response.targetInfo?.label),
            targetRect: response.targetInfo?.rect?.cgRect,
            targetKind: nonEmpty(response.targetInfo?.kind),
            targetAccessibilityLabel: nonEmpty(response.targetInfo?.accessibilityLabel),
            confidence: response.meta?.confidence,
            riskLevel: nonEmpty(response.meta?.riskLevel),
            estimatedSteps: response.meta?.estimatedSteps,
            unsupportedActionTypes: Array(Set(unsupportedActionTypes.map(\.rawValue))).sorted()
        )

        return GuidePlanMappingResult(
            screenUnderstandingResult: screenUnderstandingResult,
            guidePlan: guidePlan
        )
    }

    private func makeRecommendedTargets(
        from response: AnalyzeScreenResponse,
        mappedActions: [GuidePlanActionViewModel]
    ) -> [ScreenUnderstandingRecommendedTarget] {
        let targetActions = mappedActions.filter {
            switch $0.kind {
            case .highlight, .click, .fillText:
                return true
            case .speak, .instruction, .unsupported:
                return false
            }
        }

        if targetActions.isEmpty {
            if let label = nonEmpty(response.targetInfo?.label) ?? fallbackTargetLabel(from: response) {
                return [
                    ScreenUnderstandingRecommendedTarget(
                        rank: 1,
                        label: label,
                        whyThisMatters: nonEmpty(response.safeFirstStep) ?? nonEmpty(response.context) ?? "",
                        relatedLocalElement: nonEmpty(response.targetInfo?.localCandidateID) ?? label,
                        intendedAction: nil,
                        actionValue: nil,
                        requiresConfirmation: true,
                        visualBoundingBox: response.targetInfo?.visualBoundingBox
                    )
                ]
            }

            return []
        }

        return targetActions.enumerated().map { index, action in
            ScreenUnderstandingRecommendedTarget(
                rank: index + 1,
                label: action.target ?? nonEmpty(response.targetInfo?.label) ?? "suggested_target_\(index + 1)",
                whyThisMatters: action.text ?? nonEmpty(response.safeFirstStep) ?? "",
                relatedLocalElement: nonEmpty(action.relatedLocalElement)
                    ?? nonEmpty(response.targetInfo?.localCandidateID)
                    ?? action.target
                    ?? nonEmpty(response.targetInfo?.accessibilityLabel)
                    ?? nonEmpty(response.targetInfo?.label)
                    ?? "",
                intendedAction: mappedActionType(action.kind),
                actionValue: action.value,
                requiresConfirmation: action.requiresConfirmation,
                visualBoundingBox: action.visualBoundingBox ?? response.targetInfo?.visualBoundingBox
            )
        }
    }

    private func makeCautionNotes(from response: AnalyzeScreenResponse) -> [String] {
        guard let riskLevel = nonEmpty(response.meta?.riskLevel) else {
            return []
        }

        switch riskLevel.lowercased() {
        case "medium", "high":
            return ["Risk level: \(riskLevel)"]
        default:
            return []
        }
    }

    private func mapAction(_ action: ActionPlanItem) -> GuidePlanActionViewModel {
        let normalizedType = action.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kind: GuidePlanActionKind
        let isSupportedByFrontend: Bool

        switch normalizedType {
        case "highlight":
            kind = .highlight
            isSupportedByFrontend = true
        case FrontendActionKnowledge.clickActionValue:
            kind = .click
            isSupportedByFrontend = true
        case let type where FrontendActionKnowledge.fillAliases.contains(type):
            kind = .fillText
            isSupportedByFrontend = true
        case "speak":
            kind = .speak
            isSupportedByFrontend = true
        case let type where FrontendActionKnowledge.instructionAliases.contains(type):
            kind = .instruction
            isSupportedByFrontend = true
        default:
            kind = .unsupported
            isSupportedByFrontend = false
            print("[GuidePlanMapper] Unsupported action type ignored: \(action.type)")
        }

        return GuidePlanActionViewModel(
            id: action.id,
            kind: kind,
            target: nonEmpty(action.target),
            text: nonEmpty(action.text),
            value: nonEmpty(action.value),
            relatedLocalElement: nonEmpty(action.relatedLocalElement),
            visualBoundingBox: action.visualBoundingBox,
            requiresConfirmation: action.requiresConfirmation,
            isSupportedByFrontend: isSupportedByFrontend
        )
    }

    private func mappedActionType(_ kind: GuidePlanActionKind) -> String? {
        switch kind {
        case .click:
            return FrontendActionKnowledge.clickActionValue
        case .fillText:
            return FrontendActionKnowledge.typeActionValue
        case .highlight, .speak, .instruction, .unsupported:
            return nil
        }
    }

    private func fallbackTargetLabel(from response: AnalyzeScreenResponse) -> String? {
        response.actionPlan
            .compactMap { nonEmpty($0.target) }
            .first
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}
