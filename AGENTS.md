# Pop Agent Guidelines & Specifications

## Strict Commit Controls (未经授权禁止擅自提交代码)
Do **NOT** execute Git commits (`git commit`) or stage files (`git add`) under any circumstances unless the user has **explicitly commanded/requested** you to commit the changes first (e.g., "先commit一下代码" / "commit the changes").

### Development Requirements:
1. **No Proactive Committing**: AI coding agents must restrict their operations solely to editing code, compiling, and running local tests. Creating commits proactively is strictly forbidden.
2. **User-Controlled Git History**: Always present the completed file modifications in the chat for the user to review. Committing must be performed *only* upon receiving an explicit request from the user. This ensures the developer maintains absolute ownership and control over their Git tree, staging state, and commit messages.

## Strict Release Freeze (未经授权禁止发布新版本)
Do **NOT** publish a new GitHub Release, bump marketing versions in `Info.plist` or `project.yml`, create release-related Git tags (e.g., `v*`), or trigger CI/CD release build pipelines unless the user has **explicitly commanded** you to publish/release a new version ("我让你发才发" / "Only release when explicitly told to do so").

### Development Requirements:
1. **No Implicit Version Bumping**: All development, refactoring, and hotfixes must be written, built, and tested locally. You are forbidden from proactively increasing the application's version or pushing release tags online.
2. **Safe Staging & Verification**: Restrict your operations to local compilation and verification. Always present the candidate fixes for the user to verify first. Wait for the user's explicit release command before bumping versions and pushing tags.

## Pop Settings i18n (客户端双语国际化规范)
All user-facing interfaces, settings panels, application views, descriptions, notifications, tooltips, and console outputs in Pop must fully support **Internationalization (i18n)** in both English (`en`) and Simplified Chinese (`zh-Hans`).

### Development Requirements:
1. **UI Views**: Use standard SwiftUI `Text("...")`, `Toggle("...", isOn: ...)` or AppKit localization methods. SwiftUI automatically treats literal strings as `LocalizedStringKey` and localizes them at runtime using the catalog.
2. **Programmatic Strings**: Wrap plain `String` variables or user-facing logs in `String(localized: "...")` to enable dynamic translation lookup.
3. **Catalogs**: Immediately add any new user-facing strings to the Pop application's strings catalog ([Localizable.xcstrings](file:///Users/arjenzhou/src/github/baomi-app/pop/Sources/Pop/Localizable.xcstrings)) for both `"en"` and `"zh-Hans"` keys, ensuring 100% translation completeness.

## No Hardcoded Paths (禁止硬编码写死路径)
Do **NOT** hardcode absolute file paths anywhere in the codebase. This is especially critical for user-specific directories (e.g., paths starting with `/Users/username/...`).

### Development Requirements:
1. **Dynamic Directory Resolution**: Always resolve directories and files dynamically using native macOS / system APIs:
   - Use `FileManager.default.homeDirectoryForCurrentUser`, `FileManager.default.urls(for:in:)`, or `NSHomeDirectory()` to locate standard user folders (e.g., Desktop, Documents, Application Support) dynamically.
2. **Environment & User Isolation**: All caching, databases, temporary file saving, or scratchpad outputs must strictly rely on dynamic user paths or sandbox-provided temporary folders. The codebase must remain completely portable, secure, and executable across different user accounts and machine environments without manual configuration.
