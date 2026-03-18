import ApplicationServices
import AppKit
import Foundation

struct AccessibilityPermissionState {
    let isGranted: Bool
    let statusTitle: String
    let summary: String
    let guidance: String

    static let granted = AccessibilityPermissionState(
        isGranted: true,
        statusTitle: "Granted",
        summary: "Owl Guide can access macOS Accessibility APIs.",
        guidance: "Accessibility access is enabled. Future scanning steps can use this permission to inspect UI elements from other apps."
    )

    static let notGranted = AccessibilityPermissionState(
        isGranted: false,
        statusTitle: "Not Granted",
        summary: "Owl Guide needs Accessibility permission before it can inspect other apps.",
        guidance: "Open System Settings > Privacy & Security > Accessibility, then enable OwlGuide. If it does not appear yet, trigger the permission request once and check the list again."
    )
}

struct PermissionManager {
    func currentState() -> AccessibilityPermissionState {
        AXIsProcessTrusted() ? .granted : .notGranted
    }

    func isScreenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestAccessibilityPermissionPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func requestScreenRecordingPermissionPrompt() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func openAccessibilitySettings() -> Bool {
        openPrivacySettingsPane(named: "Privacy_Accessibility")
    }

    func openScreenRecordingSettings() -> Bool {
        openPrivacySettingsPane(named: "Privacy_ScreenCapture")
    }

    func openSystemSettings() -> Bool {
        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.SystemSettings") {
            return NSWorkspace.shared.open(settingsURL)
        }

        return NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private func openPrivacySettingsPane(named paneName: String) -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(paneName)") else {
            return false
        }

        if NSWorkspace.shared.open(url) {
            return true
        }

        return openSystemSettings()
    }
}
