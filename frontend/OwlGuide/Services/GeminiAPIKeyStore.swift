import Foundation
import Security

enum GeminiAPIKeyStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "The Gemini key could not be saved locally. Keychain status: \(status)."
        }
    }
}

struct GeminiAPIKeyStore {
    private let service = Bundle.main.bundleIdentifier ?? "com.owlguide.app"
    private let account = "gemini-api-key"

    func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }

        return key
    }

    func containsKey() -> Bool {
        load() != nil
    }

    func save(_ key: String) throws {
        let data = Data(key.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw GeminiAPIKeyStoreError.unexpectedStatus(updateStatus)
        }

        var insertQuery = baseQuery
        insertQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GeminiAPIKeyStoreError.unexpectedStatus(addStatus)
        }
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GeminiAPIKeyStoreError.unexpectedStatus(status)
        }
    }
}
