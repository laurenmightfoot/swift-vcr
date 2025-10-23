import Foundation

/// A cassette contains recorded HTTP interactions
public final class Cassette: Codable, Sendable {
  public let name: String
  private let _interactions: Box<[HTTPInteraction]>
  public let recordMode: RecordMode
  public let matcher: RequestMatcherType

  private init(
    name: String,
    interactions: [HTTPInteraction],
    recordMode: RecordMode,
    matcher: RequestMatcherType
  ) {
    self.name = name
    self._interactions = Box(interactions)
    self.recordMode = recordMode
    self.matcher = matcher
  }

  public convenience init(
    name: String,
    recordMode: RecordMode = .once,
    matcher: RequestMatcherType = .methodAndURI
  ) {
    self.init(
      name: name,
      interactions: [],
      recordMode: recordMode,
      matcher: matcher
    )
  }

  public var interactions: [HTTPInteraction] {
    _interactions.value
  }

  /// Find a matching interaction for the given request
  func findInteraction(for request: URLRequest) -> HTTPInteraction? {
    let matcher = self.matcher.createMatcher()
    return _interactions.value.first { interaction in
      matcher.matches(request, recorded: interaction.request)
    }
  }

  /// Record a new interaction
  func recordInteraction(_ interaction: HTTPInteraction) {
    _interactions.value.append(interaction)
  }

  /// Check if recording is allowed based on record mode
  func shouldRecord(hasMatch: Bool) -> Bool {
    switch recordMode {
    case .none:
      return false
    case .once:
      // Only record if cassette is completely empty (first run)
      return interactions.isEmpty
    case .newEpisodes:
      // Record if this specific request has no match
      return !hasMatch
    case .all:
      return true
    }
  }

  // MARK: - Codable

  private enum CodingKeys: String, CodingKey {
    case name
    case interactions
    case recordMode
    case matcher
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(_interactions.value, forKey: .interactions)
    try container.encode(recordMode, forKey: .recordMode)
    try container.encode(matcher, forKey: .matcher)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.name = try container.decode(String.self, forKey: .name)
    let interactions = try container.decode([HTTPInteraction].self, forKey: .interactions)
    self._interactions = Box(interactions)
    self.recordMode = try container.decode(RecordMode.self, forKey: .recordMode)
    self.matcher = try container.decode(RequestMatcherType.self, forKey: .matcher)
  }
}

/// Request matcher types that can be serialized
public enum RequestMatcherType: String, Codable, Sendable {
  case methodAndURI = "method_uri"
  case methodURIAndBody = "method_uri_body"

  func createMatcher() -> RequestMatcher {
    switch self {
    case .methodAndURI:
      return MethodAndURIMatcher()
    case .methodURIAndBody:
      return MethodURIAndBodyMatcher()
    }
  }
}

/// Thread-safe box for mutable state
final class Box<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: T

  init(_ value: T) {
    self._value = value
  }

  var value: T {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _value
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      _value = newValue
    }
  }

  func modify(_ transform: (inout T) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    transform(&_value)
  }
}
