import Foundation
import VCR

// MARK: - Basic Example

/// This example demonstrates basic VCR usage for testing an API client
@main
struct BasicUsageExample {
  static func main() async throws {
    // 1. Configure VCR with a directory for cassettes
    VCR.configure(cassetteLibraryDirectory: "cassettes")

    // 2. Use a cassette to record/replay interactions
    try await VCR.shared.useCassette("github_api") {
      // Create a VCR-enabled URLSession
      let session = VCR.urlSession()

      // Make your HTTP request
      let url = URL(string: "https://api.github.com/users/octocat")!
      let (data, response) = try await session.data(from: url)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }

      print("Status Code: \(httpResponse.statusCode)")

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let login = json["login"] as? String,
        let name = json["name"] as? String
      {
        print("User: \(login) (\(name))")
      }
    }

    print("\n✅ First run: HTTP request was recorded to cassettes/github_api.json")
    print("Run this again and it will replay the recorded response!")
  }
}

// MARK: - API Client Example

/// Example API client that uses VCR for testing
class GitHubAPIClient {
  private let session: URLSession
  private let baseURL = "https://api.github.com"

  init(session: URLSession = .shared) {
    self.session = session
  }

  func fetchUser(username: String) async throws -> GitHubUser {
    let url = URL(string: "\(baseURL)/users/\(username)")!
    let (data, response) = try await session.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200
    else {
      throw APIError.invalidResponse
    }

    return try JSONDecoder().decode(GitHubUser.self, from: data)
  }
}

struct GitHubUser: Codable {
  let login: String
  let name: String?
  let publicRepos: Int

  enum CodingKeys: String, CodingKey {
    case login, name
    case publicRepos = "public_repos"
  }
}

enum APIError: Error {
  case invalidResponse
}

// MARK: - Testing Example

#if canImport(Testing)
  import Testing

  @Suite("GitHub API Tests")
  struct GitHubAPITests {
    @Test("Fetch user")
    func testFetchUser() async throws {
      // Configure VCR for tests
      VCR.configure(cassetteLibraryDirectory: "Tests/Fixtures/Cassettes")

      // Create API client with VCR-enabled session
      let client = GitHubAPIClient(session: VCR.urlSession())

      // Use cassette to record/replay
      let user = try await VCR.shared.useCassette("github_octocat") {
        try await client.fetchUser(username: "octocat")
      }

      // Assertions
      #expect(user.login == "octocat")
      #expect(user.name == "The Octocat")
    }

    @Test("Fetch user - new episodes mode")
    func testFetchUserNewEpisodes() async throws {
      VCR.configure(cassetteLibraryDirectory: "Tests/Fixtures/Cassettes")

      let client = GitHubAPIClient(session: VCR.urlSession())

      // This will record new interactions but replay existing ones
      let user = try await VCR.shared.useCassette(
        "github_multiple_users",
        recordMode: .newEpisodes
      ) {
        try await client.fetchUser(username: "octocat")
      }

      #expect(user.login == "octocat")
    }
  }
#endif

// MARK: - Advanced Example: Custom Matchers

/// Example showing POST request with body matching
func postExample() async throws {
  VCR.configure(cassetteLibraryDirectory: "cassettes")

  try await VCR.shared.useCassette("create_user", matcher: .methodURIAndBody) {
    let session = VCR.urlSession()

    var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let userData = ["name": "Alice", "email": "alice@example.com"]
    request.httpBody = try JSONSerialization.data(withJSONObject: userData)

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    print("Created user, status: \(httpResponse.statusCode)")
  }
}

// MARK: - Manual Cassette Management

func manualCassetteExample() async throws {
  VCR.configure(cassetteLibraryDirectory: "cassettes")

  // Insert cassette manually
  try VCR.shared.insertCassette("manual_test", recordMode: .once)

  let session = VCR.urlSession()

  // Make multiple requests with same cassette
  for i in 1...3 {
    let url = URL(string: "https://httpbin.org/get?page=\(i)")!
    let (_, response) = try await session.data(from: url)
    print("Request \(i) - Status: \((response as! HTTPURLResponse).statusCode)")
  }

  // Eject and save cassette
  try VCR.shared.ejectCassette()

  print("Cassette saved with 3 interactions!")
}
