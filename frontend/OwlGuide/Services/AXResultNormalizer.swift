import Foundation

struct AXNormalizedScanResults {
    let rawNodes: [AXElementNode]
    let usefulNodes: [AXElementNode]
}

struct AXResultNormalizer {
    func normalize(rawNodes: [AXElementNode]) -> AXNormalizedScanResults {
        let parentLookup = Dictionary(uniqueKeysWithValues: rawNodes.map { ($0.path, $0) })

        let usefulNodes = rawNodes
            .enumerated()
            .filter { _, node in
                let parentNode = node.parentPath.flatMap { parentLookup[$0] }
                return shouldKeep(node: node, parentNode: parentNode)
            }
            .sorted { lhs, rhs in
                let leftScore = usefulnessScore(for: lhs.element)
                let rightScore = usefulnessScore(for: rhs.element)

                if leftScore == rightScore {
                    return lhs.offset < rhs.offset
                }

                return leftScore > rightScore
            }
            .map(\.element)

        return AXNormalizedScanResults(rawNodes: rawNodes, usefulNodes: usefulNodes)
    }

    private func shouldKeep(node: AXElementNode, parentNode: AXElementNode?) -> Bool {
        if node.isLikelyActionable {
            return true
        }

        if node.hasUsefulText && node.hasMeaningfulBounds {
            return true
        }

        if isLikelyNoisyContainer(node: node, parentNode: parentNode) {
            return false
        }

        if !node.hasUsefulText && !node.hasMeaningfulBounds {
            return false
        }

        return !node.isContainerLike || node.hasUsefulText
    }

    private func isLikelyNoisyContainer(node: AXElementNode, parentNode: AXElementNode?) -> Bool {
        guard node.isContainerLike else {
            return false
        }

        if !node.hasUsefulText, let parentNode, parentNode.isContainerLike, nearlyIdenticalBounds(lhs: node, rhs: parentNode) {
            return true
        }

        return !node.hasUsefulText && !node.hasMeaningfulBounds
    }

    private func nearlyIdenticalBounds(lhs: AXElementNode, rhs: AXElementNode) -> Bool {
        guard let leftBounds = lhs.boundsRect, let rightBounds = rhs.boundsRect else {
            return false
        }

        let tolerance: CGFloat = 6
        return abs(leftBounds.minX - rightBounds.minX) <= tolerance
            && abs(leftBounds.minY - rightBounds.minY) <= tolerance
            && abs(leftBounds.width - rightBounds.width) <= tolerance
            && abs(leftBounds.height - rightBounds.height) <= tolerance
    }

    private func usefulnessScore(for node: AXElementNode) -> Int {
        var score = 0

        if node.isLikelyActionable {
            score += 4
        }

        if node.hasUsefulText {
            score += 3
        }

        if node.hasMeaningfulBounds {
            score += 1
        }

        if !node.isContainerLike {
            score += 1
        }

        return score
    }
}
