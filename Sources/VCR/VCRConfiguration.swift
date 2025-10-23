import Foundation

/// Configuration for VCR
public struct VCRConfiguration: Sendable {
  /// Directory where cassettes are stored
  public var cassetteLibraryDirectory: URL

  /// Default record mode for new cassettes
  public var defaultRecordMode: RecordMode

  /// Default matcher for new cassettes
  public var defaultMatcher: RequestMatcherType

  public init(
    cassetteLibraryDirectory: URL,
    defaultRecordMode: RecordMode = .once,
    defaultMatcher: RequestMatcherType = .methodAndURI
  ) {
    self.cassetteLibraryDirectory = cassetteLibraryDirectory
    self.defaultRecordMode = defaultRecordMode
    self.defaultMatcher = defaultMatcher
  }

  /// Create a configuration with a relative path from the current directory
  public static func withRelativeDirectory(
    _ path: String,
    defaultRecordMode: RecordMode = .once,
    defaultMatcher: RequestMatcherType = .methodAndURI
  ) -> VCRConfiguration {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(path)
    return VCRConfiguration(
      cassetteLibraryDirectory: url,
      defaultRecordMode: defaultRecordMode,
      defaultMatcher: defaultMatcher
    )
  }
}
