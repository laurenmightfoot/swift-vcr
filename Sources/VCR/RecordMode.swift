/// Recording modes for VCR cassettes
public enum RecordMode: String, Codable, Sendable {
  /// Do not record or replay any interactions
  case none

  /// Record new interactions not found in cassette, replay existing ones
  case newEpisodes = "new_episodes"

  /// Record all interactions, overwriting the cassette
  case all

  /// Record once, then only replay (error if interaction not found)
  case once
}
