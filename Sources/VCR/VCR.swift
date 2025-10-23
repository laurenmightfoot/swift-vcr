import Foundation

/// Main VCR class for managing HTTP interaction recording and playback
public final class VCR: @unchecked Sendable {
  public static let shared = VCR()

  private let lock = NSLock()
  private var _configuration: VCRConfiguration?
  private var _currentCassette: Cassette?
  private var _isEnabled = false
  private var _isRegistered = false

  private init() {}

  /// Configure VCR with the given configuration
  public func configure(_ configuration: VCRConfiguration) {
    lock.lock()

    // Force eject any current cassette when reconfiguring
    if let cassette = _currentCassette {
      lock.unlock()
      if let config = _configuration {
        try? saveCassette(cassette, to: config.cassetteLibraryDirectory)
      }
      lock.lock()
      _currentCassette = nil
    }

    _configuration = configuration
    registerURLProtocol()

    lock.unlock()
  }

  /// Get current configuration
  public var configuration: VCRConfiguration? {
    lock.lock()
    defer { lock.unlock() }
    return _configuration
  }

  /// Get currently inserted cassette
  var currentCassette: Cassette? {
    lock.lock()
    defer { lock.unlock() }
    return _currentCassette
  }

  /// Check if VCR is enabled
  var isEnabled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _isEnabled
  }

  /// Enable VCR interception
  public func enable() {
    lock.lock()
    defer { lock.unlock() }
    _isEnabled = true
  }

  /// Disable VCR interception
  public func disable() {
    lock.lock()
    defer { lock.unlock() }
    _isEnabled = false
  }

  /// Insert a cassette for recording/playback
  /// - Parameters:
  ///   - name: Name of the cassette (used for file storage)
  ///   - recordMode: Recording mode (defaults to configuration default)
  ///   - matcher: Request matcher (defaults to configuration default)
  /// - Throws: VCRError if cassette already inserted or configuration not set
  public func insertCassette(
    _ name: String,
    recordMode: RecordMode? = nil,
    matcher: RequestMatcherType? = nil
  ) throws {
    lock.lock()
    defer { lock.unlock() }

    guard _currentCassette == nil else {
      throw VCRError.cassetteAlreadyInserted
    }

    guard let config = _configuration else {
      fatalError("VCR not configured. Call VCR.shared.configure() first.")
    }

    // Try to load existing cassette
    let cassette: Cassette
    if let loaded = try? loadCassette(name: name, from: config.cassetteLibraryDirectory) {
      cassette = loaded
    } else {
      // Create new cassette
      cassette = Cassette(
        name: name,
        recordMode: recordMode ?? config.defaultRecordMode,
        matcher: matcher ?? config.defaultMatcher
      )
    }

    _currentCassette = cassette
    _isEnabled = true
  }

  /// Eject the current cassette and save it
  /// - Throws: Error if save fails
  public func ejectCassette() throws {
    lock.lock()
    defer { lock.unlock() }

    guard let cassette = _currentCassette else {
      return
    }

    guard let config = _configuration else {
      fatalError("VCR not configured. Call VCR.shared.configure() first.")
    }

    // Save cassette
    try saveCassette(cassette, to: config.cassetteLibraryDirectory)
    _currentCassette = nil
  }

  /// Use a cassette for a specific operation
  /// - Parameters:
  ///   - name: Name of the cassette
  ///   - recordMode: Recording mode
  ///   - matcher: Request matcher
  ///   - block: Async block to execute with cassette inserted
  public func useCassette<T>(
    _ name: String,
    recordMode: RecordMode? = nil,
    matcher: RequestMatcherType? = nil,
    _ block: () async throws -> T
  ) async throws -> T {
    try insertCassette(name, recordMode: recordMode, matcher: matcher)
    defer {
      try? ejectCassette()
    }
    return try await block()
  }

  /// Use a cassette for a synchronous operation
  /// - Parameters:
  ///   - name: Name of the cassette
  ///   - recordMode: Recording mode
  ///   - matcher: Request matcher
  ///   - block: Synchronous block to execute with cassette inserted
  public func useCassette<T>(
    _ name: String,
    recordMode: RecordMode? = nil,
    matcher: RequestMatcherType? = nil,
    _ block: () throws -> T
  ) throws -> T {
    try insertCassette(name, recordMode: recordMode, matcher: matcher)
    defer {
      try? ejectCassette()
    }
    return try block()
  }

  // MARK: - Private Methods

  private func registerURLProtocol() {
    guard !_isRegistered else { return }
    // Register with the global URLProtocol system
    URLProtocol.registerClass(VCRURLProtocol.self)

    // Also modify the default session configuration
    // Note: This only affects new URLSessions, not URLSession.shared
    URLSessionConfiguration.default.protocolClasses?.insert(VCRURLProtocol.self, at: 0)
    URLSessionConfiguration.ephemeral.protocolClasses?.insert(VCRURLProtocol.self, at: 0)

    _isRegistered = true
  }

  private func loadCassette(name: String, from directory: URL) throws -> Cassette {
    let fileURL = directory.appendingPathComponent("\(name).json")
    let data = try Data(contentsOf: fileURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(Cassette.self, from: data)
  }

  private func saveCassette(_ cassette: Cassette, to directory: URL) throws {
    // Create directory if needed
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let fileURL = directory.appendingPathComponent("\(cassette.name).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let data = try encoder.encode(cassette)
    try data.write(to: fileURL)
  }
}

// MARK: - Convenience API

extension VCR {
  /// Configure VCR with a cassette directory path
  public static func configure(cassetteLibraryDirectory path: String) {
    let config = VCRConfiguration.withRelativeDirectory(path)
    shared.configure(config)
  }

  /// Create a URLSession configured to use VCR
  /// - Parameter configuration: Base URLSessionConfiguration (default: .default)
  /// - Returns: URLSession with VCR protocol registered
  public static func urlSession(
    configuration: URLSessionConfiguration = .default
  ) -> URLSession {
    let config = configuration
    var protocolClasses = config.protocolClasses ?? []
    protocolClasses.insert(VCRURLProtocol.self, at: 0)
    config.protocolClasses = protocolClasses
    return URLSession(configuration: config)
  }
}
