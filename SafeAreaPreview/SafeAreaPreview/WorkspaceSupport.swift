import AppKit
import Foundation

enum WorkspaceKind: String, Sendable {
    case swiftPackage
    case xcodeProject
    case xcodeWorkspace

    var displayName: String {
        switch self {
        case .swiftPackage:
            "Swift Package"
        case .xcodeProject:
            "Xcode Project"
        case .xcodeWorkspace:
            "Xcode Workspace"
        }
    }
}

struct WorkspaceDescriptor: Sendable {
    let url: URL
    let kind: WorkspaceKind
    let schemes: [String]
    let importableModules: [String]

    var displayName: String {
        url.lastPathComponent
    }
}

struct WorkspaceSelection: Sendable {
    let descriptor: WorkspaceDescriptor
    let scheme: String?
}

struct WorkspaceCompilationContext: Sendable {
    let compilerArguments: [String]
    let importableModules: [String]
    let runtimeArtifacts: [URL]
}

enum WorkspaceSupportError: LocalizedError {
    case unsupportedPath(URL)
    case invalidPackageMetadata
    case schemeRequired
    case buildFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedPath(url):
            "Could not recognize \(url.path) as a Swift package, `.xcodeproj`, or `.xcworkspace`."
        case .invalidPackageMetadata:
            "The selected package did not return readable metadata."
        case .schemeRequired:
            "Choose a scheme before compiling against this Xcode workspace."
        case let .buildFailed(output):
            output.isEmpty ? "The selected workspace failed to build." : output
        }
    }
}

struct CommandResult {
    let status: Int32
    let output: String
}

private struct LinkArtifacts {
    var compilerArguments: [String]
    var importableModules: [String]
    var runtimeArtifacts: [URL]
}

actor WorkspaceSupport {
    private let fileManager = FileManager.default
    private let scratchRoot: URL

    init() {
        scratchRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SafeAreaPreviewWorkspaceBuilds", isDirectory: true)
    }

    func inspect(url: URL) async throws -> WorkspaceDescriptor {
        let resolvedURL = try resolveWorkspaceURL(from: url)

        switch workspaceKind(for: resolvedURL) {
        case .swiftPackage:
            let modules = try await packageMetadata(at: resolvedURL)
            return WorkspaceDescriptor(
                url: resolvedURL,
                kind: .swiftPackage,
                schemes: [],
                importableModules: modules
            )
        case .xcodeProject:
            let schemes = try await listSchemes(at: resolvedURL, kind: .xcodeProject)
            return WorkspaceDescriptor(
                url: resolvedURL,
                kind: .xcodeProject,
                schemes: schemes,
                importableModules: []
            )
        case .xcodeWorkspace:
            let schemes = try await listSchemes(at: resolvedURL, kind: .xcodeWorkspace)
            return WorkspaceDescriptor(
                url: resolvedURL,
                kind: .xcodeWorkspace,
                schemes: schemes,
                importableModules: []
            )
        }
    }

    func prepareCompilation(for selection: WorkspaceSelection?) async throws -> WorkspaceCompilationContext {
        guard let selection else {
            return WorkspaceCompilationContext(
                compilerArguments: [],
                importableModules: [],
                runtimeArtifacts: []
            )
        }

        switch selection.descriptor.kind {
        case .swiftPackage:
            return try await prepareSwiftPackageCompilation(for: selection.descriptor)
        case .xcodeProject, .xcodeWorkspace:
            guard let scheme = selection.scheme, !scheme.isEmpty else {
                throw WorkspaceSupportError.schemeRequired
            }
            return try await prepareXcodeCompilation(for: selection.descriptor, scheme: scheme)
        }
    }

    private func resolveWorkspaceURL(from url: URL) throws -> URL {
        if workspaceKindIfDirectMatch(for: url) != nil {
            return url
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceSupportError.unsupportedPath(url)
        }

        let packageURL = url.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: packageURL.path) {
            return url
        }

        let candidates = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter { workspaceKindIfDirectMatch(for: $0) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        if let workspace = candidates.first(where: { $0.pathExtension == "xcworkspace" }) {
            return workspace
        }

        if let project = candidates.first(where: { $0.pathExtension == "xcodeproj" }) {
            return project
        }

        throw WorkspaceSupportError.unsupportedPath(url)
    }

    private func workspaceKind(for url: URL) -> WorkspaceKind {
        workspaceKindIfDirectMatch(for: url) ?? .swiftPackage
    }

    private func workspaceKindIfDirectMatch(for url: URL) -> WorkspaceKind? {
        switch url.pathExtension {
        case "xcworkspace":
            .xcodeWorkspace
        case "xcodeproj":
            .xcodeProject
        default:
            if fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                .swiftPackage
            } else {
                nil
            }
        }
    }

    private func packageMetadata(at url: URL) async throws -> [String] {
        let result = try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: [
                "swift",
                "package",
                "--package-path", url.path,
                "dump-package",
            ]
        )

        guard result.status == 0 else {
            throw WorkspaceSupportError.buildFailed(result.output)
        }

        guard
            let data = result.output.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let targets = json["targets"] as? [[String: Any]]
        else {
            throw WorkspaceSupportError.invalidPackageMetadata
        }

        let modules = targets.compactMap { target -> String? in
            guard let type = target["type"] as? String, type == "regular" else {
                return nil
            }

            return target["name"] as? String
        }

        return modules.sorted()
    }

    private func listSchemes(at url: URL, kind: WorkspaceKind) async throws -> [String] {
        let locationFlag = kind == .xcodeWorkspace ? "-workspace" : "-project"
        let result = try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: [
                "xcodebuild",
                locationFlag, url.path,
                "-list",
                "-json",
            ]
        )

        guard result.status == 0 else {
            throw WorkspaceSupportError.buildFailed(result.output)
        }

        guard
            let data = result.output.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }

        let containerKey = kind == .xcodeWorkspace ? "workspace" : "project"
        let container = json[containerKey] as? [String: Any]
        let schemes = container?["schemes"] as? [String] ?? []
        return schemes.sorted()
    }

    private func prepareSwiftPackageCompilation(for descriptor: WorkspaceDescriptor) async throws -> WorkspaceCompilationContext {
        let buildResult = try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: [
                "swift",
                "build",
                "--package-path", descriptor.url.path,
            ]
        )

        guard buildResult.status == 0 else {
            throw WorkspaceSupportError.buildFailed(buildResult.output)
        }

        let binPathResult = try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: [
                "swift",
                "build",
                "--package-path", descriptor.url.path,
                "--show-bin-path",
            ]
        )

        guard binPathResult.status == 0 else {
            throw WorkspaceSupportError.buildFailed(binPathResult.output)
        }

        let buildDirectory = URL(fileURLWithPath: binPathResult.output.trimmingCharacters(in: .whitespacesAndNewlines))
        var compilerArguments = [
            "-I", buildDirectory.appendingPathComponent("Modules").path,
        ]

        for module in descriptor.importableModules.sorted() {
            let objectDirectory = buildDirectory.appendingPathComponent("\(module).build", isDirectory: true)
            if let objectURLs = fileManager.enumerator(at: objectDirectory, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] {
                for fileURL in objectURLs where fileURL.pathExtension == "o" {
                    compilerArguments.append(fileURL.path)
                }
            }
        }

        let artifacts = scanLinkArtifacts(in: [buildDirectory])
        compilerArguments.append(contentsOf: artifacts.compilerArguments)

        return WorkspaceCompilationContext(
            compilerArguments: compilerArguments,
            importableModules: descriptor.importableModules,
            runtimeArtifacts: artifacts.runtimeArtifacts
        )
    }

    private func prepareXcodeCompilation(for descriptor: WorkspaceDescriptor, scheme: String) async throws -> WorkspaceCompilationContext {
        try fileManager.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let derivedDataPath = scratchRoot.appendingPathComponent(cacheKey(for: descriptor.url, scheme: scheme), isDirectory: true)

        let locationFlag = descriptor.kind == .xcodeWorkspace ? "-workspace" : "-project"
        let buildArguments = [
            "xcodebuild",
            locationFlag, descriptor.url.path,
            "-scheme", scheme,
            "-configuration", "Debug",
            "-derivedDataPath", derivedDataPath.path,
            "build",
            "CODE_SIGNING_ALLOWED=NO",
        ]

        let buildResult = try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: buildArguments
        )

        guard buildResult.status == 0 else {
            throw WorkspaceSupportError.buildFailed(buildResult.output)
        }

        let settingsResult = try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: [
                "xcodebuild",
                locationFlag, descriptor.url.path,
                "-scheme", scheme,
                "-configuration", "Debug",
                "-derivedDataPath", derivedDataPath.path,
                "-showBuildSettings",
                "-json",
            ]
        )

        guard settingsResult.status == 0 else {
            throw WorkspaceSupportError.buildFailed(settingsResult.output)
        }

        guard
            let data = settingsResult.output.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let buildSettings = json.first?["buildSettings"] as? [String: Any],
            let builtProductsPath = buildSettings["BUILT_PRODUCTS_DIR"] as? String
        else {
            throw WorkspaceSupportError.buildFailed(settingsResult.output)
        }

        let builtProductsDirectory = URL(fileURLWithPath: builtProductsPath)
        let packageFrameworksDirectory = builtProductsDirectory.appendingPathComponent("PackageFrameworks", isDirectory: true)
        let searchRoots = [builtProductsDirectory, packageFrameworksDirectory]
            .filter { fileManager.fileExists(atPath: $0.path) }

        let artifacts = scanLinkArtifacts(in: searchRoots)
        var compilerArguments = artifacts.compilerArguments

        if !artifacts.runtimeArtifacts.isEmpty {
            compilerArguments.append(contentsOf: [
                "-Xlinker", "-rpath",
                "-Xlinker", "@loader_path/../Frameworks",
            ])
        }

        return WorkspaceCompilationContext(
            compilerArguments: compilerArguments,
            importableModules: artifacts.importableModules,
            runtimeArtifacts: artifacts.runtimeArtifacts
        )
    }

    private func scanLinkArtifacts(in roots: [URL]) -> LinkArtifacts {
        var moduleDirectories = Set<URL>()
        var frameworkDirectories = Set<URL>()
        var libraryDirectories = Set<URL>()
        var frameworks = Set<String>()
        var libraries = Set<String>()
        var runtimeArtifacts = Set<URL>()
        var importableModules = Set<String>()

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                let pathExtension = url.pathExtension

                if pathExtension == "app" || pathExtension == "bundle" || pathExtension == "xctest" {
                    enumerator.skipDescendants()
                    continue
                }

                if pathExtension == "framework" {
                    frameworkDirectories.insert(url.deletingLastPathComponent())
                    frameworks.insert(url.deletingPathExtension().lastPathComponent)
                    runtimeArtifacts.insert(url)
                    continue
                }

                if pathExtension == "dylib" && url.lastPathComponent.hasPrefix("lib") {
                    libraryDirectories.insert(url.deletingLastPathComponent())
                    libraries.insert(String(url.deletingPathExtension().lastPathComponent.dropFirst(3)))
                    runtimeArtifacts.insert(url)
                    continue
                }

                if pathExtension == "a" && url.lastPathComponent.hasPrefix("lib") {
                    libraryDirectories.insert(url.deletingLastPathComponent())
                    libraries.insert(String(url.deletingPathExtension().lastPathComponent.dropFirst(3)))
                    continue
                }

                if pathExtension == "swiftmodule" {
                    moduleDirectories.insert(url.deletingLastPathComponent())
                    importableModules.insert(url.deletingPathExtension().lastPathComponent)
                }
            }
        }

        var arguments: [String] = []

        for directory in moduleDirectories.sorted(by: { $0.path < $1.path }) {
            arguments.append(contentsOf: ["-I", directory.path])
        }

        for directory in frameworkDirectories.sorted(by: { $0.path < $1.path }) {
            arguments.append(contentsOf: ["-F", directory.path])
        }

        for directory in libraryDirectories.sorted(by: { $0.path < $1.path }) {
            arguments.append(contentsOf: ["-L", directory.path])
        }

        for framework in frameworks.sorted() {
            arguments.append(contentsOf: ["-framework", framework])
            importableModules.insert(framework)
        }

        for library in libraries.sorted() {
            arguments.append(contentsOf: ["-l\(library)"])
            importableModules.insert(library)
        }

        return LinkArtifacts(
            compilerArguments: arguments,
            importableModules: importableModules.sorted(),
            runtimeArtifacts: runtimeArtifacts.sorted(by: { $0.path < $1.path })
        )
    }

    private func cacheKey(for url: URL, scheme: String) -> String {
        let joined = "\(url.path)::\(scheme)"
        let sanitized = joined
            .map { character -> Character in
                if character.isLetter || character.isNumber {
                    character
                } else {
                    "_"
                }
            }
        return String(sanitized.prefix(80))
    }
}

@discardableResult
nonisolated
private func runCommand(
    executableURL: URL,
    arguments: [String],
    currentDirectoryURL: URL? = nil
) throws -> CommandResult {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = executableURL
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectoryURL
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return CommandResult(status: process.terminationStatus, output: output)
}

enum WorkspacePicker {
    @MainActor
    static func pickWorkspace() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.message = "Choose a Swift package folder, `.xcodeproj`, or `.xcworkspace`."
        return panel.runModal() == .OK ? panel.url : nil
    }
}
