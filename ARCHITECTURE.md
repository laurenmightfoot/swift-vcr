# Swift VCR Architecture

This document describes the architecture and design decisions of Swift VCR.

## Overview

Swift VCR is a port of the Ruby VCR library, adapted for Swift's URLSession and modern concurrency features. It enables recording and replaying HTTP interactions for deterministic testing.

## Core Components

### 1. VCR (Main API)
**Location**: `Sources/VCR/VCR.swift`

The main singleton class that manages configuration, cassettes, and URLProtocol registration.

**Key Responsibilities:**
- Configuration management
- Cassette lifecycle (insert/eject)
- URLProtocol registration
- File I/O for cassettes
- Thread-safe state management

**Design Decisions:**
- Singleton pattern for global state management
- Uses `NSLock` for thread-safety in a `@unchecked Sendable` implementation
- Provides both async/await and synchronous APIs

### 2. Cassette
**Location**: `Sources/VCR/Cassette.swift`

Represents a collection of recorded HTTP interactions.

**Key Features:**
- Stores interactions in a thread-safe `Box<T>` wrapper
- Supports Codable for JSON serialization
- Implements request matching logic
- Determines recording behavior based on mode

**Design Decisions:**
- Uses a custom `Box<T>` class for thread-safe mutable state
- Interactions are stored as an array to preserve order
- Matcher type is serialized for consistency across sessions

### 3. HTTP Interaction Models
**Location**: `Sources/VCR/HTTPInteraction.swift`

Three core models:
- `RecordedRequest`: Simplified URLRequest representation
- `RecordedResponse`: Simplified HTTPURLResponse + data
- `HTTPInteraction`: Combines request and response with timestamp

**Design Decisions:**
- Uses simple value types (Codable structs) for easy serialization
- Binary data (request/response bodies) encoded as base64 in JSON
- Captures only essential information, not full URLRequest/URLResponse objects

### 4. VCRURLProtocol
**Location**: `Sources/VCR/VCRURLProtocol.swift`

Custom URLProtocol subclass that intercepts URLSession requests.

**How It Works:**
1. `canInit(with:)`: Checks if request should be intercepted
2. `startLoading()`: Either replays from cassette or makes real request
3. `performRealRequest()`: Makes real HTTP call with internal session
4. Records interactions when allowed by cassette mode

**Design Decisions:**
- Uses a marker property (`internalSessionKey`) to avoid infinite recursion
- Creates ephemeral URLSession without protocol classes for real requests
- Records on successful completion only

### 5. Request Matchers
**Location**: `Sources/VCR/RequestMatcher.swift`

Protocol-based matching system with built-in matchers:
- `MethodAndURIMatcher`: Matches by HTTP method and URL
- `MethodURIAndBodyMatcher`: Also matches request body
- `MethodURIAndHeadersMatcher`: Matches specific headers
- `CompositeMatcher`: Combines multiple matchers

**Design Decisions:**
- Protocol-based for extensibility
- All matchers are `Sendable` for Swift concurrency
- Common matchers are pre-built for convenience

### 6. Configuration
**Location**: `Sources/VCR/VCRConfiguration.swift`

Immutable configuration object with:
- Cassette library directory
- Default record mode
- Default matcher

**Design Decisions:**
- Sendable struct for thread-safety
- Provides helper for relative paths
- Immutable after creation

### 7. Record Modes
**Location**: `Sources/VCR/RecordMode.swift`

Enum defining when to record:
- `.once`: Record if not exists, otherwise replay
- `.newEpisodes`: Record new, replay existing
- `.all`: Always record (overwrite)
- `.none`: Never record (error if not found)

**Design Decisions:**
- Matches Ruby VCR modes for familiarity
- Codable with snake_case for JSON consistency

## Data Flow

### Recording Flow
```
URLSession request
    ↓
VCRURLProtocol.canInit() - Check if should intercept
    ↓
VCRURLProtocol.startLoading() - Check cassette for match
    ↓
No match + shouldRecord = true
    ↓
performRealRequest() - Make real HTTP call
    ↓
Record interaction to cassette
    ↓
Client receives response
```

### Replay Flow
```
URLSession request
    ↓
VCRURLProtocol.canInit() - Check if should intercept
    ↓
VCRURLProtocol.startLoading() - Check cassette for match
    ↓
Match found
    ↓
replayInteraction() - Return cached response
    ↓
Client receives response
```

### Cassette Lifecycle
```
VCR.configure() - Set up VCR
    ↓
VCR.insertCassette() - Load or create cassette
    ↓
Make requests (record/replay)
    ↓
VCR.ejectCassette() - Save cassette to disk
```

## File Format

Cassettes are stored as JSON:

```json
{
  "name": "cassette_name",
  "record_mode": "once",
  "matcher": "method_uri",
  "interactions": [
    {
      "request": {
        "method": "GET",
        "url": "https://api.example.com",
        "headers": {},
        "body": null
      },
      "response": {
        "statusCode": 200,
        "headers": {},
        "body": "base64encodeddata"
      },
      "recordedAt": "2025-10-23T09:00:00Z"
    }
  ]
}
```

## Thread Safety

### Concurrency Strategy

1. **VCR singleton**: Protected by `NSLock`
2. **Cassette interactions**: Protected by `Box<T>` with internal locking
3. **URLProtocol**: Foundation handles concurrency
4. **All public types**: Marked `Sendable` where appropriate

### Sendable Conformance

- `RecordMode`: Enum (automatic)
- `RecordedRequest/Response`: Struct with Sendable members
- `HTTPInteraction`: Struct with Sendable members
- `VCRConfiguration`: Sendable struct
- `Cassette`: Uses `@unchecked Sendable` with internal locking
- `VCR`: Uses `@unchecked Sendable` with NSLock

## Differences from Ruby VCR

### Intentional Differences

1. **JSON instead of YAML**: Better Swift/Codable support
2. **URLSession only**: Focused scope vs Ruby's multi-library support
3. **Async/await first**: Leverages modern Swift concurrency
4. **Type-safe matchers**: Protocol-based instead of dynamic

### Missing Features (Future)

- Filtering sensitive data
- Custom serializers
- ERB-like templating
- Re-recording on interval
- Hooks/callbacks

## Extension Points

### Custom Matchers

Implement `RequestMatcher` protocol:

```swift
struct CustomMatcher: RequestMatcher {
    func matches(_ request: URLRequest, recorded: RecordedRequest) -> Bool {
        // Custom matching logic
    }
}
```

### Future: Custom Serializers

Could add a `CassetteSerializer` protocol:

```swift
protocol CassetteSerializer {
    func serialize(_ cassette: Cassette) throws -> Data
    func deserialize(_ data: Data) throws -> Cassette
}
```

## Testing Strategy

### Test Suite Organization

- Unit tests for matchers
- Unit tests for record modes
- Unit tests for serialization
- Integration tests for record/replay
- All tests use `.serialized` to avoid singleton conflicts

### Test Isolation

- Each test uses unique temp directory
- Tests clean up cassettes
- Tests reconfigure VCR to avoid state leakage

## Performance Considerations

1. **File I/O**: Cassettes loaded/saved only on insert/eject
2. **Matching**: Linear search through interactions (acceptable for test scenarios)
3. **Memory**: All interactions kept in memory while cassette inserted
4. **Locking**: Minimal lock contention with coarse-grained locks

## Security Notes

- Cassettes may contain sensitive data (headers, bodies)
- Users should .gitignore cassettes or filter sensitive fields (future feature)
- No credential storage by default

## Future Enhancements

1. **Sensitive data filtering**: Redact headers/body fields
2. **Cassette encryption**: Optional encryption for sensitive tests
3. **Multiple matchers**: Support composite matching strategies
4. **Custom serializers**: YAML, Protocol Buffers, etc.
5. **Statistics**: Track hits/misses
6. **Hooks**: Before/after recording callbacks
7. **Re-recording**: Automatic re-record after time period
