import Foundation

/// Protocol for matching HTTP requests
public protocol RequestMatcher: Sendable {
  func matches(_ request: URLRequest, recorded: RecordedRequest) -> Bool
}

/// Matches requests by HTTP method and URI
public struct MethodAndURIMatcher: RequestMatcher {
  public init() {}

  public func matches(_ request: URLRequest, recorded: RecordedRequest) -> Bool {
    let method = request.httpMethod ?? "GET"
    let url = request.url?.absoluteString ?? ""
    return method == recorded.method && url == recorded.url
  }
}

/// Matches requests by HTTP method, URI, and body
public struct MethodURIAndBodyMatcher: RequestMatcher {
  public init() {}

  public func matches(_ request: URLRequest, recorded: RecordedRequest) -> Bool {
    let method = request.httpMethod ?? "GET"
    let url = request.url?.absoluteString ?? ""
    let body = request.httpBody

    return method == recorded.method
      && url == recorded.url
      && body == recorded.body
  }
}

/// Matches requests by HTTP method, URI, and headers
public struct MethodURIAndHeadersMatcher: RequestMatcher {
  private let headerKeys: Set<String>

  public init(headerKeys: Set<String>) {
    self.headerKeys = headerKeys
  }

  public init(headerKeys: String...) {
    self.headerKeys = Set(headerKeys)
  }

  public func matches(_ request: URLRequest, recorded: RecordedRequest) -> Bool {
    let method = request.httpMethod ?? "GET"
    let url = request.url?.absoluteString ?? ""

    guard method == recorded.method && url == recorded.url else {
      return false
    }

    let requestHeaders = request.allHTTPHeaderFields ?? [:]

    for key in headerKeys {
      if requestHeaders[key] != recorded.headers[key] {
        return false
      }
    }

    return true
  }
}

/// Composite matcher that requires all sub-matchers to match
public struct CompositeMatcher: RequestMatcher {
  private let matchers: [RequestMatcher]

  public init(_ matchers: [RequestMatcher]) {
    self.matchers = matchers
  }

  public func matches(_ request: URLRequest, recorded: RecordedRequest) -> Bool {
    matchers.allSatisfy { $0.matches(request, recorded: recorded) }
  }
}
