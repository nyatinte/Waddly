import Foundation
import SwiftParser
import SwiftSyntax

struct Diagnostic: Equatable {
    let rule: String
    let file: String
    let line: Int
    let message: String
}

struct Allowlist: Decodable {
    let rules: [String: [String]]
}

final class SafetyVisitor: SyntaxVisitor {
    private let file: String
    private let locations: SourceLocationConverter
    private(set) var diagnostics: [Diagnostic] = []

    init(file: String, tree: SourceFileSyntax) {
        self.file = file
        locations = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
            add("force-cast", node, "Avoid forced casts; use a checked cast with an explicit failure path.")
        }
        return .visitChildren
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
            add("force-try", node, "Avoid try!; handle or propagate the error.")
        }
        return .visitChildren
    }

    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        add("force-unwrap", node, "Avoid forced unwraps; handle the optional explicitly.")
        return .visitChildren
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        if node.attributeName.trimmedDescription == "preconcurrency" {
            add("preconcurrency", node, "Review @preconcurrency escape hatches and document the audited boundary.")
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.inheritanceClause?.trimmedDescription.contains("@unchecked Sendable") == true {
            add("unchecked-sendable", node, "Review @unchecked Sendable and document the synchronization invariant.")
        }
        if node.modifiers.contains(where: { $0.trimmedDescription == "nonisolated(unsafe)" }) {
            add("unsafe-isolation", node, "Avoid nonisolated(unsafe); isolate or synchronize mutable state.")
        }
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.inheritanceClause?.trimmedDescription.contains("@unchecked Sendable") == true {
            add("unchecked-sendable", node, "Review @unchecked Sendable and document the synchronization invariant.")
        }
        if node.modifiers.contains(where: { $0.trimmedDescription == "nonisolated(unsafe)" }) {
            add("unsafe-isolation", node, "Avoid nonisolated(unsafe); isolate or synchronize mutable state.")
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.modifiers.contains(where: { $0.trimmedDescription == "nonisolated(unsafe)" }) {
            add("unsafe-isolation", node, "Avoid nonisolated(unsafe); isolate or synchronize mutable state.")
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let called = node.calledExpression.trimmedDescription
        if called == "unsafeBitCast" || called.hasSuffix(".unsafeBitCast") {
            add("unsafe-cast", node, "Avoid unsafeBitCast.")
        }
        if called == "MainActor.assumeIsolated" {
            add("actor-assumption", node, "Review MainActor.assumeIsolated and document the executor guarantee.")
        }
        let memberName = node.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
        if memberName == "wait", node.arguments.isEmpty {
            add("semaphore-wait", node, "Avoid unbounded wait(); use bounded, cancellable async coordination.")
        }
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        if name == "Unmanaged" || (name.hasPrefix("Unsafe") && name.contains("Pointer")) {
            add("unsafe-pointer", node, "Review pointer ownership and lifetime; document the audited boundary.")
        }
        return .visitChildren
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        let label = node.label.trimmedDescription
        if label.hasPrefix("default") {
            add("switch-default", node, "Avoid switch defaults that mask new cases; enumerate cases or use @unknown default.")
        }
        return .visitChildren
    }

    private func add(_ rule: String, _ node: some SyntaxProtocol, _ message: String) {
        let location = locations.location(for: node.positionAfterSkippingLeadingTrivia)
        diagnostics.append(Diagnostic(rule: rule, file: file, line: location.line, message: message))
    }
}

func printUsage() {
    fputs("Usage: swift-safety-check --check <directory>... | --expect-rule <rule> <file>\n", stderr)
}

func swiftFiles(in path: String) -> [String] {
    let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    guard let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return url.pathExtension == "swift" ? [url.path] : []
    }
    return enumerator.compactMap { item in
        guard let fileURL = item as? URL, fileURL.pathExtension == "swift" else { return nil }
        return fileURL.path
    }.sorted()
}

func scan(_ path: String) throws -> [Diagnostic] {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    let tree = Parser.parse(source: source)
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.path
    let fullPath = URL(fileURLWithPath: path).standardizedFileURL.path
    let relative = fullPath.hasPrefix(cwd + "/") ? String(fullPath.dropFirst(cwd.count + 1)) : path
    let visitor = SafetyVisitor(file: relative, tree: tree)
    visitor.walk(tree)
    return visitor.diagnostics
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let mode = arguments.first else {
    printUsage()
    exit(2)
}

if mode == "--expect-rule" {
    guard arguments.count == 3 else {
        printUsage()
        exit(2)
    }
    do {
        let diagnostics = try scan(arguments[2])
        if diagnostics.contains(where: { $0.rule == arguments[1] }) {
            print("Fixture rejected as expected: \(arguments[1])")
            exit(0)
        }
        fputs("Expected rule \(arguments[1]) was not reported for \(arguments[2]).\n", stderr)
        exit(1)
    } catch {
        fputs("Could not scan fixture: \(error)\n", stderr)
        exit(2)
    }
}

guard mode == "--check", arguments.count >= 2 else {
    printUsage()
    exit(2)
}

do {
    let allowlistData = try Data(contentsOf: URL(fileURLWithPath: "Tools/SwiftSafetyCheck/Allowlist.json"))
    let allowlist = try JSONDecoder().decode(Allowlist.self, from: allowlistData)
    let files = arguments.dropFirst().flatMap(swiftFiles(in:))
    var violations: [Diagnostic] = []
    for file in files {
        try violations.append(contentsOf: scan(file))
    }

    let actionable = violations.filter { diagnostic in
        let key = "\(diagnostic.file):\(diagnostic.line)"
        return !(allowlist.rules[diagnostic.rule]?.contains(key) ?? false)
    }.sorted {
        ($0.file, $0.line, $0.rule) < ($1.file, $1.line, $1.rule)
    }

    for diagnostic in actionable {
        print("\(diagnostic.file):\(diagnostic.line): error: [\(diagnostic.rule)] \(diagnostic.message)")
    }
    if actionable.isEmpty {
        print("Swift safety checks passed (\(files.count) files scanned).")
    } else {
        fputs("Swift safety violations. See the allowlist policy in docs/swift-safety.md.\n", stderr)
        exit(1)
    }
} catch {
    fputs("Swift safety check failed: \(error)\n", stderr)
    exit(2)
}
