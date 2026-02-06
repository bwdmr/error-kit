import Testing
@testable import ErrorKit

// MARK: - Test Fixtures

public struct TestErrorSource: ErrorKitSource {
  public enum Base: String, Codable, Sendable, Hashable {
    case generic
    case configuration
    case request
  }

  public let base: Base
  public init(_ base: Base) { self.base = base }

  public static let generic = Self(.generic)
  public static let configuration = Self(.configuration)
  public static let request = Self(.request)
}

public struct OtherErrorSource: ErrorKitSource {
  public enum Base: String, Codable, Sendable, Hashable {
    case generic
  }

  public let base: Base
  public init(_ base: Base) { self.base = base }

  public static let generic = Self(.generic)
}

public struct TestError: ErrorKitError {
  public static let name = "TestError"
  public typealias Source = TestErrorSource
}

public struct BadSourceError: ErrorKitError {
  public static let name = "BadSourceError"
  public typealias Source = TestErrorSource
}

public struct OtherError: ErrorKitError {
  public static let name = "OtherError"
  public typealias Source = OtherErrorSource
}

/// A single provider configured once for the whole test run.
/// It demonstrates:
/// - scoping by `backing.name`
/// - overriding `type`, `timestamp`, `reason`
/// - overriding `source` with a compatible type
/// - attempting an incompatible `source` assignment (should be ignored/fallback)
struct AppErrorKitProvider: ErrorKitSourceProvider {
  func map(_ backing: inout ErrorKitBackingView) {
    switch backing.name {

    case TestError.name:
      // Normalize type
      if backing.type == "invalidrequest" {
        backing.type = "invalid_request"
      }

      // Remap source attribution (compatible type)
      if let s = backing.source as? TestErrorSource, s.base == .configuration {
        backing.source = TestErrorSource(.request)
      }

      // Override metadata
      backing.timestamp = 123
      backing.reason = "mapped"

    case BadSourceError.name:
      // Intentionally assign an incompatible source type.
      // Wrapper should fall back to original typed `Source`.
      backing.source = "not a source"

    default:
      // Identity mapping for everything else
      break
    }
  }
}

// MARK: - Tests

@Suite("ErrorKit Provider Tests")
@MainActor
struct ErrorKitProviderTests {
  
  /// Configure provider once using a static flag
  @MainActor
  private static let configureOnce: Void = {
    Task { @MainActor in
      await ErrorKitConfiguration.global.configure(AppErrorKitProvider())
    }
  }()
  
  init() async throws {
    // Access the static property to ensure configuration runs once
    _ = Self.configureOnce
    // Give configuration time to complete
    try await Task.sleep(for: .milliseconds(10))
  }

  @Test("Provider can override all backing members")
  func providerCanOverrideAllBackingMembers() async {
    let original = ErrorKitBacking<TestErrorSource>(
      type: "invalidrequest",
      source: .configuration,
      timestamp: 1,
      reason: "orig"
    )

    let wrapped = await ErrorKitWrapper<TestError>(applyingProviderTo: original)

    #expect(wrapped.type == "invalid_request")
    #expect(wrapped.timestamp == 123)
    #expect(wrapped.reason == "mapped")
    #expect(wrapped.source.base == .request)
  }

  @Test("Provider is scoped by name and can be identity for other errors")
  func providerIsScopedByName() async {
    let original = ErrorKitBacking<OtherErrorSource>(
      type: "raw",
      source: .generic,
      timestamp: 99,
      reason: "keep"
    )

    let wrapped = await ErrorKitWrapper<OtherError>(applyingProviderTo: original)

    // Provider should do nothing for OtherError
    #expect(wrapped.type == "raw")
    #expect(wrapped.source.base == .generic)
    #expect(wrapped.timestamp == 99)
    #expect(wrapped.reason == "keep")
  }

  @Test("Incompatible source assignment is ignored and original source is kept")
  func incompatibleSourceAssignmentIsIgnored() async {
    let original = ErrorKitBacking<TestErrorSource>(
      type: "raw",
      source: .generic,
      timestamp: nil,
      reason: nil
    )

    let wrapped = await ErrorKitWrapper<BadSourceError>(applyingProviderTo: original)

    // Provider attempted: backing.source = "not a source"
    // Expect fallback to original typed source.
    #expect(wrapped.source.base == .generic)
  }

  @Test("Sync initializer does not apply provider")
  func syncInitializerDoesNotApplyProvider() async {
    // This test ensures the distinction between:
    // - init(backing:) (no provider)
    // - init(applyingProviderTo:) (applies provider)
    let original = ErrorKitBacking<TestErrorSource>(
      type: "invalidrequest",
      source: .configuration,
      timestamp: 1,
      reason: "orig"
    )

    let syncWrapped = ErrorKitWrapper<TestError>(backing: original)

    // Provider not applied:
    #expect(syncWrapped.type == "invalidrequest")
    #expect(syncWrapped.source.base == .configuration)
    #expect(syncWrapped.timestamp == 1)
    #expect(syncWrapped.reason == "orig")

    // Provider applied:
    let asyncWrapped = await ErrorKitWrapper<TestError>(applyingProviderTo: original)
    #expect(asyncWrapped.type == "invalid_request")
    #expect(asyncWrapped.source.base == .request)
    #expect(asyncWrapped.timestamp == 123)
    #expect(asyncWrapped.reason == "mapped")
  }
}
