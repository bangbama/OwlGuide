import ApplicationServices
import Foundation

struct AccessibilityScanConfiguration {
    let maxDepth: Int
    let maxNodeCount: Int

    static let `default` = AccessibilityScanConfiguration(maxDepth: 2, maxNodeCount: 200)
}

struct AccessibilityScanResult {
    let elements: [AXElementNode]
    let statusMessage: String
    let isFailure: Bool
    let didHitNodeLimit: Bool
    let childLookupFailureCount: Int
    let depthLimit: Int
    let nodeLimit: Int
}

struct AccessibilityScanner {
    func scanWindow(
        _ window: AXUIElement?,
        configuration: AccessibilityScanConfiguration = .default
    ) -> AccessibilityScanResult {
        guard let window else {
            return AccessibilityScanResult(
                elements: [],
                statusMessage: "No captured external window is available yet. Capture an external target first.",
                isFailure: true,
                didHitNodeLimit: false,
                childLookupFailureCount: 0,
                depthLimit: configuration.maxDepth,
                nodeLimit: configuration.maxNodeCount
            )
        }

        switch copyChildren(from: window) {
        case .success(let children):
            var elements: [AXElementNode] = []
            var didHitNodeLimit = false
            var childLookupFailureCount = 0

            for (index, child) in children.enumerated() {
                traverse(
                    element: child,
                    depth: 1,
                    path: "\(index)",
                    configuration: configuration,
                    elements: &elements,
                    didHitNodeLimit: &didHitNodeLimit,
                    childLookupFailureCount: &childLookupFailureCount
                )

                if didHitNodeLimit {
                    break
                }
            }

            if elements.isEmpty {
                return AccessibilityScanResult(
                    elements: [],
                    statusMessage: "The captured external window exposed no accessibility children within depth \(configuration.maxDepth).",
                    isFailure: false,
                    didHitNodeLimit: didHitNodeLimit,
                    childLookupFailureCount: childLookupFailureCount,
                    depthLimit: configuration.maxDepth,
                    nodeLimit: configuration.maxNodeCount
                )
            }

            var message = "Scanned \(elements.count) accessibility nodes from the captured external window up to depth \(configuration.maxDepth)."
            if didHitNodeLimit {
                message += " The scan hit the node cap of \(configuration.maxNodeCount)."
            }
            if childLookupFailureCount > 0 {
                message += " Some descendant child lookups failed (\(childLookupFailureCount))."
            }

            return AccessibilityScanResult(
                elements: elements,
                statusMessage: message,
                isFailure: false,
                didHitNodeLimit: didHitNodeLimit,
                childLookupFailureCount: childLookupFailureCount,
                depthLimit: configuration.maxDepth,
                nodeLimit: configuration.maxNodeCount
            )
        case .failure(let error):
            return AccessibilityScanResult(
                elements: [],
                statusMessage: "Could not read AXChildren from the captured external window: \(describe(error: error)).",
                isFailure: true,
                didHitNodeLimit: false,
                childLookupFailureCount: 0,
                depthLimit: configuration.maxDepth,
                nodeLimit: configuration.maxNodeCount
            )
        }
    }

    private enum AXChildrenLookup {
        case success([AXUIElement])
        case failure(AXError)
    }

    private enum AXValueLookup {
        case success(CFTypeRef)
        case failure(AXError)
    }

    private func traverse(
        element: AXUIElement,
        depth: Int,
        path: String,
        configuration: AccessibilityScanConfiguration,
        elements: inout [AXElementNode],
        didHitNodeLimit: inout Bool,
        childLookupFailureCount: inout Int
    ) {
        guard !didHitNodeLimit else { return }

        if elements.count >= configuration.maxNodeCount {
            didHitNodeLimit = true
            return
        }

        elements.append(makeElementNode(from: element, depth: depth, path: path))

        guard depth < configuration.maxDepth else {
            return
        }

        switch copyChildren(from: element) {
        case .success(let children):
            for (index, child) in children.enumerated() {
                traverse(
                    element: child,
                    depth: depth + 1,
                    path: "\(path).\(index)",
                    configuration: configuration,
                    elements: &elements,
                    didHitNodeLimit: &didHitNodeLimit,
                    childLookupFailureCount: &childLookupFailureCount
                )

                if didHitNodeLimit {
                    break
                }
            }
        case .failure:
            childLookupFailureCount += 1
        }
    }

    private func copyChildren(from element: AXUIElement) -> AXChildrenLookup {
        var childCount: CFIndex = 0
        let countError = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &childCount)

        switch countError {
        case .success:
            guard childCount > 0 else {
                return .success([])
            }

            var values: CFArray?
            let copyError = AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, childCount, &values)

            if copyError == .success, let values {
                return .success(convertToElements(values))
            }

            return fallbackChildrenCopy(from: element, primaryError: copyError == .success ? .noValue : copyError)
        case .noValue:
            return .success([])
        default:
            return fallbackChildrenCopy(from: element, primaryError: countError)
        }
    }

    private func fallbackChildrenCopy(from element: AXUIElement, primaryError: AXError) -> AXChildrenLookup {
        switch copyAttributeValue(attribute: kAXChildrenAttribute as CFString, from: element) {
        case .success(let value):
            guard CFGetTypeID(value) == CFArrayGetTypeID() else {
                return .failure(primaryError)
            }

            let values = unsafeBitCast(value, to: CFArray.self)
            return .success(convertToElements(values))
        case .failure:
            return .failure(primaryError)
        }
    }

    private func convertToElements(_ values: CFArray) -> [AXUIElement] {
        let items = values as [AnyObject]
        return items.compactMap { item in
            let cfItem = item as CFTypeRef
            guard CFGetTypeID(cfItem) == AXUIElementGetTypeID() else {
                return nil
            }

            return unsafeBitCast(cfItem, to: AXUIElement.self)
        }
    }

    private func makeElementNode(from element: AXUIElement, depth: Int, path: String) -> AXElementNode {
        AXElementNode(
            axElement: element,
            path: path,
            role: stringValue(attribute: kAXRoleAttribute as CFString, from: element) ?? "Unavailable",
            subrole: stringValue(attribute: kAXSubroleAttribute as CFString, from: element) ?? "Unavailable",
            title: stringValue(attribute: kAXTitleAttribute as CFString, from: element) ?? "Unavailable",
            label: stringValue(attribute: kAXDescriptionAttribute as CFString, from: element) ?? "Unavailable",
            value: stringValue(attribute: kAXValueAttribute as CFString, from: element) ?? "Unavailable",
            position: pointValue(attribute: kAXPositionAttribute as CFString, from: element),
            size: sizeValue(attribute: kAXSizeAttribute as CFString, from: element),
            depth: depth,
            isEnabled: boolValue(attribute: kAXEnabledAttribute as CFString, from: element),
            isFocused: boolValue(attribute: kAXFocusedAttribute as CFString, from: element)
        )
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

            if let number = value as? NSNumber {
                return number.stringValue
            }

            return String(describing: value)
        case .failure:
            return nil
        }
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

    private func boolValue(attribute: CFString, from element: AXUIElement) -> Bool? {
        switch copyAttributeValue(attribute: attribute, from: element) {
        case .success(let value):
            if let boolean = value as? Bool {
                return boolean
            }

            if let number = value as? NSNumber {
                return number.boolValue
            }

            return nil
        case .failure:
            return nil
        }
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
