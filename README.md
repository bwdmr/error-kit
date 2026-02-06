# ErrorKit

## Description

ErrorKit is a Swift error handling framework that provides **structured, type-safe error management** with a clear separation between:

- **library-level attribution** (best-effort triage hints), and
- **application-level classification** (policy, normalization, and alignment).

The core idea is that error authors (libraries) should describe *what kind of failure occurred* and *where responsibility likely lies*, while applications retain the final say on how those errors are interpreted, grouped, or normalized.

- `type` → *“What kind of failure is this?”*
- `source` → *“Where should I start looking for the culprit?”*

This allows library authors to attach meaningful, low-cardinality hints without leaking application concerns into library code.

---

## Error Sources

An `ErrorKitSource` represents a **stable attribution namespace** indicating *where an error is assumed to be fixed* (e.g. configuration, authentication, request lifecycle).

Sources are:
- lightweight
- enumerable
- safe for metrics aggregation and routing
- orthogonal to application-level domains

### Defining a Source

```swift
public struct TestErrorSource: ErrorKitSource {
  enum Base: String, Codable, Sendable {
    case generic
  }

  let base: Base

  init(_ base: Base) { self.base = base }

  public static let generic = Self(.generic)
}
```

---

## Defining Errors

Errors bundle:
- a **name** (error family)
- a **type** (failure kind)
- a **source** (attribution hint)
- optional metadata (`timestamp`, `reason`)

```swift
struct TestError: ErrorKitError {
  static let name = "TestError"
  typealias Source = TestErrorSource

  public static func generic(type: String) -> ErrorKitWrapper<Self> {
    let reason = "generic"
    return .init(
      backing: .init(
        type: type,
        source: .generic,
        reason: reason
      )
    )
  }
}
```

At this point, the library has done everything it reasonably can:
it emitted a structured error with a best-effort attribution hint.

---

## Application-Level Mapping (Source Provider)

Applications often need to:
- align multiple libraries to a shared taxonomy
- normalize error types
- remap attribution domains at integration boundaries

ErrorKit supports this via a **Source Provider**, configured once at application startup.

### Source Provider

A provider receives a **mutable, type-erased view** of the error backing and may override:

- `type`
- `source`
- `timestamp`
- `reason`

It also receives the error `name` as a stable discriminator.

```swift
public protocol ErrorKitSourceProvider: Sendable {
  func map(_ backing: inout ErrorKitBackingView)
}
```

The provider:
- is optional
- performs pure mappings only
- makes no severity, logging, or policy decisions

If a provider assigns an incompatible `source` type, the original typed source is retained.

---

### Example Provider

```swift
struct AppErrorKitProvider: ErrorKitSourceProvider {
  func map(_ backing: inout ErrorKitBackingView) {

    // Scope rules to a specific error family
    guard backing.name == "StripeKitError" else { return }

    // Normalize type values
    if backing.type == "invalidrequest" {
      backing.type = "invalid_request"
    }

    // Remap source attribution
    if let s = backing.source as? StripeKitErrorSource,
       s.base == .configuration {
      backing.source = StripeKitErrorSource(.request)
    }

    // Optional: redact reason
    // backing.reason = nil
  }
}
```

---

## Configuration

The provider is configured **once at application startup** and applied automatically during error construction.

```swift
@main
struct MyApp {
  static func main() async {
    await ErrorKitConfiguration.global.configure(AppErrorKitProvider())
    // continue startup
  }
}
```

Because configuration is actor-isolated and write-once:
- no locks are required
- the model is safe under Swift concurrency
- configuration remains application-wide and immutable after setup

---

## Design Summary

- Libraries emit **attribution hints**, not application policy.
- Applications may **reinterpret or normalize** errors centrally.
- Mapping happens **before errors reach the application layer**.
- Error identity remains stable; only representation is adapted.
- No global mutable state, no per-call switches, no string parsing.

---

## Contributing

Contributions are welcome.

Please follow these steps when making changes.

---

## Contribution Steps

1. Create an issue describing the problem or change.
   - Add a UTC timestamp at the top of the issue (`date -u +%s`).

2. Fork the repository.

3. Create a branch for each PR you intend to make.
   - Format: `docs_readme_contribute`
   - Max 3 words, snake case.
   - First word: category.
   - Second: affected section.
   - Third: what is changed.

4. Make your first commit on that branch and include the issue number and timestamp in the commit body:
   - Indicate the category of the commit.
   - Indicate the affected source.
   - Use a descriptive title.

Example:

```yaml
docs(readme): Fix typo

- timestamp: 1768991151
- issue: https://github.com/.../issues/1
```

5. Update `changelog.json` using `generate_changelog.sh`.
   - Commit separately.

6. Open a pull request.

7. Wait for review.
