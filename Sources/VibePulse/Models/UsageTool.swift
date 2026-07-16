import SwiftUI

enum UsageTool: String, CaseIterable, Identifiable {
  case claude
  case codex
  case pi
  case omp
  case gemini
  case openCode = "opencode"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .claude:
      return "Claude Code"
    case .codex:
      return "Codex"
    case .pi:
      return "Pi"
    case .omp:
      return "OMP"
    case .gemini:
      return "Gemini"
    case .openCode:
      return "OpenCode"
    }
  }

  var shortName: String {
    switch self {
    case .claude:
      return "CC"
    case .codex:
      return "Codex"
    case .pi:
      return "Pi"
    case .omp:
      return "OMP"
    case .gemini:
      return "Gemini"
    case .openCode:
      return "OpenCode"
    }
  }

  var color: Color {
    switch self {
    case .claude:
      return Color(red: 0.86, green: 0.44, blue: 0.27)
    case .codex:
      return Color(red: 0.19, green: 0.58, blue: 0.78)
    case .pi:
      return Color(red: 0.43, green: 0.68, blue: 0.25)
    case .omp:
      return Color(red: 0.22, green: 0.66, blue: 0.62)
    case .gemini:
      return Color(red: 0.91, green: 0.54, blue: 0.18)
    case .openCode:
      return Color(red: 0.55, green: 0.36, blue: 0.78)
    }
  }

  var dailyCommand: [String] {
    switch self {
    case .claude:
      return ["agentsview", "usage", "daily", "--json", "--agent", "claude"]
    case .codex:
      return ["agentsview", "usage", "daily", "--json", "--agent", "codex"]
    case .pi:
      return ["agentsview", "usage", "daily", "--json", "--agent", "pi"]
    case .omp:
      return ["agentsview", "usage", "daily", "--json", "--agent", "omp"]
    case .gemini:
      return ["agentsview", "usage", "daily", "--json", "--agent", "gemini"]
    case .openCode:
      return ["agentsview", "usage", "daily", "--json", "--agent", "opencode"]
    }
  }
}
