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

/// File mutations whose failure a `try?` silently discards. Names are the called
/// member, so `removeItem` matches `FileManager.default.removeItem(at:)` and
/// `write` matches `data.write(to:)`. The check is deliberately syntactic, so a
/// same-named non-file method still fails `mise run safety` until it is renamed
/// or given a reviewed allowlist entry.
let fileMutationNames: Set<String> = [
    "copyItem", "createDirectory", "createFile", "linkItem", "moveItem",
    "remove", "removeItem", "replaceItemAt", "setAttributes", "trashItem", "write"
]

/// Compiler flag fragments that disable a Swift safety guarantee. Only
/// `Package.swift` manifests can carry them today, but the check runs over every
/// scanned source so a manifest is covered once it is in the scan path.
let unsafeCompilerFlagFragments = [
    "-Ounchecked",
    "-enforce-exclusivity=unchecked",
    "-strict-concurrency=minimal",
    "-suppress-warnings"
]

final class SafetyVisitor: SyntaxVisitor {
    private let file: String
    private let locations: SourceLocationConverter
    private(set) var diagnostics: [Diagnostic] = []

    init(file: String, tree: SourceFileSyntax) {
        self.file = file
        locations = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
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
        if node.modifiers.contains(where: { $0.trimmedDescription.contains("nonisolated(unsafe)") }) {
            add("unsafe-isolation", node, "Avoid nonisolated(unsafe); isolate or synchronize mutable state.")
        }
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.inheritanceClause?.trimmedDescription.contains("@unchecked Sendable") == true {
            add("unchecked-sendable", node, "Review @unchecked Sendable and document the synchronization invariant.")
        }
        if node.modifiers.contains(where: { $0.trimmedDescription.contains("nonisolated(unsafe)") }) {
            add("unsafe-isolation", node, "Avoid nonisolated(unsafe); isolate or synchronize mutable state.")
        }
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.inheritanceClause?.trimmedDescription.contains("@unchecked Sendable") == true {
            add("unchecked-sendable", node, "Review @unchecked Sendable and document the synchronization invariant.")
        }
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.inheritanceClause?.trimmedDescription.contains("@unchecked Sendable") == true {
            add("unchecked-sendable", node, "Review @unchecked Sendable and document the synchronization invariant.")
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.modifiers.contains(where: { $0.trimmedDescription.contains("nonisolated(unsafe)") }) {
            add("unsafe-isolation", node, "Avoid nonisolated(unsafe); isolate or synchronize mutable state.")
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let called = node.calledExpression.trimmedDescription
        if ["unsafeBitCast", "unsafeDowncast"].contains(where: { called == $0 || called.hasSuffix(".\($0)") }) {
            add("unsafe-cast", node, "Avoid unsafe casts.")
        }
        if called.contains("Unsafe"), called.contains("Pointer") {
            add("unsafe-pointer", node, "Review pointer ownership and lifetime; document the audited boundary.")
        }
        if called.contains("Unmanaged") {
            add("unsafe-pointer", node, "Review Unmanaged ownership and lifetime; document the audited boundary.")
        }
        if called == "unsafeFlags" || called.hasSuffix(".unsafeFlags") {
            add("unsafe-compiler-flags", node, "Review unsafeFlags; they bypass SwiftPM safety checks.")
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

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        if name == "Unmanaged" || (name.hasPrefix("Unsafe") && name.contains("Pointer")) {
            add("unsafe-pointer", node, "Review pointer ownership and lifetime; document the audited boundary.")
        }
        return .visitChildren
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        let label = node.label.trimmedDescription
        if label.hasPrefix("default") {
            add("switch-default", node, "Avoid catch-all cases; enumerate cases or use @unknown default.")
        }
        return .visitChildren
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        if node.body.statements.isEmpty {
            add("empty-catch", node, "Handle the error; an empty catch discards it silently.")
        }
        return .visitChildren
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.questionOrExclamationMark?.text == "?" else { return .visitChildren }
        if let name = calledMemberName(node.expression), fileMutationNames.contains(name) {
            add("silenced-file-mutation", node, "Handle the failed file mutation; try? discards the error.")
        }
        return .visitChildren
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        let literal = node.trimmedDescription
        if let fragment = unsafeCompilerFlagFragments.first(where: { literal.contains($0) }) {
            add("unsafe-compiler-flags", node, "Review compiler flag \(fragment); it weakens safety.")
        }
        return .visitChildren
    }

    private func calledMemberName(_ expression: ExprSyntax) -> String? {
        if let awaitExpr = expression.as(AwaitExprSyntax.self) {
            return calledMemberName(awaitExpr.expression)
        }
        if let inner = singleElementTuple(expression) {
            return calledMemberName(inner)
        }
        guard let call = expression.as(FunctionCallExprSyntax.self) else { return nil }
        return call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
    }

    private func singleElementTuple(_ expression: ExprSyntax) -> ExprSyntax? {
        guard let tuple = expression.as(TupleExprSyntax.self) else { return nil }
        guard tuple.elements.count == 1, let element = tuple.elements.first else { return nil }
        return element.expression
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
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
        return url.pathExtension == "swift" ? [url.path] : []
    }
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
    guard !tree.hasError else {
        throw NSError(
            domain: "SwiftSafetyCheck",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "SwiftSyntax could not parse \(path)"]
        )
    }
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

    let detectedLocations = Set(violations.map { "\($0.rule):\($0.file):\($0.line)" })
    let staleExceptions = allowlist.rules.flatMap { rule, entries in
        entries.filter { !detectedLocations.contains("\(rule):\($0)") }.map { "\(rule):\($0)" }
    }.sorted()
    guard staleExceptions.isEmpty else {
        fputs("Stale Swift safety allowlist entries:\n\(staleExceptions.joined(separator: "\n"))\n", stderr)
        exit(2)
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
