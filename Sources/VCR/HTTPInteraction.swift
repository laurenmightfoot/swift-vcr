import Foundation

/// Represents a recorded HTTP request
public struct RecordedRequest: Codable, Sendable {
  public let method: String
  public let url: String
  public let headers: [String: String]
  public let body: Data?

  public init(method: String, url: String, headers: [String: String], body: Data?) {
    self.method = method
    self.url = url
    self.headers = headers
    self.body = body
  }

  init(from urlRequest: URLRequest) {
    self.method = urlRequest.httpMethod ?? "GET"
    self.url = urlRequest.url?.absoluteString ?? ""
    self.headers = urlRequest.allHTTPHeaderFields ?? [:]
    self.body = urlRequest.httpBody
  }
}

/// Represents a recorded HTTP response
public struct RecordedResponse: Codable, Sendable {
  public let statusCode: Int
  public let headers: [String: String]
  public let body: Data?

  public init(statusCode: Int, headers: [String: String], body: Data?) {
    self.statusCode = statusCode
    self.headers = headers
    self.body = body
  }

  init(from httpResponse: HTTPURLResponse, body: Data?) {
    self.statusCode = httpResponse.statusCode
    self.headers = httpResponse.allHeaderFields.reduce(into: [:]) { result, pair in
      if let key = pair.key as? String, let value = pair.value as? String {
        result[key] = value
      }
    }
    self.body = body
  }
}

/// Represents a complete HTTP interaction (request + response)
public struct HTTPInteraction: Codable, Sendable {
  public let request: RecordedRequest
  public let response: RecordedResponse
  public let recordedAt: Date

  public init(request: RecordedRequest, response: RecordedResponse, recordedAt: Date = Date()) {
    self.request = request
    self.response = response
    self.recordedAt = recordedAt
  }
}
