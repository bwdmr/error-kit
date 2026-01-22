import Foundation

/// Source to where the Error is assumed to be fixed, ex.: Authentication, Configuration, Validation...
///
/// Usage: [Define custom resource domains]
///
///     public struct TestErrorSource: Source {
///       enum Base: String, Codable, Sendable { case generic }
///       let base: Base
///
///       init(_ base: Base) { self.base = base }
///
///       public static let generic = Self(.generic)
///     }
///
public protocol Source: Codable, Sendable, Hashable, CustomStringConvertible {
  associatedtype CaseType: RawRepresentable, Codable, Sendable, Hashable where CaseType.RawValue == String
  
  var base: CaseType { get }
  init(_ base: CaseType)
}

extension Source {
  public var description: String {
    base.rawValue
  }
}

public final class Backing<Source: Codable & Sendable>: Codable, Sendable {
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

/// Bundle your domain specific information with the name and add the corresponding functions
/// Type argument addresses the dynamically user defined domain the Error occurs in. ex.: Request...
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
public protocol ErrorKitError: Sendable, Codable {
  static var name: String { get }
  associatedtype Source: Codable & Sendable
}

public struct ErrorKitWrapper<E: ErrorKitError>: ErrorKitError, Sendable, Codable {
  public static var name: String { E.name }
  public typealias Source = E.Source
  
  public let backing: Backing<Source>
  
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
    self.backing = Backing(
      type: type,
      source: source,
      timestamp: timestamp,
      reason: reason
    )
  }
  
  public init(backing: Backing<Source>) {
    self.backing = backing
  }
  
  public init(type: String, source: Source) throws {
    self.backing = .init(type: type, source: source)
  }
}

extension ErrorKitWrapper: CustomStringConvertible {
  public var description: String {
    var result = #"{ \"name\": \"\#(ErrorKitWrapper.name)\", \"type\": \"\#(self.type)\", \"source\": \"\#(self.source)\""#
    
    if let timestamp {
      result.append(", \"timestamp\": \"\(String(reflecting: timestamp))\"") }
    
    if let reason {
      result.append(", \"reason\": \"\(String(reflecting: reason))\"") }
    
    result.append("}")
    return result
  }
}
