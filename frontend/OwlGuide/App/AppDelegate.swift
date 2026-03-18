import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = AppViewModel()
    private var floatingPanelController: FloatingPanelController?
    private var inspectorWindowController: InspectorWindowController?
    private var highlightWindow: NSWindowController?
    private var highlightOverlayWindowController: HighlightOverlayWindowController?
    private let arrowGuideController = ArrowGuideController()
    private var overlayValidationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var activationObserver: NSObjectProtocol?
    private var workspaceActivationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let floatingPanelController = FloatingPanelController(viewModel: viewModel)
        let inspectorWindowController = InspectorWindowController(viewModel: viewModel)
        let highlightOverlayWindowController = HighlightOverlayWindowController()

        self.floatingPanelController = floatingPanelController
        self.inspectorWindowController = inspectorWindowController
        self.highlightWindow = highlightOverlayWindowController
        self.highlightOverlayWindowController = highlightOverlayWindowController
        viewModel.prepareForFreshAnalysis = { [weak self] in
            self?.highlightOverlayWindowController?.hide()
            self?.arrowGuideController.hide()
        }

        viewModel.$isInspectorPresented
            .removeDuplicates()
            .sink { [weak self, weak inspectorWindowController] isPresented in
                DispatchQueue.main.async {
                    if isPresented {
                        self?.viewModel.refreshPermissionStatus()
                        self?.viewModel.refreshScreenUnderstandingReadiness()
                        inspectorWindowController?.showWindow(nil)
                        inspectorWindowController?.window?.orderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    } else {
                        inspectorWindowController?.window?.orderOut(nil)
                    }
                }
            }
            .store(in: &cancellables)

        viewModel.$overlayPresentationRequest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                self?.refreshOverlayPresentation(using: request)
            }
            .store(in: &cancellables)

        // HACKATHON: Independent arrow guide — directly observes groundedTargetBounds,
        // bypassing the entire HighlightOverlayWindowController safety pipeline.
        viewModel.$groundedTargetBounds
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bounds in
                guard let self else { return }
                if let bounds {
                    let message = self.viewModel.guidedStepNextStepText ?? "点击这里继续"
                    self.arrowGuideController.show(targetRectInScreen: bounds, message: message)
                } else {
                    self.arrowGuideController.hide()
                }
            }
            .store(in: &cancellables)

        // Arrow hides when the guided step card is dismissed
        viewModel.$guidedStepResponse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] step in
                if step == nil {
                    self?.arrowGuideController.hide()
                }
            }
            .store(in: &cancellables)

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.viewModel.refreshPermissionStatus()
                self?.viewModel.refreshScreenUnderstandingReadiness()
            }
        }

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor [weak self] in
                self?.viewModel.noteActivatedApplication(application)
            }
        }

        viewModel.refreshPermissionStatus()
        viewModel.refreshCurrentFrontmostAppDebugInfo()
        viewModel.captureExternalTarget()
        viewModel.refreshScreenUnderstandingReadiness()
        floatingPanelController.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        highlightOverlayWindowController?.hide()
        stopOverlayValidationTimer()

        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }

        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
    }

    private func refreshOverlayPresentation(using request: OverlayPresentationRequest) {
        guard let highlightOverlayWindowController else {
            return
        }

        guard request.showsOverlay || request.showsAnchor || request.reminderCard != nil else {
            highlightOverlayWindowController.hide()
            arrowGuideController.hide() // Sync: arrow disappears with the overlay/card
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.applyOverlayPresentationResult(overlayVisible: false, anchorVisible: false)
            }
            stopOverlayValidationTimer()
            return
        }

        let outcome = highlightOverlayWindowController.show(
            reminderCard: request.reminderCard,
            items: request.overlayItems,
            anchorFrame: request.anchorFrame,
            showsOverlay: request.showsOverlay,
            showsAnchor: request.showsAnchor
        )
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.applyOverlayPresentationResult(
                overlayVisible: outcome.overlayVisible,
                anchorVisible: outcome.anchorVisible
            )
        }
        configureOverlayValidationTimer(
            shouldRun: outcome.overlayVisible || outcome.anchorVisible || request.reminderCard != nil
        )
    }

    private func configureOverlayValidationTimer(shouldRun: Bool) {
        if shouldRun {
            guard overlayValidationTimer == nil else {
                return
            }

            let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.viewModel.validateRelayPresentationRelevance()
                    self?.viewModel.validateGuidedStepOverlaySafety()
                }
            }
            overlayValidationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            stopOverlayValidationTimer()
        }
    }

    private func stopOverlayValidationTimer() {
        overlayValidationTimer?.invalidate()
        overlayValidationTimer = nil
    }
}

private struct OverlayRenderOutcome {
    let overlayVisible: Bool
    let anchorVisible: Bool
}

@MainActor
private final class OverlayPreviewController {
    private var overlayPanel: NSPanel?
    private var reminderPlacementCache: ReminderPlacementCache?

    func show(
        reminderCard: RelayReminderCard?,
        items: [OverlayPreviewItem],
        anchorFrame: CGRect?,
        showsOverlay: Bool,
        showsAnchor: Bool
    ) -> OverlayRenderOutcome {
        guard let desktopFrame = desktopFrame(),
              let screen = targetScreen(
                for: items,
                reminderCard: reminderCard,
                anchorFrame: anchorFrame,
                within: desktopFrame
              ) else {
            hide()
            return OverlayRenderOutcome(overlayVisible: false, anchorVisible: false)
        }

        let localHighlights = showsOverlay ? items.compactMap { item in
            localHighlight(for: item, on: screen, desktopFrame: desktopFrame)
        } : []
        let anchorHighlight = showsAnchor ? localAnchorHighlight(for: anchorFrame, on: screen, desktopFrame: desktopFrame) : nil
        let reminderCardLayout = localReminderCard(
            for: reminderCard,
            on: screen,
            desktopFrame: desktopFrame,
            avoiding: localHighlights.map(\.localRect)
        )
        let resolvedHighlights = showsOverlay ? resolvedCaptionLayout(for: localHighlights, overlaySize: screen.frame.size) : []
        let overlayVisible = showsOverlay && !resolvedHighlights.isEmpty
        let anchorVisible = showsAnchor && anchorHighlight != nil

        guard overlayVisible || anchorVisible || reminderCardLayout != nil else {
            hide()
            return OverlayRenderOutcome(overlayVisible: false, anchorVisible: false)
        }

        let panel = overlayPanel ?? makePanel(frame: screen.frame)
        overlayPanel = panel
        panel.setFrame(screen.frame, display: true)
        panel.contentView = NSHostingView(
            rootView: OverlayPreviewView(
                reminderCard: reminderCardLayout,
                anchor: anchorHighlight,
                highlights: resolvedHighlights,
                overlaySize: screen.frame.size
            )
            .environment(\.colorScheme, .light)
        )
        panel.orderFrontRegardless()
        return OverlayRenderOutcome(overlayVisible: overlayVisible, anchorVisible: anchorVisible)
    }

    func hide() {
        overlayPanel?.orderOut(nil)
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func desktopFrame() -> CGRect? {
        NSScreen.screens
            .map(\.frame)
            .reduce(nil) { partialResult, frame in
                guard let partialResult else {
                    return frame
                }

                return partialResult.union(frame)
            }
    }

    private func targetScreen(
        for items: [OverlayPreviewItem],
        reminderCard: RelayReminderCard?,
        anchorFrame: CGRect?,
        within desktopFrame: CGRect
    ) -> NSScreen? {
        guard let targetWindowFrame = anchorFrame ?? reminderCard?.targetWindowFrame ?? items.first?.targetWindowFrame else {
            return nil
        }

        let globalWindowFrame = appKitGlobalRect(for: targetWindowFrame, desktopFrame: desktopFrame)

        let midpoint = CGPoint(x: globalWindowFrame.midX, y: globalWindowFrame.midY)
        if let containingScreen = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) {
            return containingScreen
        }

        return NSScreen.screens.first(where: { screen in
            globalWindowFrame.intersects(screen.frame)
        })
    }

    private func localHighlight(
        for item: OverlayPreviewItem,
        on screen: NSScreen,
        desktopFrame: CGRect
    ) -> OverlayHighlight? {
        let globalRect = appKitGlobalRect(for: item.frame, desktopFrame: desktopFrame)
        let clippedGlobalRect = globalRect.intersection(screen.frame)
        guard clippedGlobalRect.width >= 24, clippedGlobalRect.height >= 16 else {
            return nil
        }

        let localRect = CGRect(
            x: clippedGlobalRect.minX - screen.frame.minX,
            y: screen.frame.maxY - clippedGlobalRect.maxY,
            width: clippedGlobalRect.width,
            height: clippedGlobalRect.height
        )

        return OverlayHighlight(
            rank: item.rank,
            label: item.label,
            caption: item.caption,
            localRect: localRect,
            captionRect: nil,
            style: item.style
        )
    }

    private func localAnchorHighlight(
        for anchorFrame: CGRect?,
        on screen: NSScreen,
        desktopFrame: CGRect
    ) -> CGRect? {
        guard let anchorFrame else {
            return nil
        }

        let globalRect = appKitGlobalRect(for: anchorFrame, desktopFrame: desktopFrame)
        let clippedGlobalRect = globalRect.intersection(screen.frame)
        guard clippedGlobalRect.width >= 80, clippedGlobalRect.height >= 80 else {
            return nil
        }

        return CGRect(
            x: clippedGlobalRect.minX - screen.frame.minX,
            y: screen.frame.maxY - clippedGlobalRect.maxY,
            width: clippedGlobalRect.width,
            height: clippedGlobalRect.height
        )
    }

    private func localReminderCard(
        for reminderCard: RelayReminderCard?,
        on screen: NSScreen,
        desktopFrame: CGRect,
        avoiding highlightRects: [CGRect]
    ) -> OverlayReminderCardLayout? {
        guard let reminderCard,
              let localTargetWindowFrame = localAnchorHighlight(
                for: reminderCard.targetWindowFrame,
                on: screen,
                desktopFrame: desktopFrame
              ) else {
            return nil
        }

        let availableWidth = max(min(localTargetWindowFrame.width - 40, 344), 272)
        let size = estimatedReminderCardSize(
            title: reminderCard.title,
            message: reminderCard.message,
            detail: reminderCard.detail,
            width: availableWidth
        )

        let toolbarInset = min(max(localTargetWindowFrame.height * 0.1, 54), 84)
        let padding: CGFloat = 18
        let candidateOrigins = [
            CGPoint(
                x: localTargetWindowFrame.maxX - size.width - padding,
                y: localTargetWindowFrame.minY + toolbarInset
            ),
            CGPoint(
                x: localTargetWindowFrame.minX + padding,
                y: localTargetWindowFrame.minY + toolbarInset
            ),
            CGPoint(
                x: localTargetWindowFrame.maxX - size.width - padding,
                y: localTargetWindowFrame.minY + toolbarInset + 82
            )
        ]

        let titleAvoidanceZone = CGRect(
            x: localTargetWindowFrame.minX + padding,
            y: localTargetWindowFrame.minY + toolbarInset,
            width: min(localTargetWindowFrame.width * 0.48, 360),
            height: 96
        )
        let browserToolbarZone = CGRect(
            x: localTargetWindowFrame.minX,
            y: localTargetWindowFrame.minY,
            width: localTargetWindowFrame.width,
            height: min(toolbarInset + 16, 88)
        )
        let searchAvoidanceZone = CGRect(
            x: localTargetWindowFrame.minX + localTargetWindowFrame.width * 0.2,
            y: localTargetWindowFrame.minY + toolbarInset,
            width: localTargetWindowFrame.width * 0.6,
            height: 74
        )
        let avoidRects = [titleAvoidanceZone, browserToolbarZone, searchAvoidanceZone]
            + highlightRects.map { $0.insetBy(dx: -12, dy: -12) }

        let boundsRect = CGRect(origin: .zero, size: screen.frame.size).insetBy(dx: 12, dy: 12)
        let scoredFrames = candidateOrigins.enumerated().map { index, origin -> (CGRect, CGFloat, Int) in
            let rawFrame = CGRect(origin: origin, size: size)
            let boundedFrame = CGRect(
                x: min(max(rawFrame.minX, boundsRect.minX), boundsRect.maxX - size.width),
                y: min(max(rawFrame.minY, boundsRect.minY), boundsRect.maxY - size.height),
                width: size.width,
                height: size.height
            )
            let overlapPenalty = avoidRects.reduce(CGFloat.zero) { partialResult, avoidRect in
                let overlap = boundedFrame.intersection(avoidRect)
                guard !overlap.isNull else {
                    return partialResult
                }

                return partialResult + (overlap.width * overlap.height)
            }
            let topLeftPenalty = index == 1 ? 28 : 0
            return (boundedFrame, overlapPenalty + CGFloat(topLeftPenalty), index)
        }

        let targetSignature = localTargetWindowFrame.standardized.integral
        let screenSignature = screen.frame.standardized.integral

        let chosenEntry: (CGRect, CGFloat, Int)
        if let reminderPlacementCache,
           reminderPlacementCache.matches(
                targetWindowFrame: targetSignature,
                screenFrame: screenSignature
           ),
           let cachedEntry = scoredFrames.first(where: { $0.2 == reminderPlacementCache.placementIndex }) {
            chosenEntry = cachedEntry
        } else {
            chosenEntry = scoredFrames.min { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.2 < rhs.2
                }

                return lhs.1 < rhs.1
            } ?? (CGRect(origin: candidateOrigins[0], size: size), .zero, 0)

            reminderPlacementCache = ReminderPlacementCache(
                targetWindowFrame: targetSignature,
                screenFrame: screenSignature,
                placementIndex: chosenEntry.2
            )
        }

        return OverlayReminderCardLayout(
            statusLabel: reminderCard.statusLabel,
            title: reminderCard.title,
            message: reminderCard.message,
            detail: reminderCard.detail,
            frame: chosenEntry.0,
            progressCurrentStep: reminderCard.progressCurrentStep,
            progressTotalSteps: reminderCard.progressTotalSteps,
            emphasis: reminderCard.emphasis
        )
    }

    private func estimatedReminderCardSize(title: String, message: String, detail: String?, width: CGFloat) -> CGSize {
        let titleHeight = measuredTextHeight(
            title,
            font: .systemFont(ofSize: 20, weight: .semibold),
            width: width - 36
        )
        let messageHeight = measuredTextHeight(
            message,
            font: .systemFont(ofSize: 17, weight: .medium),
            width: width - 36
        )
        let detailHeight = detail.map {
            measuredTextHeight(
                $0,
                font: .systemFont(ofSize: 14, weight: .regular),
                width: width - 36
            )
        } ?? 0

        let totalHeight = 28 + 28 + titleHeight + 10 + messageHeight + (detail == nil ? 0 : 10 + detailHeight) + 22
        return CGSize(width: width, height: max(totalHeight, 144))
    }

    private func measuredTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        let rect = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height)
    }

    private func resolvedCaptionLayout(for highlights: [OverlayHighlight], overlaySize: CGSize) -> [OverlayHighlight] {
        var occupiedCaptionRects: [CGRect] = []
        var resolvedHighlights: [OverlayHighlight] = []

        for highlight in highlights {
            let captionRect = bestCaptionRect(
                for: highlight,
                overlaySize: overlaySize,
                occupiedCaptionRects: occupiedCaptionRects
            )

            if let captionRect {
                occupiedCaptionRects.append(captionRect)
            }

            resolvedHighlights.append(
                OverlayHighlight(
                    rank: highlight.rank,
                    label: highlight.label,
                    caption: highlight.caption,
                    localRect: highlight.localRect,
                    captionRect: captionRect,
                    style: highlight.style
                )
            )
        }

        return resolvedHighlights
    }

    private func bestCaptionRect(
        for highlight: OverlayHighlight,
        overlaySize: CGSize,
        occupiedCaptionRects: [CGRect]
    ) -> CGRect? {
        let captionSize = estimatedCaptionSize(for: highlight.caption)
        let candidateRects = [
            CGRect(x: highlight.localRect.minX, y: highlight.localRect.maxY + 10, width: captionSize.width, height: captionSize.height),
            CGRect(x: highlight.localRect.minX, y: highlight.localRect.minY - captionSize.height - 10, width: captionSize.width, height: captionSize.height),
            CGRect(x: highlight.localRect.maxX + 10, y: highlight.localRect.minY, width: captionSize.width, height: captionSize.height),
            CGRect(x: highlight.localRect.maxX - captionSize.width, y: highlight.localRect.maxY + 10, width: captionSize.width, height: captionSize.height)
        ]

        for candidate in candidateRects.compactMap({ boundedCaptionRect($0, overlaySize: overlaySize) }) {
            if occupiedCaptionRects.contains(where: { $0.intersects(candidate) }) {
                continue
            }

            return candidate
        }

        return nil
    }

    private func boundedCaptionRect(_ rect: CGRect, overlaySize: CGSize) -> CGRect? {
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        let bounded = CGRect(
            x: max(8, min(rect.minX, overlaySize.width - rect.width - 8)),
            y: max(8, min(rect.minY, overlaySize.height - rect.height - 8)),
            width: rect.width,
            height: rect.height
        )

        guard bounded.minX >= 0,
              bounded.minY >= 0,
              bounded.maxX <= overlaySize.width,
              bounded.maxY <= overlaySize.height else {
            return nil
        }

        return bounded
    }

    private func estimatedCaptionSize(for caption: String) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
        ]
        let measuredSize = (caption as NSString).size(withAttributes: attributes)

        return CGSize(
            width: min(max(measuredSize.width + 22, 84), 240),
            height: 32
        )
    }

    private func appKitGlobalRect(for axRect: CGRect, desktopFrame: CGRect) -> CGRect {
        CGRect(
            x: axRect.minX,
            y: desktopFrame.maxY - axRect.maxY,
            width: axRect.width,
            height: axRect.height
        )
    }
}

private struct ReminderPlacementCache {
    let targetWindowFrame: CGRect
    let screenFrame: CGRect
    let placementIndex: Int

    func matches(targetWindowFrame: CGRect, screenFrame: CGRect) -> Bool {
        framesAreClose(self.targetWindowFrame, targetWindowFrame, tolerance: 24)
            && framesAreClose(self.screenFrame, screenFrame, tolerance: 2)
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}

private struct OverlayHighlight: Identifiable {
    let id = UUID()
    let rank: Int
    let label: String
    let caption: String
    let localRect: CGRect
    let captionRect: CGRect?
    let style: OverlayPreviewStyle
}

private struct OverlayReminderCardLayout {
    let statusLabel: String
    let title: String
    let message: String
    let detail: String?
    let frame: CGRect
    let progressCurrentStep: Int?
    let progressTotalSteps: Int?
    let emphasis: OverlayReminderEmphasis
}

private struct OverlayPreviewView: View {
    let reminderCard: OverlayReminderCardLayout?
    let anchor: CGRect?
    let highlights: [OverlayHighlight]
    let overlaySize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .allowsHitTesting(false)

            if let reminderCard {
                OverlayReminderCardView(card: reminderCard)
                    .frame(width: reminderCard.frame.width, height: reminderCard.frame.height)
                    .position(x: reminderCard.frame.midX, y: reminderCard.frame.midY)
            }

            if let anchor {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Color.yellow.opacity(0.98),
                        style: StrokeStyle(lineWidth: 4, dash: [12, 8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.yellow.opacity(0.035))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.32), lineWidth: 1)
                    )
                    .frame(width: anchor.width, height: anchor.height)
                    .position(x: anchor.midX, y: anchor.midY)
                    .allowsHitTesting(false)
            }

            ForEach(highlights) { highlight in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            highlight.style == .precise ? Color.orange : Color.yellow,
                            style: StrokeStyle(
                                lineWidth: highlight.style == .precise ? 4 : 3,
                                dash: highlight.style == .precise ? [] : [12, 8]
                            )
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill((highlight.style == .precise ? Color.orange : Color.yellow).opacity(highlight.style == .precise ? 0.12 : 0.08))
                        )
                        .frame(width: highlight.localRect.width, height: highlight.localRect.height)

                    Text("\(highlight.rank)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.85))
                        )
                        .offset(x: 10, y: 10)
                }
                .frame(
                    width: highlight.localRect.width,
                    height: highlight.localRect.height,
                    alignment: .topLeading
                )
                .position(
                    x: highlight.localRect.midX,
                    y: highlight.localRect.midY
                )
                .allowsHitTesting(false)
            }

            ForEach(highlights) { highlight in
                if let captionRect = highlight.captionRect {
                    Text(highlight.caption)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.94))
                        )
                        .frame(width: captionRect.width, height: captionRect.height)
                        .position(x: captionRect.midX, y: captionRect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: overlaySize.width, height: overlaySize.height, alignment: .topLeading)
    }
}

private struct OverlayReminderCardView: View {
    let card: OverlayReminderCardLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(card.statusLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusForegroundColor)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(statusBackgroundColor)
                    )

                Spacer(minLength: 0)
            }

            if let progressCurrentStep = card.progressCurrentStep,
               let progressTotalSteps = card.progressTotalSteps,
               progressTotalSteps > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(0..<progressTotalSteps, id: \.self) { index in
                            Capsule(style: .continuous)
                                .fill(index < progressCurrentStep ? progressFillColor : Color.black.opacity(0.08))
                                .frame(maxWidth: .infinity)
                                .frame(height: 6)
                        }
                    }

                    Text("Step \(progressCurrentStep) of \(progressTotalSteps)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }

            Text(card.title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.9))
                .lineLimit(2)
                .lineSpacing(2)

            Text(card.message)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.82))
                .lineLimit(3)
                .lineSpacing(3)

            if let detail = card.detail {
                Text(detail)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.58))
                    .lineLimit(2)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.975))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
    }

    private var statusForegroundColor: Color {
        switch card.emphasis {
        case .loading:
            return Color(red: 0.11, green: 0.31, blue: 0.52)
        case .normal:
            return Color(red: 0.26, green: 0.36, blue: 0.09)
        case .caution:
            return Color(red: 0.47, green: 0.29, blue: 0.04)
        }
    }

    private var statusBackgroundColor: Color {
        switch card.emphasis {
        case .loading:
            return Color(red: 0.86, green: 0.92, blue: 0.99)
        case .normal:
            return Color(red: 0.90, green: 0.96, blue: 0.86)
        case .caution:
            return Color(red: 0.97, green: 0.91, blue: 0.74)
        }
    }

    private var progressFillColor: Color {
        switch card.emphasis {
        case .loading:
            return Color(red: 0.28, green: 0.56, blue: 0.84)
        case .normal:
            return Color(red: 0.43, green: 0.68, blue: 0.28)
        case .caution:
            return Color(red: 0.88, green: 0.67, blue: 0.18)
        }
    }
}
