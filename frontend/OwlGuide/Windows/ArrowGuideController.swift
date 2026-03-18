import AppKit

// MARK: - Standalone Arrow Guide System
// This is a completely independent overlay system that bypasses
// the complex HighlightOverlayWindowController pipeline.
// It directly observes groundedTargetBounds and draws an arrow.

final class ArrowGuideController {
    private var window: ArrowOverlayWindow?

    /// Show a curved arrow pointing to the target element.
    /// `targetRectInScreen` is in CG global coordinates (origin at top-left of primary display).
    func show(targetRectInScreen: CGRect, message: String) {
        guard let screen = screenContaining(rect: targetRectInScreen) else {
//            print("[ArrowGuide] No screen found for rect: \(targetRectInScreen)")
            return
        }

        let arrowWindow = ensureWindow(for: screen)

        // --- Coordinate conversion ---
        // CG coords: origin at top-left of primary display, Y increases downward.
        // AppKit coords: origin at bottom-left of primary display, Y increases upward.
        // NSScreen.frame is already in AppKit coordinates.
        //
        // For conversion: appKitY = primaryScreenHeight - cgY - height
        // where primaryScreenHeight = the height of the screen whose origin.y is 0 in AppKit.
        
        // The primary screen in AppKit has origin (0,0) at bottom-left.
        // Its frame.maxY equals its height in points, which is also the total
        // CG coordinate space height for the primary display.
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        
        let appKitRect = CGRect(
            x: targetRectInScreen.origin.x,
            y: primaryScreenHeight - targetRectInScreen.origin.y - targetRectInScreen.height,
            width: targetRectInScreen.width,
            height: targetRectInScreen.height
        )

        // Convert from global AppKit coordinates to window-local coordinates
        let localRect = CGRect(
            x: appKitRect.origin.x - screen.frame.origin.x,
            y: appKitRect.origin.y - screen.frame.origin.y,
            width: appKitRect.width,
            height: appKitRect.height
        )

        guard let view = arrowWindow.contentView as? ArrowOverlayView else {
            return
        }

        view.frame = CGRect(origin: .zero, size: screen.frame.size)
        view.showArrow(pointingTo: localRect, message: message)
        arrowWindow.setFrame(screen.frame, display: true)
        arrowWindow.orderFrontRegardless()

//        print("[ArrowGuide] ✅ Arrow coordinates:")
//        print("[ArrowGuide]   CG input:       \(targetRectInScreen)")
//        print("[ArrowGuide]   primaryHeight:   \(primaryScreenHeight)")
//        print("[ArrowGuide]   AppKit global:   \(appKitRect)")
//        print("[ArrowGuide]   screen.frame:    \(screen.frame)")
//        print("[ArrowGuide]   local (in view): \(localRect)")
    }

    func hide() {
        guard let view = window?.contentView as? ArrowOverlayView else {
            window?.orderOut(nil)
            return
        }
        view.hideArrow()
        window?.orderOut(nil)
//         print("[ArrowGuide] Arrow hidden")
    }

    private func ensureWindow(for screen: NSScreen) -> ArrowOverlayWindow {
        if let window {
            return window
        }
        let newWindow = ArrowOverlayWindow(screen: screen)
        self.window = newWindow
        return newWindow
    }

    private func screenContaining(rect: CGRect) -> NSScreen? {
        // Convert CG midpoint to AppKit for screen matching
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitMidY = primaryScreenHeight - rect.midY
        let appKitMidpoint = CGPoint(x: rect.midX, y: appKitMidY)

        if let match = NSScreen.screens.first(where: { $0.frame.contains(appKitMidpoint) }) {
            return match
        }
        return NSScreen.main
    }
}

// MARK: - Transparent Arrow Window

final class ArrowOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false

        let arrowView = ArrowOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        contentView = arrowView
    }
}

// MARK: - Arrow Drawing View

final class ArrowOverlayView: NSView {

    private let arrowLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private let targetDotLayer = CAShapeLayer()

    private var targetRect: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupArrow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupArrow() {
        guard let root = layer else { return }

        // Glow layer (behind the arrow for visual emphasis)
        glowLayer.fillColor = NSColor.clear.cgColor
        glowLayer.strokeColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
        glowLayer.lineWidth = 14
        glowLayer.lineCap = .round
        glowLayer.lineJoin = .round
        root.addSublayer(glowLayer)

        // Main arrow layer
        arrowLayer.fillColor = NSColor.clear.cgColor
        arrowLayer.strokeColor = NSColor.systemGreen.cgColor
        arrowLayer.lineWidth = 6
        arrowLayer.lineCap = .round
        arrowLayer.lineJoin = .round
        root.addSublayer(arrowLayer)

        // Red target dot — shows exactly where we think the target center is
        targetDotLayer.fillColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        targetDotLayer.strokeColor = NSColor.white.cgColor
        targetDotLayer.lineWidth = 2
        root.addSublayer(targetDotLayer)
    }

    func showArrow(pointingTo rect: CGRect, message: String) {
        targetRect = rect
        updateArrowPath()
        startArrowAnimation()
        isHidden = false
    }

    func hideArrow() {
        arrowLayer.removeAllAnimations()
        glowLayer.removeAllAnimations()
        isHidden = true
    }

    override func layout() {
        super.layout()
        if targetRect != .zero {
            updateArrowPath()
        }
    }

    private func updateArrowPath() {
        let targetPoint = CGPoint(x: targetRect.midX, y: targetRect.midY)

        // Arrow starts from the upper-left of the target, curves down to point at it
        let start = CGPoint(
            x: max(40, targetRect.minX - 140),
            y: targetRect.midY + 80
        )
        let mid = CGPoint(
            x: targetPoint.x - 30,
            y: targetPoint.y + 25
        )
        let end = CGPoint(
            x: targetPoint.x - 6,
            y: targetPoint.y + 3
        )

        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: mid)

        // Arrowhead
        let angle = atan2(targetPoint.y - mid.y, targetPoint.x - mid.x)
        let arrowHeadLength: CGFloat = 18
        let arrowHeadAngle: CGFloat = .pi / 5.5

        let p1 = CGPoint(
            x: end.x - arrowHeadLength * cos(angle - arrowHeadAngle),
            y: end.y - arrowHeadLength * sin(angle - arrowHeadAngle)
        )
        let p2 = CGPoint(
            x: end.x - arrowHeadLength * cos(angle + arrowHeadAngle),
            y: end.y - arrowHeadLength * sin(angle + arrowHeadAngle)
        )

        path.move(to: end)
        path.addLine(to: p1)
        path.move(to: end)
        path.addLine(to: p2)

        arrowLayer.path = path
        glowLayer.path = path

        // Red dot at exact target center for coordinate verification
        let dotRadius: CGFloat = 10
        let dotPath = CGPath(ellipseIn: CGRect(
            x: targetPoint.x - dotRadius,
            y: targetPoint.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ), transform: nil)
        targetDotLayer.path = dotPath
    }

    private func startArrowAnimation() {
        arrowLayer.removeAllAnimations()
        glowLayer.removeAllAnimations()

        // Gentle bounce animation
        let bounce = CABasicAnimation(keyPath: "transform.translation.y")
        bounce.fromValue = 0
        bounce.toValue = -10
        bounce.duration = 0.9
        bounce.autoreverses = true
        bounce.repeatCount = .infinity
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Breathing opacity
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.5
        opacity.duration = 0.9
        opacity.autoreverses = true
        opacity.repeatCount = .infinity
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        arrowLayer.add(bounce, forKey: "arrow.bounce")
        arrowLayer.add(opacity, forKey: "arrow.opacity")

        // Glow pulses in sync
        let glowOpacity = CABasicAnimation(keyPath: "opacity")
        glowOpacity.fromValue = 0.6
        glowOpacity.toValue = 0.15
        glowOpacity.duration = 0.9
        glowOpacity.autoreverses = true
        glowOpacity.repeatCount = .infinity
        glowOpacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        glowLayer.add(bounce, forKey: "glow.bounce")
        glowLayer.add(glowOpacity, forKey: "glow.opacity")
    }
}
