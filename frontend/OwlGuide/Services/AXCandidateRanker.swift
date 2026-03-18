import Foundation

struct AXRankedElement: Identifiable {
    let id = UUID()
    let element: AXElementNode
    let score: Int
    let reasonTags: [String]
}

struct AXRankedBucket {
    let allCandidates: [AXRankedElement]
    let displayCap: Int

    var displayedElements: [AXRankedElement] {
        Array(allCandidates.prefix(displayCap))
    }

    var totalCandidateCount: Int {
        allCandidates.count
    }

    var displayedCount: Int {
        min(allCandidates.count, displayCap)
    }
}

struct AXRankedResults {
    let actionable: AXRankedBucket
    let readable: AXRankedBucket
}

struct AXCandidateRanker {
    private let rankedLimit = 12

    var displayCap: Int {
        rankedLimit
    }

    func rank(filteredElements: [AXElementNode]) -> AXRankedResults {
        let actionableCandidates = filteredElements
            .map(rankActionable)
            .sorted(by: rankedElementSort)

        let readableCandidates = filteredElements
            .map(rankReadable)
            .sorted(by: rankedElementSort)

        return AXRankedResults(
            actionable: AXRankedBucket(allCandidates: actionableCandidates, displayCap: rankedLimit),
            readable: AXRankedBucket(allCandidates: readableCandidates, displayCap: rankedLimit)
        )
    }

    private func rankActionable(_ element: AXElementNode) -> AXRankedElement {
        var score = 0
        var reasonTags: [String] = []

        let roleScore = actionableRoleScore(for: element)
        score += roleScore.score
        reasonTags.append(contentsOf: roleScore.tags)

        if element.hasUsefulText {
            score += 4
            reasonTags.append("useful text")
        }

        if element.hasMeaningfulBounds {
            score += 3
            reasonTags.append("meaningful bounds")
        }

        if hasUsableSize(element) {
            score += 2
            reasonTags.append("usable size")
        }

        if element.isContainerLike {
            score -= 5
            reasonTags.append("container down-rank")
        }

        if isLikelyWindowControl(element) {
            score -= 14
            reasonTags.append("window control down-rank")
        }

        return AXRankedElement(element: element, score: score, reasonTags: dedupe(reasonTags))
    }

    private func rankReadable(_ element: AXElementNode) -> AXRankedElement {
        var score = 0
        var reasonTags: [String] = []

        let roleScore = readableRoleScore(for: element)
        score += roleScore.score
        reasonTags.append(contentsOf: roleScore.tags)

        if element.title != "Unavailable" {
            score += 3
            reasonTags.append("has title")
        }

        if element.label != "Unavailable" {
            score += 3
            reasonTags.append("has label")
        }

        if element.value != "Unavailable" {
            score += 2
            reasonTags.append("has value")
        }

        if element.hasMeaningfulBounds {
            score += 1
            reasonTags.append("meaningful bounds")
        }

        if element.isContainerLike {
            score -= 4
            reasonTags.append("container down-rank")
        }

        if isLikelyWindowControl(element) {
            score -= 12
            reasonTags.append("window control down-rank")
        }

        return AXRankedElement(element: element, score: score, reasonTags: dedupe(reasonTags))
    }

    private func actionableRoleScore(for element: AXElementNode) -> (score: Int, tags: [String]) {
        switch element.role {
        case "AXButton":
            return (12, ["button"])
        case "AXTextField", "AXTextArea":
            return (11, ["text input"])
        case "AXLink":
            return (10, ["link"])
        case "AXCheckBox", "AXRadioButton":
            return (9, ["selection control"])
        case "AXPopUpButton", "AXMenuButton", "AXComboBox":
            return (9, ["menu control"])
        case "AXStaticText":
            return (4, ["readable text"])
        default:
            return (element.hasUsefulText ? 2 : 0, element.hasUsefulText ? ["labeled element"] : [])
        }
    }

    private func readableRoleScore(for element: AXElementNode) -> (score: Int, tags: [String]) {
        switch element.role {
        case "AXStaticText":
            return (12, ["static text"])
        case "AXTextField", "AXTextArea":
            return (9, ["text content"])
        case "AXButton":
            return (7, ["button label"])
        case "AXLink":
            return (7, ["link text"])
        case "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton":
            return (6, ["labeled control"])
        default:
            return (element.hasUsefulText ? 4 : 0, element.hasUsefulText ? ["text-bearing element"] : [])
        }
    }

    private func hasUsableSize(_ element: AXElementNode) -> Bool {
        guard let size = element.size else {
            return false
        }

        return size.width >= 24 && size.height >= 16
    }

    private func isLikelyWindowControl(_ element: AXElementNode) -> Bool {
        let roleHints = [element.role, element.subrole, element.title, element.label]
            .joined(separator: " ")
            .lowercased()

        let controlTerms = ["close", "minimize", "zoom", "fullscreen", "toolbar button"]
        return controlTerms.contains { roleHints.contains($0) }
    }

    private func rankedElementSort(lhs: AXRankedElement, rhs: AXRankedElement) -> Bool {
        if lhs.score == rhs.score {
            if lhs.element.depth == rhs.element.depth {
                return lhs.element.displayName < rhs.element.displayName
            }

            return lhs.element.depth < rhs.element.depth
        }

        return lhs.score > rhs.score
    }

    private func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
