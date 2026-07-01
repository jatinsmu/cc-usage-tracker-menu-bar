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

    /// Right after a long sleep, securityd hasn't finished re-establishing its
    /// unlock session with the WindowServer — a background-only app (this one
    /// has no Dock icon) gets errSecInteractionNotAllowed instead of the usual
    /// prompt in that narrow window. The condition is transient, so a couple of
    /// short retries clear it without any user action.
    static let maxInteractionRetries = 2
    static let interactionRetryDelayNanoseconds: UInt64 = 1_000_000_000  // 1s, doubles each retry

    /// Whether a failed attempt is worth retrying. Extracted so it's testable
    /// without touching the system Keychain.
    static func shouldRetry(status: OSStatus, attempt: Int, maxAttempts: Int = maxInteractionRetries) -> Bool {
        status == errSecInteractionNotAllowed && attempt < maxAttempts
    }

    /// Delay before the given retry attempt (0-indexed), in nanoseconds.
    static func retryDelay(forAttempt attempt: Int) -> UInt64 {
        interactionRetryDelayNanoseconds << attempt
    }

    static func readCredentials() async throws -> ClaudeCredentials {
        var attempt = 0
        while true {
            let (status, result) = copyMatching()

            switch status {
            case errSecSuccess:
                guard let data = result as? Data else {
                    throw KeychainError.unexpectedData
                }
                return try parse(data)

            case errSecItemNotFound:
                throw KeychainError.itemNotFound

            default:
                guard shouldRetry(status: status, attempt: attempt) else {
                    throw KeychainError.accessError(status)
                }
                try? await Task.sleep(nanoseconds: retryDelay(forAttempt: attempt))
                attempt += 1
            }
        }
    }

    private static func copyMatching() -> (OSStatus, AnyObject?) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
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
        if let raw = oauth["expiresAt"] as? Double {
            expiresAt = date(fromEpoch: raw)
        } else if let raw = oauth["expiresAt"] as? Int {
            expiresAt = date(fromEpoch: Double(raw))
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

    /// Interpret a JSON `expiresAt` epoch whose unit isn't guaranteed.
    /// Claude Code has historically stored milliseconds, but a value in
    /// seconds divided by 1000 lands in 1970 — making a *fresh* token read as
    /// already expired and surfacing a false "Session expired". Disambiguate by
    /// magnitude: a value at or above 1e12 is milliseconds (1e12 ms = year 2001;
    /// 1e12 s = year 33658), anything smaller is seconds.
    static func date(fromEpoch raw: Double) -> Date {
        let seconds = raw >= 1_000_000_000_000 ? raw / 1000.0 : raw
        return Date(timeIntervalSince1970: seconds)
    }
}
