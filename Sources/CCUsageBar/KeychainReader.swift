import Foundation
import Security

// MARK: - Types

struct ClaudeCredentials {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?
    let rateLimitTier: String?
}

enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case accessError(OSStatus)   // includes denied, interaction not allowed, etc.
    case unexpectedData
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Claude Code credentials not found in Keychain"
        case .accessError(let s):
            return "Keychain access failed (OSStatus \(s)) — look for a security dialog and click Always Allow"
        case .unexpectedData:
            return "Keychain returned unexpected data format"
        case .parseError(let msg):
            return "Failed to parse credentials: \(msg)"
        }
    }
}

// MARK: - Reader

enum KeychainReader {
    static let service = "Claude Code-credentials"

    static func readCredentials() throws -> ClaudeCredentials {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.accessError(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return try parse(data)
    }

    /// Parse the raw JSON blob Claude Code stores in the Keychain.
    /// Extracted from `readCredentials()` so it can be unit-tested without
    /// touching the system Keychain.
    static func parse(_ data: Data) throws -> ClaudeCredentials {
        guard
            let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth  = json["claudeAiOauth"] as? [String: Any],
            let token  = oauth["accessToken"]  as? String
        else {
            throw KeychainError.parseError("Missing claudeAiOauth.accessToken")
        }

        let expiresAt: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let ms = oauth["expiresAt"] as? Int {
            expiresAt = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        } else {
            expiresAt = nil
        }

        return ClaudeCredentials(
            accessToken:      token,
            expiresAt:        expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier:    oauth["rateLimitTier"]    as? String
        )
    }
}
