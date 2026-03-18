import AppKit
import SwiftUI

final class InspectorWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: AppViewModel

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Owl Guide"
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: ControlPanelView(viewModel: viewModel))

        super.init(window: window)

        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.closeInspector()
    }
}
