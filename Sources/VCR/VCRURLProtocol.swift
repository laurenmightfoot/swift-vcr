import Foundation

/// URLProtocol subclass that intercepts URLSession requests for VCR recording/playback
final class VCRURLProtocol: URLProtocol {
  private var dataTask: URLSessionDataTask?
  private static let internalSessionKey = "VCRURLProtocol.InternalSession"

  override class func canInit(with request: URLRequest) -> Bool {
    // Don't intercept our own internal requests
    if URLProtocol.property(forKey: internalSessionKey, in: request) != nil {
      return false
    }

    // Only intercept HTTP/HTTPS requests
    guard let scheme = request.url?.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else {
      return false
    }

    return VCR.shared.isEnabled
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    guard let cassette = VCR.shared.currentCassette else {
      // No cassette inserted, pass through
      performRealRequest()
      return
    }

    // Try to find a matching interaction
    if let interaction = cassette.findInteraction(for: request) {
      // Found a match, replay it
      replayInteraction(interaction)
    } else if cassette.shouldRecord(hasMatch: false) {
      // No match and recording is allowed, perform real request and record
      performRealRequest()
    } else {
      // No match and recording not allowed
      let error = VCRError.noMatchingInteraction(
        method: request.httpMethod ?? "GET",
        url: request.url?.absoluteString ?? ""
      )
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {
    dataTask?.cancel()
    dataTask = nil
  }

  private func replayInteraction(_ interaction: HTTPInteraction) {
    // Create response
    guard let url = request.url else { return }

    let httpResponse = HTTPURLResponse(
      url: url,
      statusCode: interaction.response.statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: interaction.response.headers
    )!

    // Deliver response to client
    client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)

    if let body = interaction.response.body {
      client?.urlProtocol(self, didLoad: body)
    }

    client?.urlProtocolDidFinishLoading(self)
  }

  private func performRealRequest() {
    // Create a new request marked as internal to avoid infinite recursion
    let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
    URLProtocol.setProperty(true, forKey: Self.internalSessionKey, in: mutableRequest)
    let internalRequest = mutableRequest as URLRequest

    // Create a session that won't be intercepted
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = []
    let session = URLSession(configuration: config)

    dataTask = session.dataTask(with: internalRequest) { [weak self] data, response, error in
      guard let self else { return }

      if let error = error {
        self.client?.urlProtocol(self, didFailWithError: error)
        return
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        self.client?.urlProtocol(self, didFailWithError: VCRError.invalidResponse)
        return
      }

      let receivedData = data ?? Data()

      // Forward response to client
      self.client?.urlProtocol(
        self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
      if !receivedData.isEmpty {
        self.client?.urlProtocol(self, didLoad: receivedData)
      }
      self.client?.urlProtocolDidFinishLoading(self)

      // Record the interaction if cassette allows it
      if let cassette = VCR.shared.currentCassette,
        cassette.shouldRecord(hasMatch: false)
      {
        let interaction = HTTPInteraction(
          request: RecordedRequest(from: self.request),
          response: RecordedResponse(from: httpResponse, body: receivedData)
        )
        cassette.recordInteraction(interaction)
      }
    }

    dataTask?.resume()
  }
}

/// VCR-specific errors
public enum VCRError: LocalizedError {
  case noMatchingInteraction(method: String, url: String)
  case invalidResponse
  case cassetteNotFound(String)
  case cassetteAlreadyInserted

  public var errorDescription: String? {
    switch self {
    case .noMatchingInteraction(let method, let url):
      return "No matching interaction found for \(method) \(url)"
    case .invalidResponse:
      return "Invalid HTTP response received"
    case .cassetteNotFound(let name):
      return "Cassette not found: \(name)"
    case .cassetteAlreadyInserted:
      return "A cassette is already inserted. Eject it first."
    }
  }
}
