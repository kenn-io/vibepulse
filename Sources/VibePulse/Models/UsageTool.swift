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
