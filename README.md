# Swift VCR

A Swift port of the popular [VCR](https://github.com/vcr/vcr) Ruby gem. Record your test suite's HTTP interactions and replay them during future test runs for fast, deterministic, accurate tests.

## Features

- **Record & Replay**: Automatically record HTTP interactions and replay them in subsequent test runs
- **URLSession Support**: Works seamlessly with Foundation's URLSession
- **Multiple Record Modes**: Control when and how interactions are recorded
- **Flexible Matching**: Match requests by method, URI, headers, or body
- **JSON Storage**: Human-readable cassette files in JSON format
- **Thread-Safe**: Built with Swift concurrency in mind
- **Swift 6 Ready**: Fully compatible with Swift 6 and modern concurrency

## Installation

Add Swift VCR to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/grdsdev/swift-vcr.git", from: "0.1.0")
]
```

## Quick Start

### 1. Configure VCR

```swift
import VCR

// In your test setup
VCR.configure(cassetteLibraryDirectory: "fixtures/cassettes")
```

### 2. Use a Cassette

```swift
func testAPIRequest() async throws {
    // Create a VCR-enabled URLSession
    let session = VCR.urlSession()

    try await VCR.shared.useCassette("my_api_test") {
        let url = URL(string: "https://api.example.com/data")!
        let (data, response) = try await session.data(from: url)

        // Your assertions here
        #expect(response.statusCode == 200)
    }
}
```

### 3. Run Your Tests

- **First run**: VCR records the HTTP interaction to `fixtures/cassettes/my_api_test.json`
- **Subsequent runs**: VCR replays the recorded interaction - no network calls!

## Usage

### Record Modes

Control when interactions are recorded:

```swift
// Record once, then replay (default)
try await VCR.shared.useCassette("test", recordMode: .once) {
    // Your code
}

// Record new interactions not in cassette
try await VCR.shared.useCassette("test", recordMode: .newEpisodes) {
    // Your code
}

// Always record (overwrite cassette)
try await VCR.shared.useCassette("test", recordMode: .all) {
    // Your code
}

// Never record (error if interaction not found)
try await VCR.shared.useCassette("test", recordMode: .none) {
    // Your code
}
```

### Request Matching

Choose how requests are matched to recorded interactions:

```swift
// Match by HTTP method and URI (default)
try await VCR.shared.useCassette("test", matcher: .methodAndURI) {
    // Your code
}

// Match by method, URI, and request body
try await VCR.shared.useCassette("test", matcher: .methodURIAndBody) {
    // Your code
}
```

### Manual Cassette Management

For more control, manually insert and eject cassettes:

```swift
// Insert a cassette
try VCR.shared.insertCassette("my_cassette", recordMode: .once)

// Create VCR-enabled session and make requests
let session = VCR.urlSession()
let (data, _) = try await session.data(from: url)

// Eject and save
try VCR.shared.ejectCassette()
```

### Advanced Configuration

```swift
let config = VCRConfiguration(
    cassetteLibraryDirectory: URL(fileURLWithPath: "/path/to/cassettes"),
    defaultRecordMode: .newEpisodes,
    defaultMatcher: .methodAndURI
)
VCR.shared.configure(config)
```

## Cassette File Format

Cassettes are stored as JSON files with a clean, readable format:

```json
{
  "name" : "my_api_test",
  "record_mode" : "once",
  "matcher" : "method_uri",
  "interactions" : [
    {
      "request" : {
        "method" : "GET",
        "url" : "https://api.example.com/data",
        "headers" : {
          "Accept" : "application/json"
        }
      },
      "response" : {
        "statusCode" : 200,
        "headers" : {
          "Content-Type" : "application/json"
        },
        "body" : "eyJzdGF0dXMiOiJvayJ9"
      },
      "recordedAt" : "2025-10-23T09:00:00Z"
    }
  ]
}
```

## Important: URLSession Configuration

Swift VCR uses a custom `URLProtocol` to intercept HTTP requests. **You must use a VCR-enabled URLSession**:

```swift
// ✅ Correct - use VCR.urlSession()
let session = VCR.urlSession()

// ❌ Won't work - URLSession.shared doesn't use custom protocols
let session = URLSession.shared
```

## Examples

### Testing an API Client

```swift
import Testing
import VCR

@Suite("API Client Tests")
struct APIClientTests {
    @Test func fetchUser() async throws {
        VCR.configure(cassetteLibraryDirectory: "Tests/Fixtures/Cassettes")

        let client = APIClient(session: VCR.urlSession())

        let user = try await VCR.shared.useCassette("fetch_user") {
            try await client.fetchUser(id: 123)
        }

        #expect(user.name == "John Doe")
    }
}
```

### POST Requests with Body Matching

```swift
@Test func createUser() async throws {
    VCR.configure(cassetteLibraryDirectory: "Tests/Fixtures")

    try await VCR.shared.useCassette("create_user", matcher: .methodURIAndBody) {
        var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(newUser)

        let (data, response) = try await VCR.urlSession().data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 201)
    }
}
```

## Differences from Ruby VCR

Swift VCR focuses on core functionality for Swift/URLSession:

- **URLSession only**: Unlike Ruby VCR which supports multiple HTTP libraries, Swift VCR focuses on URLSession
- **JSON cassettes**: Uses JSON instead of YAML for better Swift compatibility
- **Async/await first**: Built for modern Swift concurrency
- **Type-safe**: Leverages Swift's type system for safer cassette handling

## Requirements

- Swift 6.0+
- iOS 13+, macOS 10.15+, or Linux

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details

## Acknowledgments

Inspired by the excellent [VCR](https://github.com/vcr/vcr) Ruby gem by Myron Marston and the VCR contributors.
