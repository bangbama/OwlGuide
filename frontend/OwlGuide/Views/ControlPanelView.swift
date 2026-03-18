import SwiftUI
import Speech
import AVFoundation

private enum ScanResultsDisplayMode: String, CaseIterable, Identifiable {
    case raw = "Raw AX Tree"
    case filtered = "Filtered Useful Elements"
    case actionable = "Top Actionable Elements"
    case readable = "Top Readable Elements"

    var id: String { rawValue }
}

struct ControlPanelView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var settings = AppSettings.shared
    @State private var scanResultsDisplayMode: ScanResultsDisplayMode = .raw
    @State private var analysisDebugPresentationMode: AnalysisDebugPresentationMode = .compact
    @State private var debugSearchQuery = ""
    @State private var isCurrentFrontmostExpanded = false
    @State private var isGeminiSetupExpanded = false
    @State private var isBrowserDiagnosticsExpanded = false
    @State private var isScreenshotDiagnosticsExpanded = false
    @State private var isPayloadDiagnosticsExpanded = false
    @State private var isRequestSummaryExpanded = false
    @State private var isResponseDiagnosticsExpanded = false
    @State private var isAdvancedAppDebugExpanded = false
@State private var isBackendExpanded = false
@State private var isCapturedTargetExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Owl Guide")
                    .font(.title3.weight(.semibold))
                
                Text("v2.1 (20260317-23:35)")
                    .font(.caption2.weight(.medium).monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .quaternaryLabelColor))
                    )
                    .padding(.leading, 4)

                Spacer()
                Button("Close") {
                    viewModel.closeInspector()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    debugQuickFindSection
                    autopilotSettingsSection
                    backendIntegrationSection

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Phase 1 Debug Panel")
                            .font(.headline)
                        Text("The app shell is running. The scanner now reads the captured external target window with a limited AXChildren depth, derives a filtered useful-elements list, and ranks local candidates for actionability and readability.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Permissions")
                                .font(.headline)

                            Spacer()

                            if !viewModel.permissionState.isGranted || !screenRecordingIsGranted {
                                Text("Attention needed")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.orange.opacity(0.12))
                                    )
                            } else {
                                Text("Ready")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.green.opacity(0.12))
                                    )
                            }
                        }

                        Text("Owl Guide needs these macOS permissions before it can inspect another app and capture the current window image.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        permissionStatusRow(
                            title: "Accessibility",
                            isGranted: viewModel.permissionState.isGranted,
                            summary: viewModel.permissionState.summary,
                            guidance: viewModel.permissionState.guidance
                        )

                        permissionStatusRow(
                            title: "Screen Recording",
                            isGranted: screenRecordingIsGranted,
                            summary: screenRecordingSummary,
                            guidance: screenRecordingGuidance
                        )
                        
                        permissionStatusRow(
                            title: "Microphone",
                            isGranted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                            summary: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? "Owl Guide can capture audio for voice input." : "Owl Guide needs Microphone permission to record audio for voice input.",
                            guidance: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? "Microphone access is enabled." : "Open System Settings > Privacy & Security > Microphone, enable Owl Guide, then quit and reopen the app if macOS still does not allow audio capture."
                        )
                        
                        permissionStatusRow(
                            title: "Speech Recognition",
                            isGranted: SFSpeechRecognizer.authorizationStatus() == .authorized,
                            summary: SFSpeechRecognizer.authorizationStatus() == .authorized ? "Owl Guide can transcribe speech to text locally." : "Owl Guide needs Speech Recognition permission to convert voice input to text.",
                            guidance: SFSpeechRecognizer.authorizationStatus() == .authorized ? "Speech Recognition is enabled." : "Open System Settings > Privacy & Security > Speech Recognition, enable Owl Guide, then quit and reopen the app if macOS still does not allow speech recognition."
                        )

                        HStack(spacing: 12) {
                            // Request buttons first
                            if !viewModel.permissionState.isGranted {
                                Button("Request Accessibility") {
                                    viewModel.requestAccessibilityPermission()
                                }
                            }

                            if !screenRecordingIsGranted {
                                Button("Request Screen Recording") {
                                    viewModel.requestScreenRecordingPermission()
                                }
                            }

                            Button("Request All Voice Permissions") {
                                AVCaptureDevice.requestAccess(for: .audio) { _ in
                                    SFSpeechRecognizer.requestAuthorization { _ in
                                        DispatchQueue.main.async {
                                            viewModel.refreshPermissionStatus()
                                        }
                                    }
                                }
                            }
                            
                            // Open buttons next
                            if !viewModel.permissionState.isGranted {
                                Button("Open Accessibility Settings") {
                                    viewModel.openAccessibilitySettings()
                                }
                            }

                            if !screenRecordingIsGranted {
                                Button("Open Screen Recording Settings") {
                                    viewModel.openScreenRecordingSettings()
                                }
                            }
                            
                            if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                                Button("Open Microphone Settings") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                            
                            if SFSpeechRecognizer.authorizationStatus() != .authorized {
                                Button("Open Speech Recognition Settings") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }

                            // Refresh last
                            Button("Refresh Permissions") {
                                viewModel.refreshPermissionStatus()
                                viewModel.refreshScreenUnderstandingReadiness()
                            }
                        }

                        if let permissionFeedbackText = viewModel.permissionFeedbackText {
                            Text(permissionFeedbackText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !screenRecordingIsGranted, let readinessFeedbackText = viewModel.screenUnderstandingReadinessFeedbackText {
                            Text(readinessFeedbackText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Current Frontmost App")
                                .font(.headline)

                            Spacer()

                            Button("Refresh Current Frontmost") {
                                viewModel.refreshCurrentFrontmostAppDebugInfo()
                            }
                        }

                        DisclosureGroup(
                            isExpanded: $isCurrentFrontmostExpanded,
                            content: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("This is what macOS reports as frontmost right now. If Owl Guide is active, this section may correctly show Owl Guide itself.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)

                                    DebugFieldRow(label: "App localized name", value: viewModel.currentFrontmostAppDebugInfo.localizedName)
                                    DebugFieldRow(label: "Bundle identifier", value: viewModel.currentFrontmostAppDebugInfo.bundleIdentifier)
                                    DebugFieldRow(label: "Process id", value: viewModel.currentFrontmostAppDebugInfo.processIdentifier)
                                    DebugFieldRow(label: "Is Owl Guide frontmost", value: yesNo(viewModel.currentFrontmostAppDebugInfo.representsOwlGuide))
                                    DebugFieldRow(label: "Accessibility permission", value: yesNo(viewModel.permissionState.isGranted))
                                    DebugFieldRow(label: "AX app reference created", value: yesNo(viewModel.currentFrontmostAppDebugInfo.appReferenceCreated))
                                    DebugFieldRow(label: "Focused window found", value: yesNo(viewModel.currentFrontmostAppDebugInfo.focusedWindowFound))
                                    DebugFieldRow(label: "Main window fallback found", value: yesNo(viewModel.currentFrontmostAppDebugInfo.mainWindowFallbackFound))
                                    DebugFieldRow(label: "Window title", value: viewModel.currentFrontmostAppDebugInfo.windowTitle)
                                    DebugFieldRow(label: "Window role", value: viewModel.currentFrontmostAppDebugInfo.windowRole)
                                    DebugFieldRow(label: "Window subrole", value: viewModel.currentFrontmostAppDebugInfo.windowSubrole)
                                    DebugFieldRow(label: "Lookup status", value: viewModel.currentFrontmostAppDebugInfo.statusMessage)
                                }
                                .padding(.top, 6)
                            },
                            label: {
                                Text(isCurrentFrontmostExpanded ? "Hide current-frontmost details" : "Show current-frontmost details")
                                    .font(.footnote.weight(.semibold))
                            }
                        )
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Captured External Target")
                                .font(.headline)

                            Spacer()

                            Button("Refresh External Target") {
                                viewModel.captureExternalTarget()
                            }
                        }
                        
                        DisclosureGroup(
                            isExpanded: $isCapturedTargetExpanded,
                            content: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("This cached non-OwlGuide target is what Owl Guide should preserve for later scanning.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)

                                    Text(viewModel.capturedExternalTargetStatusText)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)

                                    DebugFieldRow(label: "App localized name", value: viewModel.capturedExternalTargetDebugInfo.localizedName)
                                    DebugFieldRow(label: "Bundle identifier", value: viewModel.capturedExternalTargetDebugInfo.bundleIdentifier)
                                    DebugFieldRow(label: "Process id", value: viewModel.capturedExternalTargetDebugInfo.processIdentifier)
                                    DebugFieldRow(label: "Is Owl Guide frontmost", value: yesNo(viewModel.currentFrontmostAppDebugInfo.representsOwlGuide))
                                    DebugFieldRow(label: "Accessibility permission", value: yesNo(viewModel.permissionState.isGranted))
                                    DebugFieldRow(label: "AX app reference created", value: yesNo(viewModel.capturedExternalTargetDebugInfo.appReferenceCreated))
                                    DebugFieldRow(label: "Focused window found", value: yesNo(viewModel.capturedExternalTargetDebugInfo.focusedWindowFound))
                                    DebugFieldRow(label: "Main window fallback found", value: yesNo(viewModel.capturedExternalTargetDebugInfo.mainWindowFallbackFound))
                                    DebugFieldRow(label: "Window title", value: viewModel.capturedExternalTargetDebugInfo.windowTitle)
                                    DebugFieldRow(label: "Window role", value: viewModel.capturedExternalTargetDebugInfo.windowRole)
                                    DebugFieldRow(label: "Window subrole", value: viewModel.capturedExternalTargetDebugInfo.windowSubrole)
                                    DebugFieldRow(label: "Lookup status", value: viewModel.capturedExternalTargetDebugInfo.statusMessage)
                                }
                                .padding(.top, 6)
                            },
                            label: {
                                Text(isCapturedTargetExpanded ? "Hide Target Details" : "Show Target Details")
                                    .font(.footnote.weight(.semibold))
                            }
                        )
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Captured Window Child Scan")
                                .font(.headline)

                            Spacer()

                            Text(viewModel.scanState.statusTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(scanStatusColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(scanStatusColor.opacity(0.12))
                                )

                            Button("Scan Captured Window Children") {
                                viewModel.scanCapturedExternalTargetWindow()
                            }
                        }

                        Text("This scans AXChildren recursively from the captured external window with a limited depth and node cap.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(viewModel.scanState.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            ScanMetricView(label: "Depth limit", value: String(viewModel.scanDepthLimit))
                            ScanMetricView(label: "Raw nodes", value: String(viewModel.rawScannedElements.count))
                            ScanMetricView(label: "Filtered nodes", value: String(viewModel.filteredUsefulElements.count))
                            ScanMetricView(label: "Actionable candidates", value: String(viewModel.actionableCandidateCount))
                            ScanMetricView(label: "Actionable showing", value: String(viewModel.topActionableElements.count))
                            ScanMetricView(label: "Readable candidates", value: String(viewModel.readableCandidateCount))
                            ScanMetricView(label: "Readable showing", value: String(viewModel.topReadableElements.count))
                            ScanMetricView(label: "Node cap", value: String(viewModel.scanNodeLimit))
                            ScanMetricView(label: "Hit node cap", value: yesNo(viewModel.didHitScanNodeLimit))
                        }

                        if viewModel.scanChildLookupFailureCount > 0 {
                            Text("Some descendant child lookups failed during traversal: \(viewModel.scanChildLookupFailureCount)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button(viewModel.overlayPreviewRequested ? "Hide Overlay Preview" : "Show Overlay Preview") {
                                viewModel.toggleOverlayPreview()
                            }

                            Button(viewModel.windowAnchorRequested ? "Hide Window Anchor" : "Show Window Anchor") {
                                viewModel.toggleWindowAnchor()
                            }
                        }

                        Text(viewModel.overlayPreviewStatusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(viewModel.windowAnchorStatusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if !viewModel.overlayPreviewItems.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overlay Guidance Strip")
                                    .font(.headline)

                                Text("Shown overlay items stay listed here in rank order. Click a row to sync the detail pane.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(viewModel.overlayPreviewItems) { item in
                                        Button {
                                            viewModel.selectOverlayPreviewItem(item)
                                        } label: {
                                            OverlayGuidanceRow(
                                                item: item,
                                                isSelected: selectedElementID == item.id
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        } else if viewModel.isOverlayPreviewVisible {
                            Text("No overlay guidance items are currently available.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Picker("Scan Results Mode", selection: $scanResultsDisplayMode) {
                            ForEach(ScanResultsDisplayMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if showsRankedElements {
                            rankedResultsSection
                        } else if displayedScanElements.isEmpty {
                            Text(emptyStateText)
                                .font(.body)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(displayedScanElements) { element in
                                    let source: AXSelectionSource = scanResultsDisplayMode == .raw ? .raw : .filtered
                                    Button {
                                        if source == .raw {
                                            viewModel.selectRawElement(element)
                                        } else {
                                            viewModel.selectFilteredElement(element)
                                        }
                                    } label: {
                                        ScanElementCard(
                                            element: element,
                                            isSelected: selectedElementID == element.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        selectedElementDetailSection

                        screenUnderstandingSection
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 800, minHeight: 520)
        .onChange(of: debugSearchQuery) { _, newValue in
            applyDebugSearchExpansion(for: newValue)
        }
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private func verificationStatusColor(_ status: VerificationSnapshotStatus) -> Color {
        switch status {
        case .pass:
            return .green
        case .partial:
            return .orange
        case .fail:
            return .red
        case .notApplicable:
            return .secondary
        }
    }

    private func percentage(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private var scanStatusColor: Color {
        switch viewModel.scanState {
        case .idle:
            return .secondary
        case .success:
            return .green
        case .empty:
            return .orange
        case .failure:
            return .red
        }
    }

    private var screenUnderstandingStatusColor: Color {
        switch viewModel.screenUnderstandingState {
        case .idle:
            return .secondary
        case .loading:
            return .orange
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    private var languageModeText: String {
        let mode = viewModel.screenUnderstandingDebugInfo.replyLanguageMode.rawValue
        if let code = viewModel.screenUnderstandingDebugInfo.preferredResponseLanguageCode {
            return "\(mode) (\(code))"
        }

        return mode
    }

    private var watchFirstCategoryColor: Color {
        switch viewModel.screenUnderstandingDiagnosticCategory {
        case "Output-side truncation / partial JSON":
            return .orange
        case "Transport / API failure":
            return .red
        case "Image-size / request-payload pressure", "High-complexity screen fallback":
            return .yellow
        case "Low routing-confidence / classification risk":
            return .secondary
        default:
            return .green
        }
    }

    private var groundingStatusColor: Color {
        switch viewModel.screenUnderstandingGroundingStatusTitle {
        case "Grounded locally":
            return .green
        case "Partially grounded":
            return .orange
        case "Visual understanding only", "No target recommendation":
            return .secondary
        default:
            return .secondary
        }
    }

    private func watchMetricEmphasis(label: String, value: String) -> WatchMetricEmphasis {
        switch label {
        case "Failure stage":
            return value == "None" ? .neutral : .danger
        case "Likely failure cause":
            return viewModel.screenUnderstandingFailureStageLabel == "None" ? .neutral : .warning
        case "Finish reason":
            if value == "MAX_TOKENS" {
                return .danger
            }
            return value == "Unavailable" ? .neutral : .warning
        case "Parser outcome":
            if value == "fullJSON" || value == "none" {
                return .neutral
            }
            if value == "partialJSON" || value == "schemaMismatch" || value == "nonJSONText" {
                return .danger
            }
            return .warning
        default:
            return .neutral
        }
    }

    private var displayedScanElements: [AXElementNode] {
        switch scanResultsDisplayMode {
        case .raw:
            return viewModel.rawScannedElements
        case .filtered:
            return viewModel.filteredUsefulElements
        case .actionable, .readable:
            return []
        }
    }

    private var displayedRankedElements: [AXRankedElement] {
        switch scanResultsDisplayMode {
        case .actionable:
            return viewModel.topActionableElements
        case .readable:
            return viewModel.topReadableElements
        case .raw, .filtered:
            return []
        }
    }

    private var emptyStateText: String {
        switch scanResultsDisplayMode {
        case .raw:
            return "No raw AX nodes to display yet."
        case .filtered:
            return "No filtered useful elements were identified from the current raw AX scan."
        case .actionable:
            return actionableEmptyStateText
        case .readable:
            return readableEmptyStateText
        }
    }

    @ViewBuilder
    private var rankedResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(rankedSummaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if displayedRankedElements.isEmpty {
                Text(emptyStateText)
                    .font(.body)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(displayedRankedElements) { rankedElement in
                        Button {
                            if scanResultsDisplayMode == .actionable {
                                viewModel.selectActionableElement(rankedElement)
                            } else {
                                viewModel.selectReadableElement(rankedElement)
                            }
                        } label: {
                            RankedElementCard(
                                rankedElement: rankedElement,
                                isSelected: selectedElementID == rankedElement.element.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var showsRankedElements: Bool {
        scanResultsDisplayMode == .actionable || scanResultsDisplayMode == .readable
    }

    private var rankedSummaryText: String {
        switch scanResultsDisplayMode {
        case .actionable:
            return "Actionable candidates: \(viewModel.actionableCandidateCount). Showing: \(viewModel.topActionableElements.count) of \(min(viewModel.actionableCandidateCount, viewModel.rankedDisplayCap)) display slots."
        case .readable:
            return "Readable candidates: \(viewModel.readableCandidateCount). Showing: \(viewModel.topReadableElements.count) of \(min(viewModel.readableCandidateCount, viewModel.rankedDisplayCap)) display slots."
        case .raw, .filtered:
            return ""
        }
    }

    private var actionableEmptyStateText: String {
        if viewModel.actionableCandidateCount == 0 {
            return "No actionable ranked candidates were identified from the current filtered scan."
        }

        return "Actionable candidates were counted, but no actionable rows are currently available to display. Re-run the scan if this persists."
    }

    private var readableEmptyStateText: String {
        if viewModel.readableCandidateCount == 0 {
            return "No readable ranked candidates were identified from the current filtered scan."
        }

        return "Readable candidates were counted, but no readable rows are currently available to display. Re-run the scan if this persists."
    }

    private var selectedElementID: AXElementNode.ID? {
        viewModel.selectedElementInspection?.element.id
    }

    private var allReadinessItemsReady: Bool {
        !viewModel.screenUnderstandingReadiness.items.isEmpty
            && viewModel.screenUnderstandingReadiness.items.allSatisfy(\.isReady)
    }
    // MARK: - Autopilot Settings Panel

    @ViewBuilder
    private var autopilotSettingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Header ──────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "steeringwheel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Autopilot Settings")
                    .font(.headline)
                Spacer()
                Text(autopilotStatusBadge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(autopilotStatusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(autopilotStatusColor.opacity(0.12)))
            }

            Text("When enabled, Owl Guide will automatically perform actions after Gemini analysis completes and identifies target elements, with a configurable delay before execution. Recommended for use only after familiarizing yourself with the tool's behavior.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // ── Toggles ──────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动点击 (Auto Click)")
                            .font(.subheadline.weight(.medium))
                        Text("Automatically perform mouse clicks after identifying target elements")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.autoClickEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.blue)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动输入 (Auto Type)")
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("Use with caution: Directly inputs text into focused fields")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: $settings.autoTypeEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.orange)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )

            // ── Delay Slider ──────────────────────────────────────────
            if settings.autoClickEnabled || settings.autoTypeEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Pre-execution Countdown Delay")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(String(format: "%.1f seconds", settings.actionDelaySeconds))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.blue)
                    }
                    Slider(value: $settings.actionDelaySeconds, in: 1.0...5.0, step: 0.5)
                        .tint(.blue)
                    Text("After analysis completes, Owl Guide waits this duration before automatic execution, allowing you time to cancel if needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.blue.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: settings.autoClickEnabled || settings.autoTypeEnabled)
    }

    private var autopilotStatusBadge: String {
        if settings.autoClickEnabled && settings.autoTypeEnabled { return "Full Auto" }
        if settings.autoClickEnabled { return "Auto Click" }
        if settings.autoTypeEnabled { return "Auto Type" }
        return "Disabled"
    }

    private var autopilotStatusColor: Color {
        if settings.autoClickEnabled || settings.autoTypeEnabled { return .blue }
        return .secondary
    }

    @ViewBuilder
    private var backendIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Backend Integration")
                    .font(.headline)
                Spacer()
                Text(viewModel.activeBackendModeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.green.opacity(0.12))
                    )
            }
            
            DisclosureGroup(
                isExpanded: $isBackendExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Use one centralized source mode for the MVP chain: local sample, local backend, or deployed cloud backend.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Picker(
                            "Backend Mode",
                            selection: Binding(
                                get: { settings.backendDataSourceMode },
                                set: { newValue in
                                    settings.backendDataSourceMode = newValue
                                    DispatchQueue.main.async {
                                        viewModel.refreshScreenUnderstandingReadiness()
                                    }
                                }
                            )
                        ) {
                            ForEach(BackendDataSourceMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(viewModel.activeBackendModeDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Check /health") {
                                viewModel.checkBackendHealth()
                            }

                            Text(viewModel.backendHealthStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)
                },
                label: {
                    Text(isBackendExpanded ? "Hide Backend Settings" : "Show Backend Settings")
                        .font(.footnote.weight(.semibold))
                }
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var debugQuickFindSection: some View {

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Debug Quick Find")
                    .font(.headline)

                Spacer()

                if !debugSearchQuery.isEmpty {
                    Button("Clear") {
                        debugSearchQuery = ""
                    }
                    .font(.footnote)
                }
            }

            TextField("Search runtime, signing, permission, URL, parser...", text: $debugSearchQuery)
                .textFieldStyle(.roundedBorder)

            if debugSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Type a keyword to surface the matching debug fields here without scrolling through the whole panel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if debugSearchMatches.isEmpty {
                Text("No matching debug fields for “\(debugSearchQuery)”.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(debugSearchMatches) { match in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.section)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(match.label)
                                .font(.caption.weight(.semibold))

                            Text(match.value)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var selectedElementDetailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Selected Element Detail")
                    .font(.headline)

                Spacer()

                if viewModel.selectedElementInspection != nil {
                    Button("Clear Selection") {
                        viewModel.clearSelectedElementInspection()
                    }
                }
            }

            if let selected = viewModel.selectedElementInspection {
                Text("Selected from: \(selected.source.rawValue)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                DebugFieldRow(label: "Display name", value: selected.element.displayName)
                DebugFieldRow(label: "Path", value: selected.element.path)
                DebugFieldRow(label: "Role", value: selected.element.role)
                DebugFieldRow(label: "Subrole", value: selected.element.subrole)
                DebugFieldRow(label: "Title", value: selected.element.title)
                DebugFieldRow(label: "Label", value: selected.element.label)
                DebugFieldRow(label: "Value", value: selected.element.value)
                DebugFieldRow(label: "Position", value: selected.element.positionSummary)
                DebugFieldRow(label: "Size", value: selected.element.sizeSummary)
                DebugFieldRow(label: "Depth", value: String(selected.element.depth))
                DebugFieldRow(label: "Enabled", value: selected.element.enabledSummary)
                DebugFieldRow(label: "Focused", value: selected.element.focusedSummary)
                DebugFieldRow(label: "Flags", value: selected.element.flagsSummary)

                if let score = selected.score {
                    DebugFieldRow(label: "Score", value: String(score))
                }

                if !selected.reasonTags.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reason tags")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FlowTagRow(tags: selected.reasonTags)
                    }
                }
            } else {
                Text("Select a row from any scan view to inspect its details.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var watchFirstSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Watch First")
                    .font(.headline)
                Spacer()
                Text(viewModel.screenUnderstandingDiagnosticCategory)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(watchFirstCategoryColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(watchFirstCategoryColor.opacity(0.12))
                    )
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                WatchMetricCard(label: "Total elapsed", value: durationText(viewModel.screenUnderstandingDebugInfo.totalElapsedTimeMilliseconds))
                WatchMetricCard(label: "Screenshot prep", value: durationText(viewModel.screenUnderstandingDebugInfo.screenshotPreparationTimeMilliseconds))
                WatchMetricCard(label: "Gemini round-trip", value: durationText(viewModel.screenUnderstandingDebugInfo.geminiRoundTripTimeMilliseconds))
                WatchMetricCard(
                    label: "Failure stage",
                    value: viewModel.screenUnderstandingFailureStageLabel,
                    emphasis: watchMetricEmphasis(
                        label: "Failure stage",
                        value: viewModel.screenUnderstandingFailureStageLabel
                    )
                )
                WatchMetricCard(
                    label: "Likely failure cause",
                    value: viewModel.screenUnderstandingLikelyFailureCause,
                    emphasis: watchMetricEmphasis(
                        label: "Likely failure cause",
                        value: viewModel.screenUnderstandingLikelyFailureCause
                    )
                )
                WatchMetricCard(
                    label: "Finish reason",
                    value: viewModel.screenUnderstandingDebugInfo.finishReason ?? "Unavailable",
                    emphasis: watchMetricEmphasis(
                        label: "Finish reason",
                        value: viewModel.screenUnderstandingDebugInfo.finishReason ?? "Unavailable"
                    )
                )
                WatchMetricCard(
                    label: "Parser outcome",
                    value: viewModel.screenUnderstandingDebugInfo.parserOutcome.rawValue,
                    emphasis: watchMetricEmphasis(
                        label: "Parser outcome",
                        value: viewModel.screenUnderstandingDebugInfo.parserOutcome.rawValue
                    )
                )
                WatchMetricCard(label: "Original screenshot", value: watchFirstScreenshotValue(
                    width: viewModel.screenUnderstandingDebugInfo.originalScreenshotWidth,
                    height: viewModel.screenUnderstandingDebugInfo.originalScreenshotHeight,
                    bytes: viewModel.screenUnderstandingDebugInfo.originalScreenshotByteCount
                ))
                WatchMetricCard(label: "Gemini send-image", value: watchFirstScreenshotValue(
                    width: viewModel.screenUnderstandingDebugInfo.sendImageWidth,
                    height: viewModel.screenUnderstandingDebugInfo.sendImageHeight,
                    bytes: viewModel.screenUnderstandingDebugInfo.sendImageByteCount
                ))
            }

            Text(viewModel.screenUnderstandingDiagnosticNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.screenUnderstandingFailureStageLabel != "None" {
                Text(viewModel.screenUnderstandingFailureStageSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    @ViewBuilder
    private var geminiSetupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gemini Setup")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Before Owl Guide can describe the current screen, it needs a few permissions and setup items ready.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Refresh Readiness") {
                    viewModel.refreshScreenUnderstandingReadiness()
                }

                if !viewModel.permissionState.isGranted {
                    Button("Open Accessibility Settings") {
                        viewModel.openAccessibilitySettings()
                    }
                }

                if let screenRecordingItem = viewModel.screenUnderstandingReadiness.items.first(where: { $0.id == "screen-recording" }),
                   !screenRecordingItem.isReady {
                    Button("Open Screen Recording Settings") {
                        viewModel.openScreenRecordingSettings()
                    }

                    Button("Request Screen Recording") {
                        viewModel.requestScreenRecordingPermission()
                    }
                }

                if let capturedTargetItem = viewModel.screenUnderstandingReadiness.items.first(where: { $0.id == "captured-target" }),
                   !capturedTargetItem.isReady {
                    Button("Refresh External Target") {
                        viewModel.captureExternalTarget()
                    }
                }
            }

            DisclosureGroup(
                isExpanded: Binding(
                    get: { allReadinessItemsReady ? isGeminiSetupExpanded : true },
                    set: { isGeminiSetupExpanded = $0 }
                ),
                content: {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Gemini API Key")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if viewModel.isGeminiAPIKeyEditable {
                                SecureField("Enter Gemini API key", text: $viewModel.geminiAPIKeyDraft)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                TextField("", text: .constant(viewModel.geminiAPIKeyDraft))
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(true)
                                    .privacySensitive()
                            }

                            HStack(spacing: 12) {
                                Button("Save Key") {
                                    viewModel.saveGeminiAPIKey()
                                }
                                .disabled(!viewModel.canSaveGeminiAPIKey)

                                Button("Clear Saved Key") {
                                    viewModel.clearGeminiAPIKey()
                                }
                                .disabled(!viewModel.hasSavedGeminiAPIKey)
                            }

                            Text("Current key source: \(viewModel.screenUnderstandingDebugInfo.keySource.rawValue)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            if viewModel.hasSavedGeminiAPIKey {
                                Text("A Gemini API key is saved locally. Clear Saved Key before entering a different one.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Toggle(isOn: $settings.useCustomGeminiAPIKey) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use my own Gemini API Key")
                                        .font(.subheadline.weight(.medium))
                                    Text("Requests will be sent directly to Google servers, not passing through our backend. Unlimited usage, 100% private.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .disabled(!viewModel.hasSavedGeminiAPIKey)
                            .padding(.top, 4)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Gemini Model")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            TextField("Gemini model name", text: $settings.geminiModel)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("Default: gemini-3-flash-preview. Optional: gemini-3.1-pro-preview. Takes effect for both Local Backend and custom API Key mode.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Readiness")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(viewModel.screenUnderstandingReadiness.items) { item in
                                ScreenUnderstandingReadinessRow(item: item)
                            }
                        }
                    }
                    .padding(.top, 6)
                },
                label: {
                    Text(allReadinessItemsReady ? "Show readiness and setup details" : "Readiness details")
                        .font(.footnote.weight(.semibold))
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var screenRecordingReadinessItem: ScreenUnderstandingReadinessItem? {
        viewModel.screenUnderstandingReadiness.items.first(where: { $0.id == "screen-recording" })
    }

    private var screenRecordingIsGranted: Bool {
        screenRecordingReadinessItem?.isReady ?? false
    }

    private var screenRecordingSummary: String {
        if screenRecordingIsGranted {
            return "Owl Guide can capture the current app window image."
        }

        return "Owl Guide needs Screen Recording permission before it can capture another app's window."
    }

    private var screenRecordingGuidance: String {
        if screenRecordingIsGranted {
            return "Screen Recording is enabled. Owl Guide can use screenshots together with local accessibility data."
        }

        return "Open System Settings > Privacy & Security > Screen Recording, enable Owl Guide, then quit and reopen the app if macOS still does not allow capture."
    }

    @ViewBuilder
    private func permissionStatusRow(title: String, isGranted: Bool, summary: String, guidance: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(isGranted ? "Granted" : "Missing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isGranted ? .green : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill((isGranted ? Color.green : Color.orange).opacity(0.12))
                    )
            }

            Text(summary)
                .font(.body)

            Text(guidance)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var analysisDebugSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Analysis Debug Preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            DebugFieldRow(label: "Gemini reply summary", value: viewModel.relayGeminiReplySummary)
            DebugFieldRow(label: "Chosen relay mode", value: viewModel.relayPresentationModeTitle)
            DebugFieldRow(label: "Concrete local target resolved", value: yesNo(viewModel.relayHasConcreteLocalTarget))
            DebugFieldRow(label: "Guided target origin", value: viewModel.guidedTargetOriginTitle)
            DebugFieldRow(label: "Relay confidence note", value: viewModel.relayConfidenceNote)
            DebugFieldRow(label: "Relay downgrade reason", value: viewModel.relayDowngradeReason)
            DebugFieldRow(label: "Gemini model", value: viewModel.screenUnderstandingDebugInfo.modelName)
            DebugFieldRow(label: "Analysis mode", value: viewModel.screenUnderstandingDebugInfo.analysisMode.rawValue)
            DebugFieldRow(label: "Payload mode", value: viewModel.screenUnderstandingDebugInfo.payloadMode.rawValue)
            DebugFieldRow(label: "Routing confidence", value: viewModel.lastScenarioContext?.confidence.displayName ?? "Unavailable")

            DisclosureGroup(
                isExpanded: $isBrowserDiagnosticsExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        DebugFieldRow(label: "Browser-aware capture attempted", value: yesNo(viewModel.screenUnderstandingDebugInfo.browserCaptureAttempted))
                        DebugFieldRow(label: "Detected browser", value: viewModel.screenUnderstandingDebugInfo.browserName ?? "Unavailable")
                        DebugFieldRow(label: "Failure category", value: viewModel.screenUnderstandingDebugInfo.browserFailureCategory ?? "None")
                        DebugFieldRow(label: "Context mode", value: viewModel.screenUnderstandingDebugInfo.browserContextUsageDescription)
                        DebugFieldRow(label: "URL retrieval", value: viewModel.screenUnderstandingDebugInfo.browserURLRetrievalStatus)
                        DebugFieldRow(label: "Current URL", value: viewModel.screenUnderstandingDebugInfo.browserCurrentURL ?? "Unavailable")
                        DebugFieldRow(label: "Page title retrieval", value: viewModel.screenUnderstandingDebugInfo.browserTitleRetrievalStatus)
                        DebugFieldRow(label: "Page title", value: viewModel.screenUnderstandingDebugInfo.browserPageTitle ?? "Unavailable")
                        DebugFieldRow(label: "Page text summary", value: viewModel.screenUnderstandingDebugInfo.browserTextSummaryStatus)
                        DebugFieldRow(label: "Primary entry points", value: String(viewModel.screenUnderstandingDebugInfo.browserPrimaryEntryPointCount))
                        DebugFieldRow(label: "Resulting page type", value: viewModel.lastScenarioContext?.likelyPageType ?? "Unavailable")
                        DebugFieldRow(label: "Likely user goal", value: viewModel.screenUnderstandingResult?.likelyUserGoal ?? "Unavailable")
                        DebugFieldRow(label: "Relay mode", value: viewModel.relayPresentationModeTitle)
                    }
                    .padding(.top, 6)
                },
                label: {
                    Text("Browser-aware capture")
                        .font(.footnote.weight(.semibold))
                }
            )

            DisclosureGroup(
                isExpanded: $isScreenshotDiagnosticsExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        DebugFieldRow(label: "Original screenshot MIME type", value: viewModel.screenUnderstandingDebugInfo.originalScreenshotMimeType)
                        DebugFieldRow(
                            label: "Original screenshot size",
                            value: screenshotSizeText(
                                width: viewModel.screenUnderstandingDebugInfo.originalScreenshotWidth,
                                height: viewModel.screenUnderstandingDebugInfo.originalScreenshotHeight
                            )
                        )
                        DebugFieldRow(
                            label: "Original screenshot bytes",
                            value: viewModel.screenUnderstandingDebugInfo.originalScreenshotByteCount.map(String.init) ?? "Unavailable"
                        )
                        DebugFieldRow(label: "Original screenshot processing", value: viewModel.screenUnderstandingDebugInfo.originalScreenshotProcessingDescription)
                        DebugFieldRow(label: "Gemini send-image MIME type", value: viewModel.screenUnderstandingDebugInfo.sendImageMimeType)
                        DebugFieldRow(
                            label: "Gemini send-image size",
                            value: screenshotSizeText(
                                width: viewModel.screenUnderstandingDebugInfo.sendImageWidth,
                                height: viewModel.screenUnderstandingDebugInfo.sendImageHeight
                            )
                        )
                        DebugFieldRow(
                            label: "Gemini send-image bytes",
                            value: viewModel.screenUnderstandingDebugInfo.sendImageByteCount.map(String.init) ?? "Unavailable"
                        )
                        DebugFieldRow(label: "Gemini send-image downscaled", value: boolText(viewModel.screenUnderstandingDebugInfo.sendImageDidDownscale))
                        DebugFieldRow(label: "Gemini send-image lossy compression", value: boolText(viewModel.screenUnderstandingDebugInfo.sendImageUsedLossyCompression))
                        DebugFieldRow(label: "Gemini send-image processing", value: viewModel.screenUnderstandingDebugInfo.sendImageProcessingDescription)
                    }
                    .padding(.top, 6)
                },
                label: {
                    Text("Screenshot details")
                        .font(.footnote.weight(.semibold))
                }
            )

            DisclosureGroup(
                isExpanded: $isPayloadDiagnosticsExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        DebugFieldRow(label: "Analysis mode detail", value: viewModel.screenUnderstandingDebugInfo.complexityDiagnostics.reason)
                        DebugFieldRow(label: "Payload routing", value: viewModel.screenUnderstandingDebugInfo.payloadRouting.reason)
                        DebugFieldRow(label: "Routed skill", value: viewModel.lastScenarioContext?.selectedSkill.displayName ?? "Unavailable")
                        DebugFieldRow(label: "Response MIME type", value: viewModel.screenUnderstandingDebugInfo.responseMimeType)
                        DebugFieldRow(label: "Schema mode enabled", value: yesNo(viewModel.screenUnderstandingDebugInfo.responseSchemaModeEnabled))
                        DebugFieldRow(label: "Request note", value: viewModel.screenUnderstandingDebugInfo.requestDiagnosticsNote)
                        DebugFieldRow(label: "Max output tokens", value: String(viewModel.screenUnderstandingDebugInfo.maxOutputTokens))
                        DebugFieldRow(label: "Actionable candidates available", value: String(viewModel.screenUnderstandingDebugInfo.actionableCandidatesAvailable))
                        DebugFieldRow(label: "Readable candidates available", value: String(viewModel.screenUnderstandingDebugInfo.readableCandidatesAvailable))
                        DebugFieldRow(label: "Actionable candidates sent", value: String(viewModel.screenUnderstandingDebugInfo.actionableCandidatesSent))
                        DebugFieldRow(label: "Readable candidates sent", value: String(viewModel.screenUnderstandingDebugInfo.readableCandidatesSent))
                        DebugFieldRow(label: "Meaningful readable candidates", value: String(viewModel.screenUnderstandingDebugInfo.payloadRouting.meaningfulReadableCandidateCount))
                        DebugFieldRow(label: "Filtered useful elements", value: String(viewModel.screenUnderstandingDebugInfo.complexityDiagnostics.filteredUsefulElementCount))
                        DebugFieldRow(label: "Sampled candidate count", value: String(viewModel.screenUnderstandingDebugInfo.complexityDiagnostics.sampledCandidateCount))
                        DebugFieldRow(label: "Generic candidates", value: "\(viewModel.screenUnderstandingDebugInfo.payloadRouting.genericCandidateCount) / \(viewModel.screenUnderstandingDebugInfo.payloadRouting.totalCandidatesEvaluated)")
                        DebugFieldRow(label: "Generic candidate ratio", value: percentage(viewModel.screenUnderstandingDebugInfo.payloadRouting.genericCandidateRatio))
                        DebugFieldRow(label: "Container/window-control ratio", value: percentage(viewModel.screenUnderstandingDebugInfo.payloadRouting.containerOrWindowControlRatio))
                        DebugFieldRow(label: "Top candidates mostly generic", value: yesNo(viewModel.screenUnderstandingDebugInfo.payloadRouting.topCandidatesMostlyGeneric))
                        DebugFieldRow(label: "Complexity send-image long edge", value: String(viewModel.screenUnderstandingDebugInfo.complexityDiagnostics.screenshotLongEdge))
                        DebugFieldRow(label: "Complexity send-image bytes", value: String(viewModel.screenUnderstandingDebugInfo.complexityDiagnostics.sendImageByteCount))
                        DebugFieldRow(label: "Compact context characters", value: String(viewModel.screenUnderstandingDebugInfo.contextCharacterCount))
                    }
                    .padding(.top, 6)
                },
                label: {
                    Text("Payload and complexity diagnostics")
                        .font(.footnote.weight(.semibold))
                }
            )

            DisclosureGroup(
                isExpanded: $isResponseDiagnosticsExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        DebugFieldRow(label: "HTTP status", value: viewModel.screenUnderstandingDebugInfo.httpStatusCode.map(String.init) ?? "Unavailable")
                        DebugFieldRow(label: "Finish reason", value: viewModel.screenUnderstandingDebugInfo.finishReason ?? "Unavailable")
                        DebugFieldRow(label: "Finish message", value: viewModel.screenUnderstandingDebugInfo.finishMessage ?? "Unavailable")
                        DebugFieldRow(label: "Prompt tokens", value: viewModel.screenUnderstandingDebugInfo.promptTokenCount.map(String.init) ?? "Unavailable")
                        DebugFieldRow(label: "Output tokens", value: viewModel.screenUnderstandingDebugInfo.outputTokenCount.map(String.init) ?? "Unavailable")
                        DebugFieldRow(label: "Total tokens", value: viewModel.screenUnderstandingDebugInfo.totalTokenCount.map(String.init) ?? "Unavailable")
                        DebugFieldRow(label: "Raw response length", value: String(viewModel.screenUnderstandingDebugInfo.rawResponseLength))
                        DebugFieldRow(label: "Parser outcome", value: viewModel.screenUnderstandingDebugInfo.parserOutcome.rawValue)
                        DebugFieldRow(label: "Failure source", value: viewModel.screenUnderstandingDebugInfo.failureSource?.rawValue ?? "None")
                        DebugFieldRow(label: "Transport error", value: viewModel.screenUnderstandingDebugInfo.transportError ?? "None")

                        HStack(spacing: 12) {
                            Button("Copy Raw Response") {
                                viewModel.copyRawGeminiResponse()
                            }

                            Button("Copy Request Summary") {
                                viewModel.copyGeminiRequestSummary()
                            }
                        }
                    }
                    .padding(.top, 6)
                },
                label: {
                    Text("Response diagnostics")
                        .font(.footnote.weight(.semibold))
                }
            )

            DisclosureGroup(
                isExpanded: $isRequestSummaryExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 10) {
                        DiagnosticTextArea(
                            title: "Request Summary",
                            text: viewModel.screenUnderstandingDebugInfo.requestSummary
                        )

                        DiagnosticTextArea(
                            title: "Raw Gemini Response",
                            text: viewModel.screenUnderstandingDebugInfo.rawResponseText
                        )

                        DiagnosticTextArea(
                            title: "Recovered JSON",
                            text: viewModel.screenUnderstandingDebugInfo.recoveredJSONText
                        )
                    }
                    .padding(.top, 6)
                },
                label: {
                    Text("Raw request and response text")
                        .font(.footnote.weight(.semibold))
                }
            )

            DisclosureGroup(
                isExpanded: $isAdvancedAppDebugExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        DebugFieldRow(label: "Accessibility permission", value: yesNo(viewModel.permissionState.isGranted))
                        DebugFieldRow(label: "Runtime bundle id", value: viewModel.appRuntimeIdentityDebugInfo.bundleIdentifier)
                        DebugFieldRow(label: "Runtime app path", value: viewModel.appRuntimeIdentityDebugInfo.bundlePath)
                        DebugFieldRow(label: "Runtime executable", value: viewModel.appRuntimeIdentityDebugInfo.executablePath)
                        DebugFieldRow(label: "Signing state", value: viewModel.appRuntimeIdentityDebugInfo.signingState)
                        DebugFieldRow(label: "Signing detail", value: viewModel.appRuntimeIdentityDebugInfo.signingDetail)
                        DebugFieldRow(label: "Current frontmost app", value: viewModel.currentFrontmostAppDebugInfo.localizedName)
                        DebugFieldRow(label: "Current frontmost window", value: viewModel.currentFrontmostAppDebugInfo.windowTitle)
                        DebugFieldRow(label: "Current frontmost status", value: viewModel.currentFrontmostAppDebugInfo.statusMessage)
                    }
                    .padding(.top, 6)
                },
                label: {
                    Text("Advanced app and permission debug")
                        .font(.footnote.weight(.semibold))
                }
            )
        }
    }

    @ViewBuilder
    private var verificationSnapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verification Snapshot")
                        .font(.headline)

                    Text("Use this compact view to judge whether the current analysis basically passed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(viewModel.verificationSnapshotEvidenceStateTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                        )

                    Text(analysisDebugPresentationMode.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), alignment: .topLeading)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(viewModel.verificationSnapshotFields) { field in
                    verificationSnapshotField(field)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    @ViewBuilder
    private func verificationSnapshotField(_ field: VerificationSnapshotField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(field.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(field.status.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(verificationStatusColor(field.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(verificationStatusColor(field.status).opacity(0.12))
                    )
            }

            if let detail = field.detail {
                Text(detail)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var screenUnderstandingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gemini Screen Understanding")
                    .font(.headline)

                Spacer()

                Text(viewModel.screenUnderstandingState.statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(screenUnderstandingStatusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(screenUnderstandingStatusColor.opacity(0.12))
                    )

                Button("Analyze Current Screen") {
                    viewModel.analyzeCurrentScreen()
                }
                .disabled(!viewModel.screenUnderstandingReadiness.canAnalyze || viewModel.screenUnderstandingState.isLoading)
            }

            watchFirstSection

            HStack {
                Text("Debug View")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Debug View", selection: $analysisDebugPresentationMode) {
                    ForEach(AnalysisDebugPresentationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            verificationSnapshotSection

            VStack(alignment: .leading, spacing: 12) {
                if !viewModel.screenUnderstandingReadiness.canAnalyze,
                   let blockingReason = viewModel.screenUnderstandingReadiness.blockingReason {
                    Text("Analysis is unavailable: \(blockingReason)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let readinessFeedbackText = viewModel.screenUnderstandingReadinessFeedbackText {
                    Text(readinessFeedbackText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let targetSnapshot = viewModel.screenUnderstandingTargetSnapshot {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Analysis Target")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        DebugFieldRow(label: "App", value: targetSnapshot.appName)
                        DebugFieldRow(label: "Window", value: targetSnapshot.displayWindowTitle)
                        DebugFieldRow(label: "Bundle identifier", value: targetSnapshot.bundleIdentifier)
                        DebugFieldRow(label: "Process id", value: targetSnapshot.processIdentifier)
                        DebugFieldRow(label: "Window role", value: targetSnapshot.windowRole)
                        DebugFieldRow(label: "Window subrole", value: targetSnapshot.windowSubrole)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Analysis Progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DebugFieldRow(label: "Stage", value: viewModel.screenUnderstandingProgressStage.title)

                    Text(viewModel.screenUnderstandingProgressStage.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(viewModel.screenUnderstandingState.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let owlFallbackMessage = viewModel.owlFallbackMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("While Owl Guide is still working")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(owlFallbackMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Routing Summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DebugFieldRow(label: "Failure stage", value: viewModel.screenUnderstandingFailureStageLabel)
                    DebugFieldRow(label: "Likely failure cause", value: viewModel.screenUnderstandingLikelyFailureCause)
                    DebugFieldRow(label: "Invocation mode", value: viewModel.screenUnderstandingDebugInfo.invocationMode.rawValue)
                    DebugFieldRow(label: "User request present", value: yesNo(viewModel.screenUnderstandingDebugInfo.userRequestPresent))
                    DebugFieldRow(label: "Auto-analysis fired", value: yesNo(viewModel.screenUnderstandingDebugInfo.autoAnalysisFired))
                    DebugFieldRow(label: "Idle timeout", value: "\(viewModel.screenUnderstandingDebugInfo.idleTimeoutSeconds ?? viewModel.owlPassiveAutoLookDelaySeconds)s")
                    DebugFieldRow(label: "Focus lock active", value: yesNo(viewModel.screenUnderstandingDebugInfo.focusLockActive))
                    DebugFieldRow(label: "Draft preserved", value: yesNo(viewModel.screenUnderstandingDebugInfo.draftTextPreserved))
                    DebugFieldRow(label: "Fresh auto-capture", value: yesNo(viewModel.screenUnderstandingDebugInfo.autoAnalysisUsedFreshCapture))
                    DebugFieldRow(label: "Timer restarted for target change", value: yesNo(viewModel.screenUnderstandingDebugInfo.timerRestartedDueToContextChange))
                    DebugFieldRow(label: "Reply language mode", value: languageModeText)
                    DebugFieldRow(label: "Analysis mode", value: viewModel.screenUnderstandingDebugInfo.analysisMode.rawValue)
                    DebugFieldRow(label: "Payload mode", value: viewModel.screenUnderstandingDebugInfo.payloadMode.rawValue)
                    DebugFieldRow(label: "Routing confidence", value: viewModel.lastScenarioContext?.confidence.displayName ?? "Unavailable")
                    DebugFieldRow(label: "Page type", value: viewModel.screenScenarioGuidance?.context.likelyPageType ?? "Unavailable")
                    DebugFieldRow(label: "Host", value: viewModel.screenScenarioGuidance?.context.browserHostname ?? "Unavailable")
                    DebugFieldRow(label: "Task thread", value: viewModel.currentTaskThreadStatusTitle)
                    DebugFieldRow(label: "Chosen intent", value: viewModel.currentTaskThread?.chosenIntent.displayName ?? "Unavailable")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )

            geminiSetupSection

            if viewModel.screenUnderstandingState.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let result = viewModel.screenUnderstandingResult {
                VStack(alignment: .leading, spacing: 10) {
                    resultLandingSection(result)

                    if let scenarioGuidance = viewModel.screenScenarioGuidance {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("First Response")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            DebugFieldRow(label: "Context recognition", value: scenarioGuidance.firstResponse.contextRecognition)
                            DebugFieldRow(label: "Primary task", value: scenarioGuidance.firstResponse.primaryLikelyTask)
                            DebugFieldRow(label: "Backup task", value: scenarioGuidance.firstResponse.backupLikelyTask)
                            DebugFieldRow(label: "Safe first step", value: scenarioGuidance.firstResponse.safeFirstStep)

                            if let clarificationQuestion = scenarioGuidance.firstResponse.clarificationQuestion {
                                DebugFieldRow(label: "Question", value: clarificationQuestion)
                            }

                            HStack(alignment: .center, spacing: 8) {
                                Text("Page type: \(scenarioGuidance.context.likelyPageType)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let browserHostname = scenarioGuidance.context.browserHostname {
                                    Text("Host: \(browserHostname)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text("Confidence: \(scenarioGuidance.context.confidence.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                        )
                    }

                    intentConfirmationSection

                    guidedStepSection

                    VStack(alignment: .leading, spacing: 8) {
                        DebugFieldRow(label: "Page summary", value: result.pageSummary)
                        DebugFieldRow(label: "Likely user goal", value: result.likelyUserGoal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended Targets")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(result.recommendedTargets) { target in
                            recommendedTargetCard(target)
                        }
                    }

                    if !result.cautionNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Caution Notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(Array(result.cautionNotes.enumerated()), id: \.offset) { _, note in
                                Text("• \(note)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }

            if analysisDebugPresentationMode == .verbose {
                analysisDebugSection
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func resultLandingSection(_ result: ScreenUnderstandingResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Result at a Glance")
                        .font(.headline)

                    Text("This is Owl Guide's current best read of the screen and how grounded that read is locally.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(viewModel.screenUnderstandingGroundingStatusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(groundingStatusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(groundingStatusColor.opacity(0.12))
                    )
            }

            ResultSummaryRow(
                label: "What Owl sees",
                value: viewModel.screenScenarioGuidance?.firstResponse.contextRecognition ?? result.pageSummary
            )
            ResultSummaryRow(
                label: "Most likely task",
                value: viewModel.screenScenarioGuidance?.firstResponse.primaryLikelyTask ?? result.likelyUserGoal
            )
            ResultSummaryRow(
                label: "Safe first step",
                value: viewModel.screenScenarioGuidance?.firstResponse.safeFirstStep
                    ?? "Review the top recommendation before taking action."
            )
            ResultSummaryRow(
                label: "Grounding",
                value: viewModel.screenUnderstandingGroundingSummary
            )

            if let selectedLabel = viewModel.selectedRecommendedTargetLabel,
               let selectedSummary = viewModel.selectedRecommendedTargetSummary {
                ResultSummaryRow(
                    label: "Selected recommendation",
                    value: "\(selectedLabel)\n\(selectedSummary)"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    @ViewBuilder
    private var intentConfirmationSection: some View {
        if !viewModel.scenarioIntentOptions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Intent Confirmation")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(intentConfirmationSummaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.scenarioIntentOptions) { option in
                        Button {
                            viewModel.confirmScenarioIntent(option.intent)
                        } label: {
                            IntentOptionCard(
                                option: option,
                                isSelected: viewModel.isIntentSelected(option.intent),
                                isConfirmed: viewModel.isIntentConfirmed(option.intent)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }

    @ViewBuilder
    private var guidedStepSection: some View {
        if let currentTaskThread = viewModel.currentTaskThread,
           let guidedStep = viewModel.guidedStepResponse {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(guidedStep.title)
                        .font(.headline)

                    Spacer()

                    Text(currentTaskThread.isConfirmed ? "Confirmed" : "Tentative")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(currentTaskThread.isConfirmed ? .green : .orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill((currentTaskThread.isConfirmed ? Color.green : Color.orange).opacity(0.12))
                        )
                }

                ResultSummaryRow(label: "Chosen intent", value: currentTaskThread.chosenIntent.displayName)
                ResultSummaryRow(label: "Current page type", value: currentTaskThread.currentPageType)
                ResultSummaryRow(label: "Next step", value: guidedStep.nextStep)
                ResultSummaryRow(label: "Relay mode", value: viewModel.relayPresentationModeTitle)
                ResultSummaryRow(label: "Highlight status", value: viewModel.guidedStepHighlightStatusTitle)
                ResultSummaryRow(label: "Concrete local target", value: viewModel.guidedStepConcreteTargetStatusText)
                ResultSummaryRow(label: "Chosen target source", value: viewModel.guidedTargetOriginTitle)
                ResultSummaryRow(label: "Confidence note", value: viewModel.relayConfidenceNote)

                if let targetType = viewModel.guidedStepTargetTypeTitle {
                    ResultSummaryRow(label: "Target type", value: targetType)
                }

                ResultSummaryRow(label: "Grounding reason", value: viewModel.guidedStepGroundingReasonText)

                if viewModel.guidedTargetOriginNeedsExplanation {
                    ResultSummaryRow(
                        label: "Target origin note",
                        value: "The guided step target differs from the current visual-only recommendation list."
                    )
                }

                if viewModel.relayDowngradeReason != "None" {
                    ResultSummaryRow(label: "Why Owl Guide downgraded", value: viewModel.relayDowngradeReason)
                }

                if let safetyNote = guidedStep.safetyNote {
                    ResultSummaryRow(label: "Safety note", value: safetyNote)
                }

                ResultSummaryRow(label: "Thread decision", value: currentTaskThread.continuationSummary)

                if let clarificationQuestion = guidedStep.clarificationQuestion,
                   !currentTaskThread.isConfirmed {
                    ResultSummaryRow(label: "Before continuing", value: clarificationQuestion)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }

    private var intentConfirmationSummaryText: String {
        if let currentTaskThread = viewModel.currentTaskThread {
            if currentTaskThread.isConfirmed {
                return "The current goal is confirmed. You can still switch to a different goal if Owl Guide picked the wrong one."
            }

            return "Choose the closest goal so Owl Guide can guide one safe step at a time."
        }

        return "Choose the closest goal so Owl Guide can guide one safe step at a time."
    }

    @ViewBuilder
    private func recommendedTargetCard(_ target: ScreenUnderstandingRecommendedTarget) -> some View {
        let linkStatus = viewModel.localLinkStatus(for: target)
        let isSelected = viewModel.isRecommendedTargetSelected(target)
        let content = recommendedTargetCardContent(target, linkStatus: linkStatus, isSelected: isSelected)

        if linkStatus.isLinked {
            Button {
                viewModel.inspectRecommendedTarget(target)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func recommendedTargetCardContent(
        _ target: ScreenUnderstandingRecommendedTarget,
        linkStatus: ScreenUnderstandingLocalLinkStatus,
        isSelected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(target.rank).")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(target.label)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(target.whyThisMatters)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(linkStatus.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(linkStatus.isLinked ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill((linkStatus.isLinked ? Color.green : Color.secondary).opacity(0.12))
                    )
            }

            Text(linkStatus.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !target.relatedLocalElement.isEmpty {
                Text("Local element id: \(target.relatedLocalElement)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if linkStatus.isLinked {
                Text(isSelected ? "Shown in current overlay" : "Inspect and Show in Overlay")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("Visual-only suggestion")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        )
    }

    private func screenshotSizeText(width: Int?, height: Int?) -> String {
        guard let width, let height else {
            return "Unavailable"
        }

        return "\(width) × \(height)"
    }

    private func watchFirstScreenshotValue(width: Int?, height: Int?, bytes: Int?) -> String {
        let size = screenshotSizeText(width: width, height: height)
        let byteText = bytes.map(String.init) ?? "Unavailable"
        return "\(size)\n\(byteText) bytes"
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return value ? "Yes" : "No"
    }

    private func durationText(_ value: Int?) -> String {
        guard let value else {
            return "Unavailable"
        }

        if value >= 1000 {
            return String(format: "%.2fs", Double(value) / 1000.0)
        }

        return "\(value) ms"
    }

    private var debugSearchMatches: [DebugSearchMatch] {
        let trimmedQuery = debugSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let normalizedQuery = trimmedQuery.lowercased()
        return debugSearchEntries
            .filter { entry in
                let haystack = [
                    entry.section,
                    entry.label,
                    entry.value
                ]
                .joined(separator: " ")
                .lowercased()

                return haystack.contains(normalizedQuery)
            }
            .prefix(12)
            .map { DebugSearchMatch(section: $0.section, label: $0.label, value: $0.value) }
    }

    private var debugSearchEntries: [DebugSearchEntry] {
        [
            DebugSearchEntry(section: "Accessibility Permission", label: "Status", value: viewModel.permissionState.statusTitle),
            DebugSearchEntry(section: "Accessibility Permission", label: "Summary", value: viewModel.permissionState.summary),
            DebugSearchEntry(section: "Captured External Target", label: "App localized name", value: viewModel.capturedExternalTargetDebugInfo.localizedName),
            DebugSearchEntry(section: "Captured External Target", label: "Bundle identifier", value: viewModel.capturedExternalTargetDebugInfo.bundleIdentifier),
            DebugSearchEntry(section: "Captured External Target", label: "Lookup status", value: viewModel.capturedExternalTargetDebugInfo.statusMessage),
            DebugSearchEntry(section: "Watch First", label: "Failure stage", value: viewModel.screenUnderstandingFailureStageLabel),
            DebugSearchEntry(section: "Watch First", label: "Likely failure cause", value: viewModel.screenUnderstandingLikelyFailureCause),
            DebugSearchEntry(section: "Watch First", label: "Finish reason", value: viewModel.screenUnderstandingDebugInfo.finishReason ?? "Unavailable"),
            DebugSearchEntry(section: "Watch First", label: "Parser outcome", value: viewModel.screenUnderstandingDebugInfo.parserOutcome.rawValue),
            DebugSearchEntry(section: "Browser-aware capture", label: "Detected browser", value: viewModel.screenUnderstandingDebugInfo.browserName ?? "Unavailable"),
            DebugSearchEntry(section: "Browser-aware capture", label: "Failure category", value: viewModel.screenUnderstandingDebugInfo.browserFailureCategory ?? "None"),
            DebugSearchEntry(section: "Browser-aware capture", label: "Context mode", value: viewModel.screenUnderstandingDebugInfo.browserContextUsageDescription),
            DebugSearchEntry(section: "Browser-aware capture", label: "URL retrieval", value: viewModel.screenUnderstandingDebugInfo.browserURLRetrievalStatus),
            DebugSearchEntry(section: "Browser-aware capture", label: "Current URL", value: viewModel.screenUnderstandingDebugInfo.browserCurrentURL ?? "Unavailable"),
            DebugSearchEntry(section: "Browser-aware capture", label: "Page title retrieval", value: viewModel.screenUnderstandingDebugInfo.browserTitleRetrievalStatus),
            DebugSearchEntry(section: "Browser-aware capture", label: "Page title", value: viewModel.screenUnderstandingDebugInfo.browserPageTitle ?? "Unavailable"),
            DebugSearchEntry(section: "Routing Summary", label: "Page type", value: viewModel.screenScenarioGuidance?.context.likelyPageType ?? "Unavailable"),
            DebugSearchEntry(section: "Routing Summary", label: "Host", value: viewModel.screenScenarioGuidance?.context.browserHostname ?? "Unavailable"),
            DebugSearchEntry(section: "Advanced app and permission debug", label: "Accessibility permission", value: yesNo(viewModel.permissionState.isGranted)),
            DebugSearchEntry(section: "Advanced app and permission debug", label: "Runtime bundle id", value: viewModel.appRuntimeIdentityDebugInfo.bundleIdentifier),
            DebugSearchEntry(section: "Advanced app and permission debug", label: "Runtime app path", value: viewModel.appRuntimeIdentityDebugInfo.bundlePath),
            DebugSearchEntry(section: "Advanced app and permission debug", label: "Runtime executable", value: viewModel.appRuntimeIdentityDebugInfo.executablePath),
            DebugSearchEntry(section: "Advanced app and permission debug", label: "Signing state", value: viewModel.appRuntimeIdentityDebugInfo.signingState),
            DebugSearchEntry(section: "Advanced app and permission debug", label: "Signing detail", value: viewModel.appRuntimeIdentityDebugInfo.signingDetail),
            DebugSearchEntry(section: "Advanced app and permission debug", label: "Current frontmost app", value: viewModel.currentFrontmostAppDebugInfo.localizedName),
            DebugSearchEntry(section: "Advanced app and permission debug", label: "Current frontmost status", value: viewModel.currentFrontmostAppDebugInfo.statusMessage)
        ]
    }

    private func applyDebugSearchExpansion(for query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return
        }

        let advancedKeywords = ["runtime", "signing", "permission", "executable", "bundle", "frontmost"]
        let browserKeywords = ["browser", "url", "host", "domain", "title", "text summary", "chrome", "safari"]
        let responseKeywords = ["parser", "finish", "token", "response", "raw response"]
        let payloadKeywords = ["payload", "complexity", "candidate", "routing", "analysis mode"]

        if advancedKeywords.contains(where: normalized.contains)
            || browserKeywords.contains(where: normalized.contains)
            || responseKeywords.contains(where: normalized.contains)
            || payloadKeywords.contains(where: normalized.contains) {
            analysisDebugPresentationMode = .verbose
        }

        if advancedKeywords.contains(where: normalized.contains) {
            isAdvancedAppDebugExpanded = true
        }

        if browserKeywords.contains(where: normalized.contains) {
            isBrowserDiagnosticsExpanded = true
        }

        if responseKeywords.contains(where: normalized.contains) {
            isResponseDiagnosticsExpanded = true
            isRequestSummaryExpanded = true
        }

        if payloadKeywords.contains(where: normalized.contains) {
            isPayloadDiagnosticsExpanded = true
        }
    }
}

private struct ResultSummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct IntentOptionCard: View {
    let option: OwlGuideIntentOption
    let isSelected: Bool
    let isConfirmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(option.title)
                    .font(.body.weight(.semibold))

                Spacer()

                if option.isPrimary {
                    Text("Likely")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if isConfirmed {
                    Text("Confirmed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if isSelected {
                    Text("Tentative")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Text(option.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .underPageBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isConfirmed ? Color.green : (isSelected ? Color.accentColor : Color.primary.opacity(0.08)), lineWidth: isSelected || isConfirmed ? 1.5 : 1)
        )
    }
}

private struct DiagnosticTextArea: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120, maxHeight: 220)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }
}

private struct ScreenUnderstandingReadinessRow: View {
    let item: ScreenUnderstandingReadinessItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.title)
                    .font(.body.weight(.medium))

                Spacer()

                Text(item.isReady ? "Ready" : "Missing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.isReady ? .green : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill((item.isReady ? Color.green : Color.orange).opacity(0.12))
                    )
            }

            Text(item.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}

private struct OverlayGuidanceRow: View {
    let item: OverlayPreviewItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(item.rank)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.88))
                )

            Text(item.caption)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
        )
    }
}

private struct DebugFieldRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

private struct ScanMetricView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body.weight(.medium))
        }
    }
}

private struct RankedElementCard: View {
    let rankedElement: AXRankedElement
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(rankedElement.element.depthSummary)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(rankedElement.element.displayName)
                        .font(.body.weight(.medium))

                    Text("\(rankedElement.element.role) | \(rankedElement.element.subrole)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(rankedElement.element.geometrySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(rankedElement.score)")
                    .font(.headline.monospacedDigit())
            }

            FlowTagRow(tags: rankedElement.reasonTags)

            Text(rankedElement.element.flagsSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private var cardBackgroundColor: Color {
        isSelected
            ? Color.accentColor.opacity(0.12)
            : Color(nsColor: .windowBackgroundColor)
    }
}

private struct ScanElementCard: View {
    let element: AXElementNode
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(element.depthSummary)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(element.displayName)
                        .font(.body.weight(.medium))

                    Text("\(element.role) | \(element.subrole)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(element.geometrySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(element.flagsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if element.title != "Unavailable" {
                DebugFieldRow(label: "Title", value: element.title)
            }

            if element.label != "Unavailable" {
                DebugFieldRow(label: "Label", value: element.label)
            }

            if element.value != "Unavailable" {
                DebugFieldRow(label: "Value", value: element.value)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private var cardBackgroundColor: Color {
        isSelected
            ? Color.accentColor.opacity(0.12)
            : Color(nsColor: .windowBackgroundColor)
    }
}

private struct WatchMetricCard: View {
    let label: String
    let value: String
    var emphasis: WatchMetricEmphasis = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        switch emphasis {
        case .neutral:
            return Color(nsColor: .windowBackgroundColor)
        case .warning:
            return Color.orange.opacity(0.08)
        case .danger:
            return Color.red.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch emphasis {
        case .neutral:
            return Color.primary.opacity(0.08)
        case .warning:
            return Color.orange.opacity(0.32)
        case .danger:
            return Color.red.opacity(0.36)
        }
    }

    private var valueColor: Color {
        switch emphasis {
        case .neutral:
            return .primary
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

private enum WatchMetricEmphasis {
    case neutral
    case warning
    case danger
}

private struct DebugSearchEntry {
    let section: String
    let label: String
    let value: String
}

private struct DebugSearchMatch: Identifiable {
    let id = UUID()
    let section: String
    let label: String
    let value: String
}

private struct FlowTagRow: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
        }
    }
}
