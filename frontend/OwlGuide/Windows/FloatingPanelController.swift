import AppKit
import SwiftUI

final class FloatingPanelController: NSWindowController, NSWindowDelegate {
    private weak var viewModel: AppViewModel?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = NSHostingView(rootView: FloatingOwlView(viewModel: viewModel))

        super.init(window: panel)
        panel.delegate = self

        positionPanel(panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let origin = NSPoint(
            x: screen.maxX - panel.frame.width - 24,
            y: screen.maxY - panel.frame.height - 24
        )
        panel.setFrameOrigin(origin)
    }

    func windowDidMove(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.viewModel?.noteOwlPromptRepositioned()
        }
    }
}
