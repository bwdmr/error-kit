import Testing

@testable import ErrorKit


@Suite("ErrorKit Tests")
struct ErrorKitTests {
  
  public struct TestErrorSource: Source {
    public enum Base: String, Codable, Sendable { case generic }
    public let base: Base
      
    public init(_ base: Base) { self.base = base }
    public static let generic = Self(.generic)
      
    public var description: String {
      base.rawValue
    }
  }
    
  struct TestError: ErrorKitError {
    static let name = "TestError"
    typealias Source = TestErrorSource
    
    public static func generic() -> ErrorKitWrapper<Self> {
      let reason = "Email format is invalid"
      return .init(backing: .init(type: "generic", source: .generic, reason: reason))
    }
  }
  
  @Test("Initialize with all parameters")
  func initializationWithAllParameters() {
    let error = TestError.generic()
    
    #expect(error.type == "generic")
    #expect(error.source == .generic)
    #expect(error.reason == "Email format is invalid")
  }
}

