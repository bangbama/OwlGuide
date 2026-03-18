import AppKit
import SwiftUI
import Speech
import AVFoundation

struct FloatingOwlView: View {
    @ObservedObject var viewModel: AppViewModel
    @FocusState private var isIntentFieldFocused: Bool
    @State private var isBreathing = false
    @State private var isFloating = false
    @State private var isPressed = false
    @State private var isListening = false
    @State private var isSettingsPresented = false
    
    var body: some View {
        OwlClickTarget(
            singleClickAction: viewModel.beginOwlInvocation,
            tripleClickAction: viewModel.openDebugPanelFromDeveloperGesture,
            onMouseDown: { isPressed = true },
            onMouseUp: { isPressed = false }
        ) {
            Image("OwlAvatar")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .shadow(
                    // 【关键修改】将 .primary 强制改为 .black。
                    // 彻底杜绝深色模式下阴影变成“白色发光边框”的视觉 Bug。
                    color: viewModel.screenUnderstandingState.isLoading ? .orange.opacity(isBreathing ? 0.8 : 0.3) : .black.opacity(0.25),
                    radius: viewModel.screenUnderstandingState.isLoading ? (isBreathing ? 15 : 5) : 10, // 稍微加大常规阴影半径，更有悬浮感
                    y: viewModel.screenUnderstandingState.isLoading ? 0 : 5
                )
                .offset(y: viewModel.screenUnderstandingState.isLoading ? (isFloating ? -5 : 0) : 0)
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isPressed)
                .padding(20)
        }
        .buttonStyle(.plain)
        .onChange(of: viewModel.screenUnderstandingState.isLoading) { _, isProcessing in
            if isProcessing {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    isFloating = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    isBreathing = false
                    isFloating = false
                }
            }
        }
        .help("Open Owl Guide")
        .padding(8)
        .popover(
            isPresented: Binding(
                get: { viewModel.isOwlInvocationPromptPresented },
                set: { isPresented in
                    if !isPresented {
                        DispatchQueue.main.async {
                            viewModel.handleOwlInvocationPromptPresentationChange(isPresented: false)
                        }
                    }
                }
            ),
            arrowEdge: .leading
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .sheet(isPresented: $isSettingsPresented) {
                        @ObservedObject var settings = AppSettings.shared
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Settings")
                                .font(.title2.weight(.semibold))
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Gemini API Key")
                                    .font(.headline)
                                
                                SecureField("Enter your Gemini API key", text: $viewModel.geminiAPIKeyDraft)
                                    .textFieldStyle(.roundedBorder)
                                
                                Text("Don't have an API key?")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Link("Get your free Gemini API key", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                
                                HStack(spacing: 12) {
                                    Button("Save Key") {
                                        viewModel.saveGeminiAPIKey()
                                        AppSettings.shared.useCustomGeminiAPIKey = true
                                        isSettingsPresented = false
                                    }
                                    .disabled(!viewModel.canSaveGeminiAPIKey)
                                    
                                    if viewModel.hasSavedGeminiAPIKey {
                                        Button("Clear Saved Key") {
                                            viewModel.clearGeminiAPIKey()
                                            AppSettings.shared.useCustomGeminiAPIKey = false
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                            
                            Toggle(isOn: $settings.useCustomGeminiAPIKey) {
                                Text("Use my own Gemini API Key")
                                    .font(.subheadline.weight(.medium))
                            }
                            .disabled(!viewModel.hasSavedGeminiAPIKey)
                            
                            Text("When enabled, requests are sent directly to Google servers, not passing through our backend. Unlimited usage, 100% private.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            HStack {
                                Spacer()
                                Button("Done") {
                                    isSettingsPresented = false
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.top, 16)
                        }
                        .padding(24)
                        .frame(width: 450)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 4) {
                        Text("Need help with this screen?")
                            .font(.system(size: 24, weight: .bold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        
                        Text("v2.1 (20260317-23:35)")
                            .font(.caption2.weight(.medium).monospaced())
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        viewModel.dismissOwlInvocationPrompt()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Close prompt")
                }
                .padding(.bottom, 16)
                
                Text("I can explain what is on this screen and guide you step by step.")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.green.opacity(0.8))
                    
                    Text("I won’t click or type without your permission.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.green.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 20)

                TextField("Example: help me sign in", text: Binding(
                    get: { viewModel.owlUserRequestText },
                    set: { viewModel.updateOwlUserRequestText($0) }
                ))
                // 1. 调大字体，这是让老人看清的关键
                .font(.system(size: 24, weight: .medium))
                // 2. 必须使用 .plain 样式，否则无法自定义高度
                .textFieldStyle(.plain)
                // 3. 通过 Padding 彻底撑开点击区域
                .padding(.horizontal, 16)
                .frame(height: 60) // 此时 frame 才会真正起作用
                // 4. 手动绘制圆角边框
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                )
                .focused($isIntentFieldFocused)
                .onSubmit {
                    viewModel.submitOwlUserRequest()
                }
                .onChange(of: isIntentFieldFocused) { _, focused in
                    if focused {
                        viewModel.noteOwlIntentFieldFocused()
                    }
                }
                .padding(.bottom, 16)
                
                HStack(spacing: 10) {
                    Button("Sign in") {
                        viewModel.updateOwlUserRequestText("Help me sign in")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .font(.system(size: 14, weight: .medium))
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    
                    Button("Read screen") {
                        viewModel.updateOwlUserRequestText("Read this screen")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .font(.system(size: 14, weight: .medium))
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    
                    Button("Next step") {
                        viewModel.updateOwlUserRequestText("What should I click next?")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .font(.system(size: 14, weight: .medium))
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)

                    Button("Reset password") {
                        viewModel.updateOwlUserRequestText("Help me reset my password")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .font(.system(size: 14, weight: .medium))
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    .lineLimit(1)
                }
                .padding(.bottom, 20)

                HStack(spacing: 12) {
                    Button(action: {
                        if !isListening {
                            SpeechManager.shared.requestPermissions { granted, speechGranted, micGranted in
                                if granted {
                                    isListening = true
                                    viewModel.updateOwlUserRequestText("")
                                    SpeechManager.shared.onRecordingStopped = { [weak viewModel] in
                                        DispatchQueue.main.async {
                                            self.isListening = false
                                            viewModel?.submitOwlUserRequest()
                                        }
                                    }
                                    do {
                                        try SpeechManager.shared.startRecording { transcribedText in
                                            viewModel.updateOwlUserRequestText(transcribedText)
                                        }
                                    } catch {
                                        isListening = false
                                        let alert = NSAlert()
                                        alert.messageText = "Could not start recording"
                                        alert.informativeText = error.localizedDescription
                                        alert.addButton(withTitle: "OK")
                                        alert.runModal()
                                    }
                                } else {
                                    var missingPermissions = [String]()
                                    if !speechGranted { missingPermissions.append("Speech Recognition") }
                                    if !micGranted { missingPermissions.append("Microphone") }
                                    
                                    let alert = NSAlert()
                                    alert.messageText = "\(missingPermissions.joined(separator: " and ")) permission(s) required"
                                    alert.informativeText = "Please enable the relevant permissions in the debug panel, or go to System Settings > Privacy & Security to enable them manually."
                                    alert.addButton(withTitle: "Open Debug Panel")
                                    alert.addButton(withTitle: "Cancel")
                                    
                                    if alert.runModal() == .alertFirstButtonReturn {
                                        viewModel.openDebugPanelFromDeveloperGesture()
                                    }
                                }
                            }
                        } else {
                            isListening = false
                            SpeechManager.shared.stopRecording()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                                .symbolEffect(.pulse, isActive: isListening)
                            Text(isListening ? "Listening..." : "Speak")
                                .font(.system(size: 20, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isListening ? .red : .orange)
                    .accessibilityLabel(isListening ? "Recording, tap to stop" : "Voice Input")
                    .accessibilityHint("Tap to start voice input, tap again to stop; submission is automatic after stopping")
                    .shadow(color: .orange.opacity(0.3), radius: 4, y: 2)
                    .frame(maxWidth: 240)

                    Button(action: {
                        viewModel.requestScreenLookFromPrompt()
                    }) {
                        Text("Help Me Now")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue.opacity(0.8))
                    .shadow(color: .blue.opacity(0.2), radius: 4, y: 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
                
                Text("You can stop anytime.")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(16)
            .frame(width: 480)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.noteOwlPromptTapped()
            }
            .onAppear {
                if viewModel.owlFocusLockActive {
                    isIntentFieldFocused = true
                }
            }
        }
    }
}

private struct OwlClickTarget<Content: View>: NSViewRepresentable {
    let singleClickAction: () -> Void
    let tripleClickAction: () -> Void
    let onMouseDown: () -> Void
    let onMouseUp: () -> Void
    let content: Content

    init(
        singleClickAction: @escaping () -> Void,
        tripleClickAction: @escaping () -> Void,
        onMouseDown: @escaping () -> Void = {},
        onMouseUp: @escaping () -> Void = {},
        @ViewBuilder content: () -> Content
    ) {
        self.singleClickAction = singleClickAction
        self.tripleClickAction = tripleClickAction
        self.onMouseDown = onMouseDown
        self.onMouseUp = onMouseUp
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(singleClickAction: singleClickAction, tripleClickAction: tripleClickAction)
    }

    func makeNSView(context: Context) -> NSView {
        let container = ClickHandlingView()
        container.clickHandler = { [weak coordinator = context.coordinator] clickCount in
            coordinator?.handleClickCount(clickCount)
        }
        container.onMouseDown = { [weak coordinator = context.coordinator] in
            coordinator?.onMouseDown()
        }
        container.onMouseUp = { [weak coordinator = context.coordinator] in
            coordinator?.onMouseUp()
        }
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let clickHandlingView = nsView as? ClickHandlingView {
            clickHandlingView.clickHandler = { [weak coordinator = context.coordinator] clickCount in
                coordinator?.handleClickCount(clickCount)
            }
            clickHandlingView.onMouseDown = { [weak coordinator = context.coordinator] in
                coordinator?.onMouseDown()
            }
            clickHandlingView.onMouseUp = { [weak coordinator = context.coordinator] in
                coordinator?.onMouseUp()
            }
        }
        if let hostingView = nsView.subviews.first as? NSHostingView<Content> {
            hostingView.rootView = content
        }

        context.coordinator.singleClickAction = singleClickAction
        context.coordinator.tripleClickAction = tripleClickAction
        context.coordinator.onMouseDown = onMouseDown
        context.coordinator.onMouseUp = onMouseUp
    }

    final class Coordinator: NSObject {
        var singleClickAction: () -> Void
        var tripleClickAction: () -> Void
        var onMouseDown: () -> Void
        var onMouseUp: () -> Void
        private var accumulatedClickCount = 0
        private var resetWorkItem: DispatchWorkItem?
        private var singleClickWorkItem: DispatchWorkItem?

        init(
            singleClickAction: @escaping () -> Void,
            tripleClickAction: @escaping () -> Void,
            onMouseDown: @escaping () -> Void = {},
            onMouseUp: @escaping () -> Void = {}
        ) {
            self.singleClickAction = singleClickAction
            self.tripleClickAction = tripleClickAction
            self.onMouseDown = onMouseDown
            self.onMouseUp = onMouseUp
        }

        func handleClickCount(_ clickCount: Int) {
            guard clickCount > 0 else {
                return
            }

            singleClickWorkItem?.cancel()
            resetWorkItem?.cancel()

            accumulatedClickCount += 1

            switch accumulatedClickCount {
            case 1:
                let singleClickWorkItem = DispatchWorkItem { [weak self] in
                    guard let self, self.accumulatedClickCount == 1 else {
                        return
                    }

                    self.singleClickAction()
                    self.resetClickSequence()
                }
                self.singleClickWorkItem = singleClickWorkItem
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + NSEvent.doubleClickInterval,
                    execute: singleClickWorkItem
                )
            case 2:
                scheduleSequenceReset()
            case 3:
                tripleClickAction()
                resetClickSequence()
            default:
                resetClickSequence()
            }
        }

        private func scheduleSequenceReset() {
            let resetWorkItem = DispatchWorkItem { [weak self] in
                self?.resetClickSequence()
            }
            self.resetWorkItem = resetWorkItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + NSEvent.doubleClickInterval,
                execute: resetWorkItem
            )
        }

        private func resetClickSequence() {
            accumulatedClickCount = 0
            singleClickWorkItem?.cancel()
            singleClickWorkItem = nil
            resetWorkItem?.cancel()
            resetWorkItem = nil
        }
    }
}

private final class ClickHandlingView: NSView {
    var clickHandler: ((Int) -> Void)?
    var onMouseDown: (() -> Void)?
    var onMouseUp: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        onMouseUp?()
        clickHandler?(event.clickCount)
        super.mouseUp(with: event)
    }
}

private struct OwlInvocationCountdownBar: View {
    let startTime: Date?
    let durationSeconds: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            GeometryReader { geometry in
                let progress = remainingProgress(at: context.date)

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.12))

                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 4)
        }
    }

    private func remainingProgress(at currentDate: Date) -> CGFloat {
        guard let startTime else {
            return 0
        }

        let elapsed = max(currentDate.timeIntervalSince(startTime), 0)
        let remaining = max(Double(durationSeconds) - elapsed, 0)
        return CGFloat(remaining / max(Double(durationSeconds), 1))
    }
}
