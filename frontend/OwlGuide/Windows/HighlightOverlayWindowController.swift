import AppKit
import SwiftUI

private final class TransparentOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct HighlightOverlayRenderOutcome {
    let overlayVisible: Bool
    let anchorVisible: Bool
}

struct HighlightOverlayItemLayout: Identifiable {
    let id = UUID()
    let rank: Int
    let label: String
    let caption: String
    let localRect: CGRect
    let captionRect: CGRect?
    let style: OverlayPreviewStyle
}

struct HighlightOverlayReminderCardLayout {
    let statusLabel: String
    let title: String
    let message: String
    let detail: String?
    let frame: CGRect
    let progressCurrentStep: Int?
    let progressTotalSteps: Int?
    let emphasis: OverlayReminderEmphasis
    /// Human-readable label for the action button, e.g. "Click" or "Type"
    let actionLabel: String?
    /// If the action is typing, this holds the full text to be input for preview.
    let actionInputPreview: String?
    /// Callback to execute the proposed action. When non-nil, the card shows an action button.
    let onExecuteAction: (() -> Void)?
}

private struct HighlightReminderPlacementCache {
    let targetWindowFrame: CGRect
    let screenFrame: CGRect
    let highlightRects: [CGRect]
    let placementIndex: Int

    func matches(targetWindowFrame: CGRect, screenFrame: CGRect, highlightRects: [CGRect]) -> Bool {
        guard self.highlightRects.count == highlightRects.count else {
            return false
        }
        
        let rectsMatch = zip(self.highlightRects, highlightRects).allSatisfy { lhs, rhs in
            framesAreClose(lhs, rhs, tolerance: 10)
        }
        
        return rectsMatch
            && framesAreClose(self.targetWindowFrame, targetWindowFrame, tolerance: 24)
            && framesAreClose(self.screenFrame, screenFrame, tolerance: 2)
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}

@MainActor
final class HighlightOverlayWindowController: NSWindowController {
    private var overlayPanel: TransparentOverlayPanel?
    private var reminderPlacementCache: HighlightReminderPlacementCache?

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    convenience init() {
        let initialFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Ensure the panel leverages `makePanel` so it gets `.screenSaver` level,
        // `isFloatingPanel`, and proper `collectionBehavior` for mission control.
        self.init(window: nil)
        let panel = makePanel(frame: initialFrame)
        self.window = panel
        self.overlayPanel = panel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        reminderCard: RelayReminderCard?,
        items: [OverlayPreviewItem],
        anchorFrame: CGRect?,
        showsOverlay: Bool,
        showsAnchor: Bool
    ) -> HighlightOverlayRenderOutcome {
        guard let desktopFrame = desktopFrame() else {
            hide()
            return HighlightOverlayRenderOutcome(overlayVisible: false, anchorVisible: false)
        }

        let screen = targetScreen(
            for: items,
            reminderCard: reminderCard,
            anchorFrame: anchorFrame,
            within: desktopFrame
        ) ?? NSScreen.main ?? NSScreen.screens.first
        let panelFrame = screen?.frame ?? CGRect(origin: .zero, size: CGSize(width: 1440, height: 900))

        let localHighlights: [HighlightOverlayItemLayout] = showsOverlay ? items.compactMap { item in
            guard let screen else {
                return nil
            }

            return localHighlight(for: item, on: screen, desktopFrame: desktopFrame)
        } : []
        let anchorHighlight = showsAnchor ? screen.flatMap { localAnchorHighlight(for: anchorFrame, on: $0, desktopFrame: desktopFrame) } : nil
        var avoidingRects = localHighlights.map(\.localRect)
        if let anchorFrame, let screen {
            if let targetRect = localAnchorHighlight(for: anchorFrame, on: screen, desktopFrame: desktopFrame) {
                avoidingRects.append(targetRect.insetBy(dx: -40, dy: -40))
            }
        }

        let reminderCardLayout = localReminderCard(
            for: reminderCard,
            on: screen,
            desktopFrame: desktopFrame,
            avoiding: avoidingRects
        )
        let overlaySize = panelFrame.size
        let resolvedHighlights: [HighlightOverlayItemLayout] = showsOverlay
            ? resolvedCaptionLayout(for: localHighlights, overlaySize: overlaySize)
            : []
        let overlayVisible = showsOverlay && !resolvedHighlights.isEmpty
        let anchorVisible = showsAnchor && anchorHighlight != nil

        guard overlayVisible || anchorVisible || reminderCardLayout != nil else {
            hide()
            return HighlightOverlayRenderOutcome(overlayVisible: false, anchorVisible: false)
        }

        let panel = overlayPanel ?? makePanel(frame: panelFrame)
        overlayPanel = panel
        window = panel
        panel.setFrame(panelFrame, display: true)
        panel.contentView = NSHostingView(
            rootView: HighlightOverlayView(
                reminderCard: reminderCardLayout,
                anchor: anchorHighlight,
                highlights: resolvedHighlights,
                overlaySize: overlaySize
            )
            .environment(\.colorScheme, .light)
        )
        // If the card has an action button, the panel must accept mouse events
        // so the user can tap "Perform Action". Otherwise remain fully click-through.
        let cardIsInteractive = reminderCardLayout?.onExecuteAction != nil
        panel.ignoresMouseEvents = !cardIsInteractive
        panel.orderFrontRegardless()
        return HighlightOverlayRenderOutcome(overlayVisible: overlayVisible, anchorVisible: anchorVisible)
    }

    func hide() {
        overlayPanel?.orderOut(nil)
    }

    private func makePanel(frame: CGRect) -> TransparentOverlayPanel {
        let panel = TransparentOverlayPanel(
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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

        return NSScreen.screens.first(where: { globalWindowFrame.intersects($0.frame) })
    }

    private func localHighlight(
        for item: OverlayPreviewItem,
        on screen: NSScreen,
        desktopFrame: CGRect
    ) -> HighlightOverlayItemLayout? {
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

        return HighlightOverlayItemLayout(
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
        guard clippedGlobalRect.width >= 4, clippedGlobalRect.height >= 4 else {
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
        on screen: NSScreen?,
        desktopFrame: CGRect,
        avoiding highlightRects: [CGRect]
    ) -> HighlightOverlayReminderCardLayout? {
        guard let reminderCard else {
            return nil
        }

        if let screen,
           let localTargetWindowFrame = localAnchorHighlight(
            for: reminderCard.targetWindowFrame,
            on: screen,
            desktopFrame: desktopFrame
           ) {
            return positionedReminderCardLayout(
                reminderCard: reminderCard,
                localTargetWindowFrame: localTargetWindowFrame,
                screen: screen,
                avoiding: highlightRects
            )
        }

        let fallbackVisibleFrame = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? desktopFrame.insetBy(dx: 24, dy: 24)

        let fallbackWidth = min(max(fallbackVisibleFrame.width * 0.28, 320), 360)
        let fallbackHeight = estimatedReminderCardSize(
            title: reminderCard.title,
            message: reminderCard.message,
            detail: reminderCard.detail,
            actionInputPreview: actionInputPreviewText(for: reminderCard),
            hasActionButton: reminderCard.onExecuteAction != nil,
            width: fallbackWidth
        ).height
        let fallbackFrame = CGRect(
            x: max(fallbackVisibleFrame.maxX - fallbackWidth - 24 - fallbackVisibleFrame.minX, 24),
            y: max(fallbackVisibleFrame.maxY - fallbackHeight - 24 - fallbackVisibleFrame.minY, 24),
            width: fallbackWidth,
            height: fallbackHeight
        )

        return HighlightOverlayReminderCardLayout(
            statusLabel: reminderCard.statusLabel,
            title: reminderCard.title,
            message: reminderCard.message,
            detail: reminderCard.detail,
            frame: fallbackFrame,
            progressCurrentStep: reminderCard.progressCurrentStep,
            progressTotalSteps: reminderCard.progressTotalSteps,
            emphasis: reminderCard.emphasis,
            actionLabel: actionLabel(for: reminderCard),
            actionInputPreview: actionInputPreviewText(for: reminderCard),
            onExecuteAction: reminderCard.onExecuteAction
        )
    }

    private func positionedReminderCardLayout(
        reminderCard: RelayReminderCard,
        localTargetWindowFrame: CGRect,
        screen: NSScreen,
        avoiding highlightRects: [CGRect]
    ) -> HighlightOverlayReminderCardLayout {
        
        let availableWidth = max(min(localTargetWindowFrame.width - 40, 388), 320)
        let actionInputPreview = actionInputPreviewText(for: reminderCard)
        let size = estimatedReminderCardSize(
            title: reminderCard.title,
            message: reminderCard.message,
            detail: reminderCard.detail,
            actionInputPreview: actionInputPreview,
            hasActionButton: reminderCard.onExecuteAction != nil,
            width: availableWidth
        )

        let toolbarInset = min(max(localTargetWindowFrame.height * 0.1, 54), 84)
        let padding: CGFloat = 18
        let candidateOrigins = [
            // Top Right
            CGPoint(
                x: localTargetWindowFrame.maxX - size.width - padding,
                y: localTargetWindowFrame.minY + toolbarInset
            ),
            // Top Left
            CGPoint(
                x: localTargetWindowFrame.minX + padding,
                y: localTargetWindowFrame.minY + toolbarInset
            ),
            // Top Right (lower)
            CGPoint(
                x: localTargetWindowFrame.maxX - size.width - padding,
                y: localTargetWindowFrame.minY + toolbarInset + 82
            ),
            // Bottom Right
            CGPoint(
                x: localTargetWindowFrame.maxX - size.width - padding,
                y: localTargetWindowFrame.maxY - size.height - padding
            ),
            // Bottom Left
            CGPoint(
                x: localTargetWindowFrame.minX + padding,
                y: localTargetWindowFrame.maxY - size.height - padding
            ),
            // Middle Right
            CGPoint(
                x: localTargetWindowFrame.maxX - size.width - padding,
                y: localTargetWindowFrame.midY - size.height / 2
            ),
            // Middle Left
            CGPoint(
                x: localTargetWindowFrame.minX + padding,
                y: localTargetWindowFrame.midY - size.height / 2
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
            screenFrame: screenSignature,
            highlightRects: highlightRects
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

            reminderPlacementCache = HighlightReminderPlacementCache(
                targetWindowFrame: targetSignature,
                screenFrame: screenSignature,
                highlightRects: highlightRects,
                placementIndex: chosenEntry.2
            )
        }

        return HighlightOverlayReminderCardLayout(
            statusLabel: reminderCard.statusLabel,
            title: reminderCard.title,
            message: reminderCard.message,
            detail: reminderCard.detail,
            frame: chosenEntry.0,
            progressCurrentStep: reminderCard.progressCurrentStep,
            progressTotalSteps: reminderCard.progressTotalSteps,
            emphasis: reminderCard.emphasis,
            actionLabel: actionLabel(for: reminderCard),
            actionInputPreview: actionInputPreviewText(for: reminderCard),
            onExecuteAction: reminderCard.onExecuteAction
        )
    }

    private func estimatedReminderCardSize(title: String, message: String, detail: String?, actionInputPreview: String?, hasActionButton: Bool, width: CGFloat) -> CGSize {
        let titleHeight = measuredTextHeight(
            title,
            font: .systemFont(ofSize: 21, weight: .semibold),
            width: width - 32
        )
        let messageHeight = measuredTextHeight(
            message,
            font: .systemFont(ofSize: 17, weight: .regular),
            width: width - 32
        )
        let detailHeight = detail.map {
            measuredTextHeight(
                $0,
                font: .systemFont(ofSize: 16, weight: .regular),
                width: width - 32
            )
        } ?? 0
        let previewHeight = actionInputPreview.map {
            measuredTextHeight(
                $0,
                font: .systemFont(ofSize: 15, weight: .regular),
                width: width - 56
            ) + 26 // Include vertical padding for preview box
        } ?? 0
        let actionButtonHeight: CGFloat = hasActionButton ? 60 : 0

        let totalHeight = 28 + 28 + titleHeight + 10 + messageHeight + (detail == nil ? 0 : 10 + detailHeight) + (actionInputPreview == nil ? 0 : 12 + previewHeight) + actionButtonHeight + 22
        return CGSize(width: width, height: min(max(totalHeight, 148), hasActionButton ? 560 : 460))
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

    private func resolvedCaptionLayout(
        for highlights: [HighlightOverlayItemLayout],
        overlaySize: CGSize
    ) -> [HighlightOverlayItemLayout] {
        var occupiedCaptionRects: [CGRect] = []
        var resolvedHighlights: [HighlightOverlayItemLayout] = []

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
                HighlightOverlayItemLayout(
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
        for highlight: HighlightOverlayItemLayout,
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
        return CGRect(
            x: axRect.minX,
            y: desktopFrame.maxY - axRect.maxY,
            width: axRect.width,
            height: axRect.height
        )
    }

    /// Generate a human-readable action label for the card button.
    private func actionLabel(for card: RelayReminderCard) -> String? {
        guard card.onExecuteAction != nil,
              let actionType = card.proposedActionType?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !actionType.isEmpty,
              actionType != "none"
        else {
            return nil
        }

        switch actionType {
        case "type":
            return "Type"
        case "click":
            return "Click"
        default:
            return "Perform Action"
        }
    }

    private func actionInputPreviewText(for card: RelayReminderCard) -> String? {
        guard card.onExecuteAction != nil,
              let actionType = card.proposedActionType?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              actionType == "type",
              let value = card.proposedActionValue,
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
