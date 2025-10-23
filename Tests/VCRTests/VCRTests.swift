import Foundation
import Testing

@testable import VCR

@Suite("VCR Tests", .serialized)
struct VCRTests {

  @Test("Record and replay HTTP interaction")
  func testRecordAndReplay() async throws {
    // Ensure clean state
    try? VCR.shared.ejectCassette()

    // Configure VCR
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("vcr_tests")
      .appendingPathComponent(UUID().uuidString)

    let config = VCRConfiguration(
      cassetteLibraryDirectory: tempDir,
      defaultRecordMode: .once
    )
    VCR.shared.configure(config)

    // Clean up any existing cassette
    try? FileManager.default.removeItem(at: tempDir)

    let cassetteName = "test_http_request"

    // Create a VCR-enabled URLSession
    let session = VCR.urlSession()

    // First run: Record the interaction
    let firstResponse = try await VCR.shared.useCassette(cassetteName, recordMode: .all) {
      let url = URL(string: "https://httpbin.org/get")!
      let (data, response) = try await session.data(from: url)

      #expect(response is HTTPURLResponse)
      let statusCode = (response as! HTTPURLResponse).statusCode
      // httpbin.org can return 502 when overloaded, accept both for this test
      #expect(statusCode == 200 || statusCode == 502)
      #expect(data.count > 0)

      return String(data: data, encoding: .utf8)
    }

    #expect(firstResponse != nil)

    // Verify cassette was saved
    let cassetteURL = tempDir.appendingPathComponent("\(cassetteName).json")
    #expect(FileManager.default.fileExists(atPath: cassetteURL.path))

    // Second run: Replay the interaction (should get exact same response, even if it was an error)
    let secondResponse = try await VCR.shared.useCassette(cassetteName, recordMode: .once) {
      let url = URL(string: "https://httpbin.org/get")!
      let (data, response) = try await session.data(from: url)

      #expect(response is HTTPURLResponse)
      return String(data: data, encoding: .utf8)
    }

    // Both responses should be identical (this is the key feature of VCR!)
    #expect(firstResponse == secondResponse)

    // Clean up
    try? FileManager.default.removeItem(at: tempDir)
  }

  @Test("Request matching by method and URI")
  func testRequestMatching() async throws {
    let matcher = MethodAndURIMatcher()

    let request1 = URLRequest(url: URL(string: "https://example.com/api")!)
    let recorded1 = RecordedRequest(
      method: "GET",
      url: "https://example.com/api",
      headers: [:],
      body: nil
    )

    #expect(matcher.matches(request1, recorded: recorded1))

    // Different URL should not match
    let request2 = URLRequest(url: URL(string: "https://example.com/other")!)
    #expect(!matcher.matches(request2, recorded: recorded1))

    // Different method should not match
    var request3 = URLRequest(url: URL(string: "https://example.com/api")!)
    request3.httpMethod = "POST"
    #expect(!matcher.matches(request3, recorded: recorded1))
  }

  @Test("Cassette serialization")
  func testCassetteSerialization() throws {
    let interaction = HTTPInteraction(
      request: RecordedRequest(
        method: "GET",
        url: "https://example.com",
        headers: ["User-Agent": "Swift VCR"],
        body: nil
      ),
      response: RecordedResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: Data("{}".utf8)
      )
    )

    let cassette = Cassette(name: "test", recordMode: .once)
    cassette.recordInteraction(interaction)

    // Encode
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(cassette)

    #expect(data.count > 0)

    // Decode
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decodedCassette = try decoder.decode(Cassette.self, from: data)

    #expect(decodedCassette.name == "test")
    #expect(decodedCassette.interactions.count == 1)
    #expect(decodedCassette.interactions[0].request.url == "https://example.com")
  }

  @Test("Record mode behavior")
  func testRecordModeBehavior() {
    let cassetteOnce = Cassette(name: "test", recordMode: .once)

    // Empty cassette: should record
    #expect(cassetteOnce.shouldRecord(hasMatch: false) == true)
    #expect(cassetteOnce.shouldRecord(hasMatch: true) == true)

    // Add an interaction
    cassetteOnce.recordInteraction(
      HTTPInteraction(
        request: RecordedRequest(method: "GET", url: "https://example.com", headers: [:], body: nil),
        response: RecordedResponse(statusCode: 200, headers: [:], body: nil)
      ))

    // Non-empty cassette: should never record (even if no match)
    #expect(cassetteOnce.shouldRecord(hasMatch: false) == false)
    #expect(cassetteOnce.shouldRecord(hasMatch: true) == false)

    let cassetteNewEpisodes = Cassette(name: "test", recordMode: .newEpisodes)
    cassetteNewEpisodes.recordInteraction(
      HTTPInteraction(
        request: RecordedRequest(method: "GET", url: "https://example.com", headers: [:], body: nil),
        response: RecordedResponse(statusCode: 200, headers: [:], body: nil)
      ))

    // newEpisodes: record if no match, don't record if match
    #expect(cassetteNewEpisodes.shouldRecord(hasMatch: false) == true)
    #expect(cassetteNewEpisodes.shouldRecord(hasMatch: true) == false)

    let cassetteAll = Cassette(name: "test", recordMode: .all)

    // Should always record
    #expect(cassetteAll.shouldRecord(hasMatch: false) == true)
    #expect(cassetteAll.shouldRecord(hasMatch: true) == true)

    let cassetteNone = Cassette(name: "test", recordMode: .none)

    // Should never record
    #expect(cassetteNone.shouldRecord(hasMatch: false) == false)
    #expect(cassetteNone.shouldRecord(hasMatch: true) == false)
  }

  @Test("Once mode rejects new interactions after first recording")
  func testOnceModePreventsNewRecordings() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("vcr_tests_once_mode")
      .appendingPathComponent(UUID().uuidString)

    try? FileManager.default.removeItem(at: tempDir)

    VCR.shared.configure(
      VCRConfiguration(
        cassetteLibraryDirectory: tempDir,
        defaultRecordMode: .once
      ))

    let cassetteName = "test_once_mode"
    let session = VCR.urlSession()

    // First interaction - should record
    try await VCR.shared.useCassette(cassetteName, recordMode: .once) {
      var request = URLRequest(url: URL(string: "https://httpbin.org/get?test=1")!)
      request.httpMethod = "GET"
      let (_, _) = try await session.data(for: request)
    }

    // Verify cassette was saved with 1 interaction
    try VCR.shared.insertCassette(cassetteName)
    #expect(VCR.shared.currentCassette?.interactions.count == 1)
    try VCR.shared.ejectCassette()

    // Second interaction with DIFFERENT URL - should fail (not record)
    var didCatchError = false
    do {
      try await VCR.shared.useCassette(cassetteName, recordMode: .once) {
        var request = URLRequest(url: URL(string: "https://httpbin.org/get?test=2")!)
        request.httpMethod = "GET"
        let (_, _) = try await session.data(for: request)
      }
    } catch {
      // Should throw an error (VCRError wrapped by URLSession)
      didCatchError = true
      let errorDescription = error.localizedDescription
      // Verify it's a VCRError about no matching interaction
      #expect(
        errorDescription.contains("No matching interaction")
          || (error as NSError).domain == "VCR.VCRError")
    }
    #expect(didCatchError, "Expected error to be thrown for non-matching URL")

    // Verify cassette still has only 1 interaction (didn't record the second)
    try VCR.shared.insertCassette(cassetteName)
    #expect(VCR.shared.currentCassette?.interactions.count == 1)
    try VCR.shared.ejectCassette()

    // Clean up
    try? FileManager.default.removeItem(at: tempDir)
  }

  @Test("Cassette file persistence")
  func testCassettePersistence() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("vcr_tests_persistence")
      .appendingPathComponent(UUID().uuidString)

    // Ensure clean state
    try? FileManager.default.removeItem(at: tempDir)

    VCR.shared.configure(
      VCRConfiguration(
        cassetteLibraryDirectory: tempDir,
        defaultRecordMode: .all
      ))

    let cassetteName = "test_persistence"

    // Record an interaction
    try VCR.shared.insertCassette(cassetteName, recordMode: .all)

    if let cassette = VCR.shared.currentCassette {
      let interaction = HTTPInteraction(
        request: RecordedRequest(
          method: "GET",
          url: "https://example.com/api",
          headers: [:],
          body: nil
        ),
        response: RecordedResponse(
          statusCode: 200,
          headers: ["Content-Type": "application/json"],
          body: Data("{\"status\":\"ok\"}".utf8)
        )
      )
      cassette.recordInteraction(interaction)
    }

    try VCR.shared.ejectCassette()

    // Verify file exists
    let cassetteURL = tempDir.appendingPathComponent("\(cassetteName).json")
    #expect(FileManager.default.fileExists(atPath: cassetteURL.path))

    // Load the cassette again
    try VCR.shared.insertCassette(cassetteName)
    let loadedCassette = VCR.shared.currentCassette
    #expect(loadedCassette != nil)
    #expect(loadedCassette?.interactions.count == 1)
    #expect(loadedCassette?.interactions.first?.request.url == "https://example.com/api")

    try VCR.shared.ejectCassette()

    // Clean up
    try? FileManager.default.removeItem(at: tempDir)
  }
}
