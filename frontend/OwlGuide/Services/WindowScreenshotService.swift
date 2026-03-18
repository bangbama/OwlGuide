import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

struct WindowScreenshot {
    let cgImage: CGImage
    let pngData: Data
    let mimeType: String
    let size: CGSize

    var pixelWidth: Int {
        Int(size.width)
    }

    var pixelHeight: Int {
        Int(size.height)
    }

    var byteCount: Int {
        pngData.count
    }

    var processingDescription: String {
        "Original-size window capture encoded once as PNG. No resize. No lossy compression."
    }
}

struct GeminiSendImage {
    let data: Data
    let mimeType: String
    let size: CGSize
    let didDownscale: Bool
    let usedLossyCompression: Bool
    let processingDescription: String

    var pixelWidth: Int {
        Int(size.width)
    }

    var pixelHeight: Int {
        Int(size.height)
    }

    var byteCount: Int {
        data.count
    }
}

struct BackendUploadImage {
    let data: Data
    let mimeType: String
    let size: CGSize
    let didDownscale: Bool
    let usedLossyCompression: Bool
    let processingDescription: String

    var pixelWidth: Int {
        Int(size.width)
    }

    var pixelHeight: Int {
        Int(size.height)
    }

    var byteCount: Int {
        data.count
    }
}

enum WindowScreenshotError: LocalizedError {
    case screenRecordingPermissionRequired
    case windowNotFound
    case captureFailed
    case imageEncodingFailed
    case sendImagePreparationFailed

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionRequired:
            return "Screen Recording permission is required to capture another app's window screenshot. Enable it in System Settings > Privacy & Security > Screen Recording."
        case .windowNotFound:
            return "The captured target window could not be matched to a visible macOS window for screenshot capture."
        case .captureFailed:
            return "macOS could not capture the target window screenshot."
        case .imageEncodingFailed:
            return "The captured screenshot could not be encoded as PNG data."
        case .sendImagePreparationFailed:
            return "Owl Guide could not prepare the Gemini send-image from the captured window screenshot."
        }
    }
}

struct WindowScreenshotService {
    private static let geminiSendMaxLongEdge: CGFloat = 1600
    private static let geminiSendJPEGCompressionQuality: CGFloat = 0.82
    private static let backendUploadMaxLongEdge: CGFloat = 1600
    private static let backendUploadJPEGCompressionQuality: CGFloat = 0.80

    func canAttemptWindowScreenshot(
        processIdentifier: pid_t?,
        windowTitle: String?,
        targetFrame: CGRect?
    ) -> ScreenUnderstandingReadinessItem {
        guard CGPreflightScreenCaptureAccess() else {
            return ScreenUnderstandingReadinessItem(
                id: "screenshot-capture",
                title: "Window screenshot",
                isReady: false,
                detail: "Allow Screen Recording first. Owl Guide cannot capture the current app window without it."
            )
        }

        guard let processIdentifier else {
            return ScreenUnderstandingReadinessItem(
                id: "screenshot-capture",
                title: "Window screenshot",
                isReady: false,
                detail: "Capture another app first so Owl Guide knows which window to analyze."
            )
        }

        guard let targetFrame, targetFrame.width >= 80, targetFrame.height >= 80 else {
            return ScreenUnderstandingReadinessItem(
                id: "screenshot-capture",
                title: "Window screenshot",
                isReady: false,
                detail: "The captured window bounds are not usable yet. Refresh the external target and try again."
            )
        }

        guard bestMatchingWindow(
            processIdentifier: processIdentifier,
            windowTitle: sanitizedTitle(windowTitle),
            targetFrame: targetFrame
        ) != nil else {
            return ScreenUnderstandingReadinessItem(
                id: "screenshot-capture",
                title: "Window screenshot",
                isReady: false,
                detail: "Owl Guide could not match the captured target to a visible macOS window yet."
            )
        }

        return ScreenUnderstandingReadinessItem(
            id: "screenshot-capture",
            title: "Window screenshot",
            isReady: true,
            detail: "A visible target window is available for screenshot capture."
        )
    }

    func captureWindowScreenshot(
        processIdentifier: pid_t,
        windowTitle: String?,
        targetFrame: CGRect?
    ) async throws -> WindowScreenshot {
        guard CGPreflightScreenCaptureAccess() else {
            throw WindowScreenshotError.screenRecordingPermissionRequired
        }

        guard let matchedWindow = bestMatchingWindow(
            processIdentifier: processIdentifier,
            windowTitle: sanitizedTitle(windowTitle),
            targetFrame: targetFrame
        ) else {
            throw WindowScreenshotError.windowNotFound
        }

        guard let image = try await captureImage(for: matchedWindow) else {
            throw WindowScreenshotError.captureFailed
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw WindowScreenshotError.imageEncodingFailed
        }

        return WindowScreenshot(
            cgImage: image,
            pngData: pngData,
            mimeType: "image/png",
            size: CGSize(width: image.width, height: image.height)
        )
    }

    func prepareGeminiSendImage(from screenshot: WindowScreenshot) throws -> GeminiSendImage {
        let preparedImage = try prepareCompressedJPEGImage(
            from: screenshot,
            maxLongEdge: Self.geminiSendMaxLongEdge,
            compressionQuality: Self.geminiSendJPEGCompressionQuality,
            label: "Gemini send-image"
        )

        return GeminiSendImage(
            data: preparedImage.data,
            mimeType: "image/jpeg",
            size: preparedImage.size,
            didDownscale: preparedImage.didDownscale,
            usedLossyCompression: true,
            processingDescription: preparedImage.processingDescription
        )
    }

    func prepareBackendUploadImage(from screenshot: WindowScreenshot) async throws -> BackendUploadImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let preparedImage = try prepareCompressedJPEGImage(
                        from: screenshot,
                        maxLongEdge: Self.backendUploadMaxLongEdge,
                        compressionQuality: Self.backendUploadJPEGCompressionQuality,
                        label: "Backend upload image"
                    )
                    continuation.resume(
                        returning: BackendUploadImage(
                            data: preparedImage.data,
                            mimeType: "image/jpeg",
                            size: preparedImage.size,
                            didDownscale: preparedImage.didDownscale,
                            usedLossyCompression: true,
                            processingDescription: preparedImage.processingDescription
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func bestMatchingWindow(
        processIdentifier: pid_t,
        windowTitle: String?,
        targetFrame: CGRect?
    ) -> MatchedWindow? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        return windowList
            .compactMap { dictionary -> MatchedWindow? in
                guard let ownerPID = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
                      ownerPID.int32Value == processIdentifier,
                      let windowID = dictionary[kCGWindowNumber as String] as? NSNumber,
                      let layer = dictionary[kCGWindowLayer as String] as? NSNumber,
                      let boundsDictionary = dictionary[kCGWindowBounds as String] as? [String: Any],
                      let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                      bounds.width >= 40,
                      bounds.height >= 40 else {
                    return nil
                }

                let name = (dictionary[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let score = scoreWindow(
                    title: name,
                    layer: layer.intValue,
                    bounds: bounds,
                    expectedTitle: windowTitle,
                    expectedFrame: targetFrame
                )

                return MatchedWindow(
                    windowID: CGWindowID(windowID.uint32Value),
                    title: name,
                    bounds: bounds,
                    score: score
                )
            }
            .max(by: { $0.score < $1.score })
    }

    private func scoreWindow(
        title: String?,
        layer: Int,
        bounds: CGRect,
        expectedTitle: String?,
        expectedFrame: CGRect?
    ) -> Int {
        var score = 0

        if layer == 0 {
            score += 20
        } else {
            score -= min(layer * 2, 30)
        }

        if let expectedTitle, !expectedTitle.isEmpty,
           let title, !title.isEmpty {
            if title.caseInsensitiveCompare(expectedTitle) == .orderedSame {
                score += 120
            } else if title.localizedCaseInsensitiveContains(expectedTitle) || expectedTitle.localizedCaseInsensitiveContains(title) {
                score += 60
            }
        }

        if let expectedFrame {
            let standardizedBounds = bounds.standardized
            let standardizedExpected = expectedFrame.standardized
            let intersection = standardizedBounds.intersection(standardizedExpected)
            let overlapArea = max(intersection.width, 0) * max(intersection.height, 0)
            let expectedArea = max(standardizedExpected.width * standardizedExpected.height, 1)
            let overlapRatio = overlapArea / expectedArea
            score += Int(overlapRatio * 100)

            let midpointDistance = hypot(
                standardizedBounds.midX - standardizedExpected.midX,
                standardizedBounds.midY - standardizedExpected.midY
            )
            score -= Int(midpointDistance / 40)
        }

        return score
    }

    private func sanitizedTitle(_ title: String?) -> String? {
        guard let title else {
            return nil
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "Unavailable" || trimmed.isEmpty ? nil : trimmed
    }

    private func resizedImage(
        from image: CGImage,
        targetWidth: Int,
        targetHeight: Int
    ) -> CGImage? {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }

    private func prepareCompressedJPEGImage(
        from screenshot: WindowScreenshot,
        maxLongEdge: CGFloat,
        compressionQuality: CGFloat,
        label: String
    ) throws -> (data: Data, size: CGSize, didDownscale: Bool, processingDescription: String) {
        let originalWidth = CGFloat(screenshot.pixelWidth)
        let originalHeight = CGFloat(screenshot.pixelHeight)
        let originalLongEdge = max(originalWidth, originalHeight)
        let needsDownscale = originalLongEdge > maxLongEdge
        let scale = needsDownscale ? (maxLongEdge / originalLongEdge) : 1.0
        let targetWidth = max(Int((originalWidth * scale).rounded()), 1)
        let targetHeight = max(Int((originalHeight * scale).rounded()), 1)

        let outputCGImage: CGImage
        if needsDownscale {
            guard let resizedImage = resizedImage(
                from: screenshot.cgImage,
                targetWidth: targetWidth,
                targetHeight: targetHeight
            ) else {
                throw WindowScreenshotError.sendImagePreparationFailed
            }
            outputCGImage = resizedImage
        } else {
            outputCGImage = screenshot.cgImage
        }

        let bitmap = NSBitmapImageRep(cgImage: outputCGImage)
        guard let jpegData = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        ) else {
            throw WindowScreenshotError.sendImagePreparationFailed
        }

        let processingDescription: String
        if needsDownscale {
            processingDescription = "\(label) downscaled from \(screenshot.pixelWidth) × \(screenshot.pixelHeight) to \(targetWidth) × \(targetHeight), then JPEG-encoded at quality \(compressionQuality). Lossy compression applied."
        } else {
            processingDescription = "\(label) kept original dimensions at \(targetWidth) × \(targetHeight), then JPEG-encoded at quality \(compressionQuality). Lossy compression applied."
        }

        return (
            data: jpegData,
            size: CGSize(width: targetWidth, height: targetHeight),
            didDownscale: needsDownscale,
            processingDescription: processingDescription
        )
    }

    private func captureImage(for matchedWindow: MatchedWindow) async throws -> CGImage? {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)

        guard let scWindow = shareableContent.windows.first(where: { $0.windowID == matchedWindow.windowID }) else {
            throw WindowScreenshotError.windowNotFound
        }

        let contentFilter = SCContentFilter(desktopIndependentWindow: scWindow)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.width = max(Int((contentFilter.contentRect.width * CGFloat(contentFilter.pointPixelScale)).rounded()), 1)
        configuration.height = max(Int((contentFilter.contentRect.height * CGFloat(contentFilter.pointPixelScale)).rounded()), 1)

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: image)
                }
            }
        }
    }
}

private struct MatchedWindow {
    let windowID: CGWindowID
    let title: String?
    let bounds: CGRect
    let score: Int
}
