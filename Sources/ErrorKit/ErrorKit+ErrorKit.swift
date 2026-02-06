import Foundation

// MARK: - Configuration

/// Global, application-wide ErrorKit configuration.
public extension ErrorKitConfiguration {
  static var global: ErrorKitConfiguration { shared }
}

public actor ErrorKitConfiguration {
  fileprivate static let shared = ErrorKitConfiguration()
  private var provider: (any ErrorKitSourceProvider)?

  /// Configure the Source provider.
  /// Must be called exactly once during application startup.
  public func configure(_ provider: any ErrorKitSourceProvider) {
    precondition(self.provider == nil, "ErrorKitConfiguration.configure must be called only once.")
    self.provider = provider
  }

  public func getProvider() -> (any ErrorKitSourceProvider)? { provider }
}

// MARK: - Provider

/// Source Provider used to remap ErrorKitSource values at the application layer.
///
/// A Source Provider allows the application to **reinterpret or normalize**
/// error sources emitted by a library, without requiring the library to
/// change its internal domain model.
///
/// This is useful when:
/// - multiple libraries need to align to a shared error taxonomy
/// - a library’s internal domains differ from application-level concepts
/// - error ownership should be reassigned at integration boundaries
///
/// The provider is invoked during error construction, before the error
/// is surfaced to the application layer.
///
/// Notes:
/// - The provider is optional; if not configured, sources pass through unchanged.
/// - Providers are intended to be **pure mappings** (no side effects).
/// - No severity, logging, or policy decisions should be made here.
/// - If a provider assigns an incompatible `source` type, the original typed `source` is kept.
///
/// Usage: [Define an application-level Provider]
///
///     struct AppErrorKitProvider: ErrorKitSourceProvider {
///       func map(_ backing: inout ErrorKitBackingView) {
///         // Scope to a specific error family (optional)
///         guard backing.name == "StripeKitError" else { return }
///
///         // Example: normalize library "type" values
///         if backing.type == "invalidrequest" {
///           backing.type = "invalid_request"
///         }
///
///         // Example: remap Stripe source taxonomy
///         if let s = backing.source as? StripeKitErrorSource, s.base == .configuration {
///           backing.source = StripeKitErrorSource(.request)
///         }
///
///         // Example: strip reason (optional policy example)
///         // backing.reason = nil
///       }
///     }
///
public protocol ErrorKitSourceProvider: Sendable {
  /// Allows the application to remap backing members before the error
  /// is surfaced to the application layer.
  ///
  /// Notes:
  /// - `name` is intended as a stable discriminator for mapping rules.
  /// - `source` is type-erased; providers may cast it to concrete `ErrorKitSource` types.
  /// - Assigning an incompatible `source` type is ignored (original typed `source` is kept).
  func map(_ backing: inout ErrorKitBackingView)
}

// MARK: - Source

/// Source to where the Error is assumed to be fixed, ex.: Authentication, Configuration, Validation...
///
/// A Source represents a **stable error namespace** describing *where responsibility lies*
/// to resolve the error, rather than where it occurred technically.
///
/// Sources are intentionally lightweight and enumerable, making them suitable
/// for metrics aggregation, routing, and policy decisions at the application layer.
///
/// Usage: [Define custom resource domains]
///
///     public struct TestErrorSource: ErrorKitSource {
///       enum Base: String, Codable, Sendable {
///         case generic
///       }
///
///       let base: Base
///
///       init(_ base: Base) { self.base = base }
///
///       public static let generic = Self(.generic)
///     }
///
public protocol ErrorKitSource: Codable, Sendable, Hashable, CustomStringConvertible {
  associatedtype CaseType: RawRepresentable, Codable, Sendable, Hashable where CaseType.RawValue == String

  var base: CaseType { get }
  init(_ base: CaseType)
}

extension ErrorKitSource {
  public var description: String { base.rawValue }
}

// MARK: - Backing + View

/// Mutable, type-erased "view" of an ErrorKit backing.
///
/// This type is used exclusively by `ErrorKitSourceProvider` implementations
/// to apply application-level mapping rules.
///
/// `source` is stored as `any Sendable` to allow type-erasure while remaining
/// compatible with Swift concurrency.
public struct ErrorKitBackingView: Sendable {
  public var name: String
  public var type: String
  public var source: any Sendable
  public var timestamp: Int64?
  public var reason: String?

  public init(
    name: String,
    type: String,
    source: any Sendable,
    timestamp: Int64?,
    reason: String?
  ) {
    self.name = name
    self.type = type
    self.source = source
    self.timestamp = timestamp
    self.reason = reason
  }
}

public final class ErrorKitBacking<Source: Codable & Sendable>: Codable, Sendable {
  fileprivate let type: String
  fileprivate let source: Source
  fileprivate let timestamp: Int64?
  fileprivate let reason: String?

  public init(
    type: String,
    source: Source,
    timestamp: Int64? = nil,
    reason: String? = nil
  ) {
    self.type = type
    self.source = source
    self.timestamp = timestamp
    self.reason = reason
  }
}

// MARK: - Error + Wrapper

/// Bundle your domain specific information with the name and add the corresponding functions
/// Type argument addresses the dynamically user defined domain the Error occurs in.
///
/// Usage: [Define custom Error category]
///
///     struct TestError: ErrorKitError {
///       static let name = "TestError"
///       typealias Source = TestErrorSource
///
///       public static func generic(type: String) -> ErrorKitWrapper<Self> {
///         let reason = "generic"
///         return .init(backing: .init(type: type, source: .generic, reason: reason))
///       }
///     }
///
public protocol ErrorKitError: Sendable, Codable, Error {
  static var name: String { get }
  associatedtype Source: Codable & Sendable
}

public struct ErrorKitWrapper<E: ErrorKitError>: ErrorKitError, Sendable, Codable {
  public static var name: String { E.name }
  public typealias Source = E.Source

  public let backing: ErrorKitBacking<Source>

  public var type: String { backing.type }
  public var source: Source { backing.source }
  public var timestamp: Int64? { backing.timestamp }
  public var reason: String? { backing.reason }

  public init(
    type: String,
    source: Source,
    timestamp: Int64? = nil,
    reason: String? = nil
  ) {
    self.backing = ErrorKitBacking(
      type: type,
      source: source,
      timestamp: timestamp,
      reason: reason
    )
  }

  /// Initializes without applying a provider.
  public init(backing: ErrorKitBacking<Source>) {
    self.backing = backing
  }

  /// Initializes and applies the configured provider (if any).
  ///
  /// Because configuration is actor-isolated, this initializer is `async`.
  public init(applyingProviderTo backing: ErrorKitBacking<Source>) async {
    var view = ErrorKitBackingView(
      name: Self.name,
      type: backing.type,
      source: backing.source,
      timestamp: backing.timestamp,
      reason: backing.reason
    )

    if let provider = await ErrorKitConfiguration.global.getProvider() {
      provider.map(&view)
    }

    // If the provider assigned an incompatible source type, keep the original typed source.
    let typedSource = (view.source as? Source) ?? backing.source

    self.backing = ErrorKitBacking(
      type: view.type,
      source: typedSource,
      timestamp: view.timestamp,
      reason: view.reason
    )
  }

  public init(type: String, source: Source) throws {
    self.backing = .init(type: type, source: source)
  }
}

extension ErrorKitWrapper: CustomStringConvertible {
  public var description: String {
    var result = #"{ \"name\": \"\#(ErrorKitWrapper.name)\", \"type\": \"\#(self.type)\", \"source\": \"\#(self.source)\""#

    if let timestamp {
      result.append(", \"timestamp\": \"\(String(reflecting: timestamp))\"")
    }

    if let reason {
      result.append(", \"reason\": \"\(String(reflecting: reason))\"")
    }

    result.append("}")
    return result
  }
}

// MARK: - Application Example (configuration)

/// Example application-level setup:
///
///     @main
///     struct MyApp {
///       static func main() async {
///         await ErrorKitConfiguration.global.configure(AppErrorKitProvider())
///         // continue startup...
///       }
///     }
///
