import Foundation
import SwiftUI

/// Persistent user-configurable settings for OwlGuide.
/// All values use @AppStorage so they survive app restarts automatically.
final class AppSettings: ObservableObject {
    @AppStorage("backend.dataSourceMode")
    private var backendDataSourceModeRawValue: String = BackendDataSourceMode.cloudBackend.rawValue

    // MARK: - Autopilot Action

    /// When ON, OwlGuide automatically executes the identified *click* action
/// after Gemini analysis completes — without requiring the user to tap
/// the "Perform Action" button. Default: OFF.
    @AppStorage("autopilot.autoClickEnabled")
    var autoClickEnabled: Bool = false

    /// When ON, OwlGuide automatically types the predicted text into the
    /// identified input field after Gemini analysis. Default: OFF.
    @AppStorage("autopilot.autoTypeEnabled")
    var autoTypeEnabled: Bool = false

    /// Delay in seconds before Autopilot fires after analysis, giving the
    /// user a brief window to cancel. Range: 1.0 – 5.0.  Default: 2.0 s.
    @AppStorage("autopilot.actionDelaySeconds")
    var actionDelaySeconds: Double = 2.0

    var backendDataSourceMode: BackendDataSourceMode {
        get { BackendDataSourceMode(rawValue: backendDataSourceModeRawValue) ?? .localSample }
        set { backendDataSourceModeRawValue = newValue.rawValue }
    }
    
    /// Gemini model to use for local backend mode
    @AppStorage("gemini.model")
    var geminiModel: String = "gemini-3-flash-preview"
    
    /// 是否使用用户自定义的Gemini API Key
    @AppStorage("gemini.useCustomAPIKey")
    var useCustomGeminiAPIKey: Bool = false
    
    /// 用户自定义的Gemini API Key，存储在本地Keychain，这里只存开关状态
    @AppStorage("gemini.customAPIKeySaved")
    var customGeminiAPIKeySaved: Bool = false

    // MARK: - Singleton

    static let shared = AppSettings()
    private init() {}
}
