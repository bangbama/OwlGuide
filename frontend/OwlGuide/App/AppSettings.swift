import Foundation
import SwiftUI
import IOKit

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

    /// 设备唯一匿名标识，自动生成并持久化存储，无需用户授权
    @AppStorage("device.anonymousIdentifier")
    private(set) var anonymousDeviceIdentifier: String = AppSettings.generateHardwareUUID()
    
    // MARK: - Singleton

    static let shared = AppSettings()
    private init() {}
    
    // MARK: - 设备标识生成
    private static func generateHardwareUUID() -> String {
        // 优先读取UserDefaults中已存储的标识
        if let existingId = UserDefaults.standard.string(forKey: "device.anonymousIdentifier") {
            return existingId
        }
        
        // 使用IOKit获取Mac设备硬件UUID，无需用户授权
        let masterPort: mach_port_t = kIOMainPortDefault
        let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
        let platformExpert = IOServiceGetMatchingService(masterPort, matchingDict)
        
        guard platformExpert != IO_OBJECT_NULL else {
            // fallback: 生成随机UUID并存储
            let fallbackUUID = UUID().uuidString
            UserDefaults.standard.set(fallbackUUID, forKey: "device.anonymousIdentifier")
            return fallbackUUID
        }
        
        guard let uuidData = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ).takeRetainedValue() as? Data else {
            IOObjectRelease(platformExpert)
            let fallbackUUID = UUID().uuidString
            UserDefaults.standard.set(fallbackUUID, forKey: "device.anonymousIdentifier")
            return fallbackUUID
        }
        
        IOObjectRelease(platformExpert)
        
        guard let uuidString = String(data: uuidData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            let fallbackUUID = UUID().uuidString
            UserDefaults.standard.set(fallbackUUID, forKey: "device.anonymousIdentifier")
            return fallbackUUID
        }
        
        // 存储获取到的硬件UUID
        UserDefaults.standard.set(uuidString, forKey: "device.anonymousIdentifier")
        return uuidString
    }
}
