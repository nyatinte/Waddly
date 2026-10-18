let url = URL(fileURLWithPath: "/tmp/waddly-check")
// Double parentheses are the case under test, so keep them past SwiftFormat's redundantParens rule.
// swiftformat:disable:next redundantParens
try? ((FileManager.default.removeItem))(at: url)
