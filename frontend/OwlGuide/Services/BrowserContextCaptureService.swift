import AppKit
import Foundation

enum BrowserCaptureFailureCategory: String, Codable {
    case permission = "permission"
    case unsupportedBrowser = "unsupported browser"
    case automationFailed = "automation failed"
    case emptyResult = "empty result"
    case fallbackUsed = "fallback used"
}

struct BrowserCaptureContext: Codable {
    let browserName: String
    let currentURL: String?
    let pageTitle: String?
    let visibleTextSummary: String?
    let primaryEntryPoints: [String]
    let pageIdentity: String?
    let likelyAudience: String?
    let likelySafeStartingPoint: String?
    let notableRiskOrAmbiguity: String?

    var hostname: String? {
        guard let currentURL,
              let url = URL(string: currentURL),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        return host.lowercased()
    }
}

struct BrowserCaptureAttemptResult {
    let attempted: Bool
    let browserName: String?
    let context: BrowserCaptureContext?
    let failureCategory: BrowserCaptureFailureCategory?
    let urlRetrievalStatus: String
    let titleRetrievalStatus: String
    let textSummaryStatus: String
    let contextUsageDescription: String

    static let unsupported = BrowserCaptureAttemptResult(
        attempted: false,
        browserName: nil,
        context: nil,
        failureCategory: .unsupportedBrowser,
        urlRetrievalStatus: "Skipped: frontmost target is not a supported browser.",
        titleRetrievalStatus: "Skipped: frontmost target is not a supported browser.",
        textSummaryStatus: "Skipped: frontmost target is not a supported browser.",
        contextUsageDescription: "Generic screenshot + AX context only"
    )
}

struct BrowserContextCaptureService {
    private static let fieldSeparator = "\u{001F}"
    private static let listSeparator = "\u{001E}"

    private enum SupportedBrowser {
        case safari
        case chrome

        init?(bundleIdentifier: String) {
            switch bundleIdentifier {
            case "com.apple.Safari":
                self = .safari
            case "com.google.Chrome":
                self = .chrome
            default:
                return nil
            }
        }

        var displayName: String {
            switch self {
            case .safari:
                return "Safari"
            case .chrome:
                return "Google Chrome"
            }
        }

        var bundleIdentifier: String {
            switch self {
            case .safari:
                return "com.apple.Safari"
            case .chrome:
                return "com.google.Chrome"
            }
        }
    }

    func captureContext(forAppNamed appName: String, bundleIdentifier: String) -> BrowserCaptureAttemptResult {
        guard let browser = SupportedBrowser(bundleIdentifier: bundleIdentifier) else {
            return .unsupported
        }

        let script = browserScript(for: browser)
        let descriptor = runAppleScript(script)

        switch descriptor {
        case .success(let payload):
            return parsePayload(payload, browserName: browser.displayName)
        case .failure(let error):
            let category = classifyFailureCategory(from: error.localizedDescription)
            return BrowserCaptureAttemptResult(
                attempted: true,
                browserName: browser.displayName,
                context: nil,
                failureCategory: category,
                urlRetrievalStatus: "Failed: \(error.localizedDescription)",
                titleRetrievalStatus: "Failed: \(error.localizedDescription)",
                textSummaryStatus: "Failed: \(error.localizedDescription)",
                contextUsageDescription: "Generic screenshot + AX context only"
            )
        }
    }

    private func parsePayload(_ payload: String, browserName: String) -> BrowserCaptureAttemptResult {
        let fields = payload.components(separatedBy: Self.fieldSeparator)
        guard fields.count >= 6 else {
            return BrowserCaptureAttemptResult(
                attempted: true,
                browserName: browserName,
                context: nil,
                failureCategory: .emptyResult,
                urlRetrievalStatus: "Failed: browser script returned an unexpected payload.",
                titleRetrievalStatus: "Failed: browser script returned an unexpected payload.",
                textSummaryStatus: "Failed: browser script returned an unexpected payload.",
                contextUsageDescription: "Generic screenshot + AX context only"
            )
        }

        let urlStatus = fields[0]
        let pageURL = trimmedOrNil(fields[1])
        let titleStatus = fields[2]
        let pageTitle = trimmedOrNil(fields[3])
        let textStatus = fields[4]
        let summaryPayload = fields[5]

        let summaryParts = summaryPayload.components(separatedBy: Self.listSeparator)
        let rawTextSummary = summaryParts.first.flatMap(trimmedOrNil)
        let entryPoints = summaryParts.dropFirst().compactMap(trimmedOrNil).prefix(5)
        let compressedSummary = compressedSemanticSummary(
            pageTitle: pageTitle,
            pageURL: pageURL,
            rawTextSummary: rawTextSummary,
            entryPoints: Array(entryPoints)
        )

        let context = BrowserCaptureContext(
            browserName: browserName,
            currentURL: pageURL,
            pageTitle: pageTitle,
            visibleTextSummary: compressedSummary.summary,
            primaryEntryPoints: compressedSummary.entryPoints,
            pageIdentity: compressedSummary.pageIdentity,
            likelyAudience: compressedSummary.likelyAudience,
            likelySafeStartingPoint: compressedSummary.likelySafeStartingPoint,
            notableRiskOrAmbiguity: compressedSummary.notableRiskOrAmbiguity
        )

        let hasUsefulBrowserContext =
            pageURL != nil
            || pageTitle != nil
            || compressedSummary.summary != nil
            || !compressedSummary.entryPoints.isEmpty

        return BrowserCaptureAttemptResult(
            attempted: true,
            browserName: browserName,
            context: hasUsefulBrowserContext ? context : nil,
            failureCategory: hasUsefulBrowserContext ? nil : .fallbackUsed,
            urlRetrievalStatus: urlStatus,
            titleRetrievalStatus: titleStatus,
            textSummaryStatus: textStatus,
            contextUsageDescription: hasUsefulBrowserContext
                ? "Browser-aware context + generic grounding"
                : "Generic screenshot + AX context only"
        )
    }

    private func browserScript(for browser: SupportedBrowser) -> String {
        let js = appleScriptStringLiteral(Self.browserSummaryJavaScript)
        let fs = Self.fieldSeparator

        switch browser {
        case .safari:
            return """
            tell application id "\(browser.bundleIdentifier)"
                if not (exists front document) then error "No front document available."
                set owlFieldSeparator to "\(fs)"
                set pageURL to ""
                set pageTitle to ""
                set pageData to ""
                set urlStatus to "Unavailable"
                set titleStatus to "Unavailable"
                set textStatus to "Unavailable"

                try
                    set pageURL to (URL of front document as text)
                    if pageURL is not "" then set urlStatus to "Retrieved"
                on error errMsg
                    set urlStatus to "Failed: " & errMsg
                end try

                try
                    set pageTitle to (name of front document as text)
                    if pageTitle is not "" then set titleStatus to "Retrieved"
                on error errMsg
                    set titleStatus to "Failed: " & errMsg
                end try

                try
                    set pageData to (do JavaScript \(js) in front document)
                    if pageData is not "" then set textStatus to "Retrieved"
                on error errMsg
                    set textStatus to "Failed: " & errMsg
                end try

                return urlStatus & owlFieldSeparator & pageURL & owlFieldSeparator & titleStatus & owlFieldSeparator & pageTitle & owlFieldSeparator & textStatus & owlFieldSeparator & pageData
            end tell
            """
        case .chrome:
            return """
            tell application id "\(browser.bundleIdentifier)"
                if (count of windows) is 0 then error "No front window available."
                set owlFieldSeparator to "\(fs)"
                set pageURL to ""
                set pageTitle to ""
                set pageData to ""
                set urlStatus to "Unavailable"
                set titleStatus to "Unavailable"
                set textStatus to "Unavailable"

                try
                    set pageURL to (URL of active tab of front window as text)
                    if pageURL is not "" then set urlStatus to "Retrieved"
                on error errMsg
                    set urlStatus to "Failed: " & errMsg
                end try

                try
                    set pageTitle to (title of active tab of front window as text)
                    if pageTitle is not "" then set titleStatus to "Retrieved"
                on error errMsg
                    set titleStatus to "Failed: " & errMsg
                end try

                try
                    set pageData to (execute active tab of front window javascript \(js))
                    if pageData is not "" then set textStatus to "Retrieved"
                on error errMsg
                    set textStatus to "Failed: " & errMsg
                end try

                return urlStatus & owlFieldSeparator & pageURL & owlFieldSeparator & titleStatus & owlFieldSeparator & pageTitle & owlFieldSeparator & textStatus & owlFieldSeparator & pageData
            end tell
            """
        }
    }

    private func runAppleScript(_ source: String) -> Result<String, NSError> {
        guard let appleScript = NSAppleScript(source: source) else {
            return .failure(
                NSError(
                    domain: "BrowserContextCaptureService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not create AppleScript source."]
                )
            )
        }

        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                ?? "Browser scripting failed."
            return .failure(
                NSError(
                    domain: "BrowserContextCaptureService",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            )
        }

        return .success(descriptor.stringValue ?? "")
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func classifyFailureCategory(from message: String) -> BrowserCaptureFailureCategory {
        let lowercased = message.lowercased()

        if lowercased.contains("not authorized")
            || lowercased.contains("not permitted")
            || lowercased.contains("permission")
            || lowercased.contains("allow javascript from apple events") {
            return .permission
        }

        return .automationFailed
    }

    private func compressedSemanticSummary(
        pageTitle: String?,
        pageURL: String?,
        rawTextSummary: String?,
        entryPoints: [String]
    ) -> (
        summary: String?,
        pageIdentity: String?,
        likelyAudience: String?,
        likelySafeStartingPoint: String?,
        notableRiskOrAmbiguity: String?,
        entryPoints: [String]
    ) {
        let hostname = URL(string: pageURL ?? "")?.host?.lowercased()
        let compactEntryPoints = Array(entryPoints.prefix(5))
        let lowercasedCorpus = [pageTitle, rawTextSummary, hostname]
            .compactMap { $0?.lowercased() }
            .joined(separator: " | ")

        let pageIdentity = compactText(pageTitle ?? rawTextSummary, limit: 80)
        let likelyAudience: String?
        if lowercasedCorpus.contains("patient") || lowercasedCorpus.contains("medical") || lowercasedCorpus.contains("health") || lowercasedCorpus.contains("hospital") {
            likelyAudience = "Patients or families"
        } else if lowercasedCorpus.contains("account") || lowercasedCorpus.contains("sign in") {
            likelyAudience = "Account users"
        } else {
            likelyAudience = nil
        }

        let likelySafeStartingPoint = compactEntryPoints.first ?? compactText(rawTextSummary, limit: 60)
        let notableRiskOrAmbiguity: String?
        if compactEntryPoints.count >= 4 {
            notableRiskOrAmbiguity = "Many entry points are visible."
        } else if compactEntryPoints.isEmpty {
            notableRiskOrAmbiguity = "No clear entry point was detected."
        } else {
            notableRiskOrAmbiguity = nil
        }

        let summaryComponents = [
            pageIdentity.map { "Page identity: \($0)" },
            likelyAudience.map { "Audience: \($0)" },
            !compactEntryPoints.isEmpty ? "Entry points: \(compactEntryPoints.joined(separator: " | "))" : nil,
            likelySafeStartingPoint.map { "Safe start: \($0)" },
            notableRiskOrAmbiguity.map { "Note: \($0)" }
        ].compactMap { $0 }

        return (
            summary: summaryComponents.joined(separator: " || ").isEmpty ? nil : summaryComponents.joined(separator: " || "),
            pageIdentity: pageIdentity,
            likelyAudience: likelyAudience,
            likelySafeStartingPoint: likelySafeStartingPoint,
            notableRiskOrAmbiguity: notableRiskOrAmbiguity,
            entryPoints: compactEntryPoints
        )
    }

    private func compactText(_ value: String?, limit: Int) -> String? {
        guard let value = trimmedOrNil(value ?? "") else {
            return nil
        }

        if value.count <= limit {
            return value
        }

        let truncated = value.prefix(limit - 1).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(truncated)…"
    }

    private static let browserSummaryJavaScript = """
    (() => {
      const clean = (value) => (value || "").replace(/\\s+/g, " ").trim();
      const summaryParts = [];
      const entryPoints = [];
      const pushUnique = (list, value, maxCount) => {
        const cleaned = clean(value);
        if (!cleaned || cleaned.length < 2) return;
        const generic = ["home", "menu", "more", "next", "back", "close"];
        if (list === entryPoints && generic.includes(cleaned.toLowerCase())) return;
        if (!list.includes(cleaned)) list.push(cleaned);
        if (list.length > maxCount) list.length = maxCount;
      };

      pushUnique(summaryParts, document.title, 8);
      const metaDescription = document.querySelector('meta[name="description"]')?.content;
      pushUnique(summaryParts, metaDescription, 8);

      Array.from(document.querySelectorAll("main h1, main h2, h1, h2, h3"))
        .slice(0, 5)
        .forEach((element) => pushUnique(summaryParts, element.innerText, 8));

      Array.from(document.querySelectorAll("main p, main li"))
        .slice(0, 4)
        .forEach((element) => pushUnique(summaryParts, element.innerText, 10));

      Array.from(document.querySelectorAll("main a, main button, nav a, [role='button'], input[type='submit'], input[type='button']"))
        .slice(0, 40)
        .forEach((element) => {
          pushUnique(
            entryPoints,
            element.innerText || element.value || element.getAttribute("aria-label") || element.getAttribute("title"),
            5
          );
        });

      const summary = clean(summaryParts.join(" | ")).slice(0, 360);
      return [summary].concat(entryPoints).join("\(Self.listSeparator)");
    })();
    """
}
