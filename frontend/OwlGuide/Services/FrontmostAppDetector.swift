import AppKit
import ApplicationServices
import Foundation

struct CapturedAXTarget {
    let debugInfo: FrontmostAppDebugInfo
    let windowElement: AXUIElement?
    let windowFrame: CGRect?
}

struct FrontmostAppDebugInfo {
    let localizedName: String
    let bundleIdentifier: String
    let processIdentifier: String
    let representsOwlGuide: Bool
    let appReferenceCreated: Bool
    let focusedWindowFound: Bool
    let mainWindowFallbackFound: Bool
    let windowTitle: String
    let windowRole: String
    let windowSubrole: String
    let statusMessage: String

    static let empty = FrontmostAppDebugInfo(
        localizedName: "Unavailable",
        bundleIdentifier: "Unavailable",
        processIdentifier: "Unavailable",
        representsOwlGuide: false,
        appReferenceCreated: false,
        focusedWindowFound: false,
        mainWindowFallbackFound: false,
        windowTitle: "Unavailable",
        windowRole: "Unavailable",
        windowSubrole: "Unavailable",
        statusMessage: "No frontmost application has been captured yet."
    )

    static func unavailable(message: String) -> FrontmostAppDebugInfo {
        FrontmostAppDebugInfo(
            localizedName: "Unavailable",
            bundleIdentifier: "Unavailable",
            processIdentifier: "Unavailable",
            representsOwlGuide: false,
            appReferenceCreated: false,
            focusedWindowFound: false,
            mainWindowFallbackFound: false,
            windowTitle: "Unavailable",
            windowRole: "Unavailable",
            windowSubrole: "Unavailable",
            statusMessage: message
        )
    }
}

struct FrontmostAppDetector {
    func currentFrontmostApplication() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    func isOwlGuide(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }

        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return true
        }

        guard let appBundleIdentifier = app.bundleIdentifier,
              let selfBundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        return appBundleIdentifier == selfBundleIdentifier
    }

    func captureDebugInfo(for app: NSRunningApplication?) -> FrontmostAppDebugInfo {
        captureTarget(for: app).debugInfo
    }

    func currentWindowFrame(for windowElement: AXUIElement?) -> CGRect? {
        guard let windowElement else {
            return nil
        }

        return rectValue(for: windowElement)
    }

    func captureTarget(for app: NSRunningApplication?) -> CapturedAXTarget {
        guard let app else {
            return CapturedAXTarget(
                debugInfo: .unavailable(message: "macOS did not report a frontmost application."),
                windowElement: nil,
                windowFrame: nil
            )
        }

        let pid = app.processIdentifier
        let applicationElement = AXUIElementCreateApplication(pid)
        let isSelf = isOwlGuide(app)

        var info = FrontmostAppDebugInfo(
            localizedName: app.localizedName ?? "Unknown",
            bundleIdentifier: app.bundleIdentifier ?? "Unknown",
            processIdentifier: String(pid),
            representsOwlGuide: isSelf,
            appReferenceCreated: true,
            focusedWindowFound: false,
            mainWindowFallbackFound: false,
            windowTitle: "Unavailable",
            windowRole: "Unavailable",
            windowSubrole: "Unavailable",
            statusMessage: "Accessibility application reference created."
        )

        let focusedWindowResult = copyElementValue(attribute: kAXFocusedWindowAttribute as CFString, from: applicationElement)
        switch focusedWindowResult {
        case .success(let focusedWindow):
            info = populateWindowMetadata(for: focusedWindow, into: info)
            return CapturedAXTarget(
                debugInfo: FrontmostAppDebugInfo(
                    localizedName: info.localizedName,
                    bundleIdentifier: info.bundleIdentifier,
                    processIdentifier: info.processIdentifier,
                    representsOwlGuide: info.representsOwlGuide,
                    appReferenceCreated: info.appReferenceCreated,
                    focusedWindowFound: true,
                    mainWindowFallbackFound: false,
                    windowTitle: info.windowTitle,
                    windowRole: info.windowRole,
                    windowSubrole: info.windowSubrole,
                    statusMessage: "Focused window resolved successfully."
                ),
                windowElement: focusedWindow,
                windowFrame: rectValue(for: focusedWindow)
            )
        case .failure(let focusedError):
            let mainWindowResult = copyElementValue(attribute: kAXMainWindowAttribute as CFString, from: applicationElement)

            switch mainWindowResult {
            case .success(let mainWindow):
                info = populateWindowMetadata(for: mainWindow, into: info)
                return CapturedAXTarget(
                    debugInfo: FrontmostAppDebugInfo(
                        localizedName: info.localizedName,
                        bundleIdentifier: info.bundleIdentifier,
                        processIdentifier: info.processIdentifier,
                        representsOwlGuide: info.representsOwlGuide,
                        appReferenceCreated: info.appReferenceCreated,
                        focusedWindowFound: false,
                        mainWindowFallbackFound: true,
                        windowTitle: info.windowTitle,
                        windowRole: info.windowRole,
                        windowSubrole: info.windowSubrole,
                        statusMessage: "Focused window unavailable: \(describe(error: focusedError)). Main window fallback resolved successfully."
                    ),
                    windowElement: mainWindow,
                    windowFrame: rectValue(for: mainWindow)
                )
            case .failure(let mainError):
                return CapturedAXTarget(
                    debugInfo: FrontmostAppDebugInfo(
                        localizedName: info.localizedName,
                        bundleIdentifier: info.bundleIdentifier,
                        processIdentifier: info.processIdentifier,
                        representsOwlGuide: info.representsOwlGuide,
                        appReferenceCreated: info.appReferenceCreated,
                        focusedWindowFound: false,
                        mainWindowFallbackFound: false,
                        windowTitle: info.windowTitle,
                        windowRole: info.windowRole,
                        windowSubrole: info.windowSubrole,
                        statusMessage: "Focused window unavailable: \(describe(error: focusedError)). Main window unavailable: \(describe(error: mainError))."
                    ),
                    windowElement: nil,
                    windowFrame: nil
                )
            }
        }
    }

    private func populateWindowMetadata(for window: AXUIElement, into info: FrontmostAppDebugInfo) -> FrontmostAppDebugInfo {
        FrontmostAppDebugInfo(
            localizedName: info.localizedName,
            bundleIdentifier: info.bundleIdentifier,
            processIdentifier: info.processIdentifier,
            representsOwlGuide: info.representsOwlGuide,
            appReferenceCreated: info.appReferenceCreated,
            focusedWindowFound: info.focusedWindowFound,
            mainWindowFallbackFound: info.mainWindowFallbackFound,
            windowTitle: stringValue(attribute: kAXTitleAttribute as CFString, from: window) ?? "Unavailable",
            windowRole: stringValue(attribute: kAXRoleAttribute as CFString, from: window) ?? "Unavailable",
            windowSubrole: stringValue(attribute: kAXSubroleAttribute as CFString, from: window) ?? "Unavailable",
            statusMessage: info.statusMessage
        )
    }

    private enum AXValueLookup {
        case success(CFTypeRef)
        case failure(AXError)
    }

    private enum AXElementLookup {
        case success(AXUIElement)
        case failure(AXError)
    }

    private func copyElementValue(attribute: CFString, from element: AXUIElement) -> AXElementLookup {
        switch copyAttributeValue(attribute: attribute, from: element) {
        case .success(let value):
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return .failure(.attributeUnsupported)
            }
            return .success(unsafeBitCast(value, to: AXUIElement.self))
        case .failure(let error):
            return .failure(error)
        }
    }

    private func stringValue(attribute: CFString, from element: AXUIElement) -> String? {
        switch copyAttributeValue(attribute: attribute, from: element) {
        case .success(let value):
            if let string = value as? String {
                return string
            }

            if let attributedString = value as? NSAttributedString {
                return attributedString.string
            }

            return String(describing: value)
        case .failure:
            return nil
        }
    }

    private func rectValue(for element: AXUIElement) -> CGRect? {
        guard let position = pointValue(attribute: kAXPositionAttribute as CFString, from: element),
              let size = sizeValue(attribute: kAXSizeAttribute as CFString, from: element) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func pointValue(attribute: CFString, from element: AXUIElement) -> CGPoint? {
        guard let axValue = axValue(attribute: attribute, from: element, expectedType: .cgPoint) else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func sizeValue(attribute: CFString, from element: AXUIElement) -> CGSize? {
        guard let axValue = axValue(attribute: attribute, from: element, expectedType: .cgSize) else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func axValue(attribute: CFString, from element: AXUIElement, expectedType: AXValueType) -> AXValue? {
        switch copyAttributeValue(attribute: attribute, from: element) {
        case .success(let value):
            guard CFGetTypeID(value) == AXValueGetTypeID() else {
                return nil
            }

            let axValue = unsafeBitCast(value, to: AXValue.self)
            guard AXValueGetType(axValue) == expectedType else {
                return nil
            }

            return axValue
        case .failure:
            return nil
        }
    }

    private func copyAttributeValue(attribute: CFString, from element: AXUIElement) -> AXValueLookup {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        if error == .success, let value {
            return .success(value)
        }

        return .failure(error == .success ? .noValue : error)
    }

    private func describe(error: AXError) -> String {
        switch error {
        case .success:
            return "success"
        case .failure:
            return "generic failure"
        case .illegalArgument:
            return "illegal argument"
        case .invalidUIElement:
            return "invalid UI element"
        case .invalidUIElementObserver:
            return "invalid UI element observer"
        case .cannotComplete:
            return "cannot complete"
        case .attributeUnsupported:
            return "attribute unsupported"
        case .actionUnsupported:
            return "action unsupported"
        case .notificationUnsupported:
            return "notification unsupported"
        case .notImplemented:
            return "not implemented"
        case .notificationAlreadyRegistered:
            return "notification already registered"
        case .notificationNotRegistered:
            return "notification not registered"
        case .apiDisabled:
            return "Accessibility API disabled"
        case .noValue:
            return "no value"
        case .parameterizedAttributeUnsupported:
            return "parameterized attribute unsupported"
        case .notEnoughPrecision:
            return "not enough precision"
        @unknown default:
            return "unknown AX error"
        }
    }
}
