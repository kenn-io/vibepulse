import Foundation
import Security

protocol ServerTokenStoring {
  func read(server: String) throws -> String
  func write(_ token: String, server: String) throws
}

struct KeychainServerTokens: ServerTokenStoring {
  private func query(_ server: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.vibepulse.VibePulse.server-token",
      kSecAttrAccount as String: UsageFetcher.normalizedServerURL(server),
    ]
  }

  func read(server: String) throws -> String {
    guard !UsageFetcher.normalizedServerURL(server).isEmpty else { return "" }
    var request = query(server)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    if status == errSecItemNotFound { return "" }
    guard status == errSecSuccess else { throw TokenError(status: status) }
    guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
      throw TokenError(status: errSecDecode)
    }
    return token
  }

  func write(_ token: String, server: String) throws {
    guard !UsageFetcher.normalizedServerURL(server).isEmpty else { return }
    let request = query(server)
    if token.isEmpty {
      let status = SecItemDelete(request as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw TokenError(status: status)
      }
      return
    }
    let attributes = [kSecValueData as String: Data(token.utf8)]
    var status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(request.merging(attributes) { _, new in new } as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw TokenError(status: status) }
  }

  private struct TokenError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
      "Could not access the login keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))"
    }
  }
}
