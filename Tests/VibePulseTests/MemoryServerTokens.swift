import Foundation

@testable import VibePulse

final class MemoryServerTokens: ServerTokenStoring {
  var tokens: [String: String] = [:]
  var readError: Error?
  var writeError: Error?

  func read(server: String) throws -> String {
    if let readError { throw readError }
    return tokens[server] ?? ""
  }

  func write(_ token: String, server: String) throws {
    if let writeError { throw writeError }
    tokens[server] = token
  }
}
