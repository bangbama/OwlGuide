import ApplicationServices
import Foundation

struct AXElementNode: Identifiable {
    let id = UUID()
    let axElement: AXUIElement?
    let path: String
    let role: String
    let subrole: String
    let title: String
    let label: String
    let value: String
    let position: CGPoint?
    let size: CGSize?
    let depth: Int
    let isEnabled: Bool?
    let isFocused: Bool?

    var displayName: String {
        let candidates = [title, label, value]
        if let firstUsableValue = candidates.first(where: { $0 != "Unavailable" && !$0.isEmpty }) {
            return firstUsableValue
        }

        return role
    }

    var positionSummary: String {
        guard let position else { return "Unavailable" }
        return String(format: "(%.1f, %.1f)", position.x, position.y)
    }

    var sizeSummary: String {
        guard let size else { return "Unavailable" }
        return String(format: "(%.1f × %.1f)", size.width, size.height)
    }

    var geometrySummary: String {
        "\(positionSummary) | \(sizeSummary)"
    }

    var depthSummary: String {
        "Depth \(depth)"
    }

    var parentPath: String? {
        guard let separatorIndex = path.lastIndex(of: ".") else {
            return nil
        }

        return String(path[..<separatorIndex])
    }

    var boundsRect: CGRect? {
        guard let position, let size else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    var isContainerLike: Bool {
        let containerRoles: Set<String> = [
            "AXGroup",
            "AXLayoutArea",
            "AXScrollArea",
            "AXSplitGroup",
            "AXTabGroup",
            "AXToolbar",
            "AXList",
            "AXOutline",
            "AXBrowser"
        ]

        return containerRoles.contains(role)
    }

    var hasUsefulText: Bool {
        [title, label, value].contains { candidate in
            candidate != "Unavailable" && !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var hasMeaningfulBounds: Bool {
        guard let size else {
            return false
        }

        return size.width > 1 && size.height > 1
    }

    var isLikelyActionable: Bool {
        let actionableRoles: Set<String> = [
            "AXButton",
            "AXLink",
            "AXTextField",
            "AXTextArea",
            "AXCheckBox",
            "AXRadioButton",
            "AXPopUpButton",
            "AXMenuButton",
            "AXStaticText"
        ]

        return actionableRoles.contains(role) || (hasUsefulText && !isContainerLike)
    }

    var flagsSummary: String {
        [
            "container-like: \(isContainerLike ? "yes" : "no")",
            "useful text: \(hasUsefulText ? "yes" : "no")",
            "meaningful bounds: \(hasMeaningfulBounds ? "yes" : "no")"
        ].joined(separator: " | ")
    }

    var enabledSummary: String {
        boolSummary(isEnabled)
    }

    var focusedSummary: String {
        boolSummary(isFocused)
    }

    private func boolSummary(_ value: Bool?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return value ? "Yes" : "No"
    }
}
