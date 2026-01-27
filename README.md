# ErrorKit


### Description
A Swift error handling framework that provides structured, type-safe error management with enhanced debugging capabilities.
It allows for developers to predetermine a attribution/triage oriented categorization which should be orthogonal towards the application-layer, domain specific classification of Error types.

- type == “what kind of failure is this?” 
- source == “where should I start looking for the culprit?”

as for the parent of the code it is a most straightforward process to attribute their errors with a best-effort “where should I look first” hint.

```swift
public struct TestErrorSource: Source {
  enum Base: String, Codable, Sendable { case generic }
  let base: Base

  init(_ base: Base) { self.base = base }

  public static let generic = Self(.generic)
}

...

struct TestError: ErrorKitError { 
  static let name = "TestError"
  typealias Source = TestErrorSource

  public static func generic(type: String) -> ErrorKitWrapper<Self> {
    let reason = "generic"
    return .init(backing: .init(type: type, source: .generic, reason: reason))
   }
}
```


### Contributing

Contributions are welcome.

Please follow these steps when making changes.

---

## Contribution steps

1. Create an issue describing the problem or change.
  - Add an UTC Timestamp at the top of the issue. (`date -u +%s`) 

2. Fork the repository.

3. Create a branch for each PR you intend to make.
  - Format: `docs_readme_contribute`, max 3 words in snake case
  - the first word a category. the second the section affected. the third what is to change.

4. Make your first commit on that branch and include the issue number and the issue timestamp as first two elements in the commit body:
  - indicate the category of the commit as in type.
  - indicate affected source of the change.
  - follow the commit with a title that describes what has changed not why.
  - complete example:

```yaml
docs(readme): Fix Typo

- timestamp: 1768991151
- issue: https://github.com/.../issues/1
```

5. Update the `changelog.json` with the script `generate_changelog.sh`.
  - add as a separate commit.

6. Open a pull request.

7. Wait for the pull request to be reviewed.

8. ??

9. Profit

---
