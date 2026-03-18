import AppKit
import CoreGraphics
import Foundation
import ApplicationServices

enum ActionExecutionError: Error, LocalizedError {
    case axPermissionDenied
    case cannotCreateEvent
    case targetFocusFailed
    case timeout
    case simulationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .axPermissionDenied: return "Accessibility permission denied."
        case .cannotCreateEvent: return "Failed to create CGEvent."
        case .targetFocusFailed: return "Target application could not be brought to front."
        case .timeout: return "Timed out waiting for target window focus."
        case .simulationFailed(let reason): return "System error: \(reason)"
        }
    }
}

@MainActor
final class ActionExecutionService {

    // MARK: - Click (Expert Focus-Verify-Click Pattern)

    func click(at point: CGPoint) async throws {
        guard AXIsProcessTrusted() else {
            throw ActionExecutionError.axPermissionDenied
        }

        print("[ActionTrace] 🚀 Starting Robust Click Sequence at \(point)")
        let startTime = Date()

        // 1. Identify Target App and Window via coordinate
        let systemWide = AXUIElementCreateSystemWide()
        var elementUnderMouse: AXUIElement?
        
        let axErr = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &elementUnderMouse)
        guard axErr == .success, let targetElement = elementUnderMouse else {
            print("[ActionTrace] ⚠️ Could not find AX element at position. Falling back to basic click.")
            try await performBasicClick(at: point)
            return
        }

        // 2. Resolve PID and Window Reference
        var pid: pid_t = 0
        AXUIElementGetPid(targetElement, &pid)
        let appRef = AXUIElementCreateApplication(pid)
        let windowRef = findWindowParent(of: targetElement) ?? targetElement

        print("[ActionTrace] 🔍 Target PID: \(pid), Window found: \(windowRef != targetElement)")

        // 3. Stage 1: Force Transition to Frontmost
        // We set Frontmost on App and Main on Window
        try await activateTarget(appRef: appRef, windowRef: windowRef)

        // 4. Stage 2: Verification Loop (Wait for OS to settle window state)
        // We give it up to 400ms to register as Frontmost/Main
        let focused = try await waitUntilFocused(appRef: appRef, windowRef: windowRef, timeout: 0.4)
        print("[ActionTrace] \(focused ? "✅" : "⚠️") Focus verified.")

        // 5. Stage 3: Event Injection
        try await postClickSequence(at: point)

        let totalTime = Date().timeIntervalSince(startTime)
        print("[ActionTrace] 🏁 Sequence finished in \(String(format: "%.3f", totalTime))s")
    }

    // MARK: - Internal Logic (Expert Reference)

    private func activateTarget(appRef: AXUIElement, windowRef: AXUIElement) async throws {
        // Set App to Frontmost
        AXUIElementSetAttributeValue(appRef, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        // Set Window to Main
        AXUIElementSetAttributeValue(windowRef, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    private func waitUntilFocused(appRef: AXUIElement, windowRef: AXUIElement, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var frontmostValue: CFTypeRef?
            var mainValue: CFTypeRef?
            
            let isAppFront = AXUIElementCopyAttributeValue(appRef, kAXFrontmostAttribute as CFString, &frontmostValue) == .success && (frontmostValue as? Bool == true)
            let isWinMain = AXUIElementCopyAttributeValue(windowRef, kAXMainAttribute as CFString, &mainValue) == .success && (mainValue as? Bool == true)
            
            if isAppFront && isWinMain { return true }
            
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms poll
        }
        return false
    }

    private func postClickSequence(at point: CGPoint) async throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw ActionExecutionError.cannotCreateEvent
        }
        
        // Suppress local events to 0 to ensure our simulated event wins
        source.localEventsSuppressionInterval = 0

        // Move confirmation
        CGWarpMouseCursorPosition(point)
        let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: 20_000_000)

        // Dual Stage Click (Stage 1 is for OS safety, Stage 2 for logic)
        for stage in 1...2 {
            guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
                continue
            }
            down.post(tap: .cghidEventTap)
            try await Task.sleep(nanoseconds: 30_000_000) // 30ms hold
            up.post(tap: .cghidEventTap)
            
            if stage == 1 {
                try await Task.sleep(nanoseconds: 100_000_000) // Gap between clicks
            }
        }
    }

    private func performBasicClick(at point: CGPoint) async throws {
        let source = CGEventSource(stateID: .hidSystemState)
        CGWarpMouseCursorPosition(point)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cgAnnotatedSessionEventTap)
        try await Task.sleep(nanoseconds: 50_000_000)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func findWindowParent(of element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<10 { // Max depth search
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role) == .success,
               (role as? String) == kAXWindowRole as String {
                return current
            }
            var parent: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success {
                current = (parent as! AXUIElement)
            } else {
                break
            }
        }
        return nil
    }

    // MARK: - Type

    func type(text: String, focusingAt point: CGPoint? = nil,
              pressReturn shouldPressReturn: Bool = false) async throws {
        if let point {
            print("[ActionTrace] ⌨️ Type focus request. Activating window...")
            try await click(at: point)
            try await Task.sleep(nanoseconds: 600_000_000) // Wait for focus to land
        }

        let eventSource = CGEventSource(stateID: .combinedSessionState)
        let utf16Chars  = Array(text.utf16)
        
        for start in stride(from: 0, to: utf16Chars.count, by: chunkSize) {
            let end = min(start + 20, utf16Chars.count)
            let chunk = Array(utf16Chars[start..<end])
            guard let keyEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) else { continue }
            keyEvent.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyEvent.post(tap: .cgAnnotatedSessionEventTap)
            keyEvent.type = .keyUp
            keyEvent.post(tap: .cgAnnotatedSessionEventTap)
            try await Task.sleep(nanoseconds: 15_000_000)
        }

        if shouldPressReturn {
            try pressReturn(eventSource: eventSource)
        }
    }
    
    private let chunkSize = 20

    private func pressReturn(eventSource: CGEventSource?) throws {
        let returnKey: CGKeyCode = 36
        guard let down = CGEvent(keyboardEventSource: eventSource, virtualKey: returnKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: eventSource, virtualKey: returnKey, keyDown: false) else { return }
        down.post(tap: .cgAnnotatedSessionEventTap)
        usleep(20_000)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
