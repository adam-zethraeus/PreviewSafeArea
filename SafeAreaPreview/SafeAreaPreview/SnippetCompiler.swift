import AppKit
import Combine
import Foundation

enum SnippetCompilerError: LocalizedError {
    case invalidCompilerOutput
    case failedToLoadBundle(URL)
    case missingPrincipalClass(URL)
    case principalClassIsNotViewController(String)
    case compilerFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCompilerOutput:
            "The compiler did not produce a loadable bundle."
        case let .failedToLoadBundle(url):
            "The compiled bundle at \(url.path) could not be loaded."
        case let .missingPrincipalClass(url):
            "The compiled bundle at \(url.path) did not expose a principal class."
        case let .principalClassIsNotViewController(name):
            "The compiled principal class `\(name)` is not an `NSViewController`."
        case let .compilerFailed(output):
            output
        }
    }
}

final class LoadedSnippet: @unchecked Sendable {
    let bundle: Bundle
    let controllerType: NSViewController.Type

    nonisolated init(bundle: Bundle, controllerType: NSViewController.Type) {
        self.bundle = bundle
        self.controllerType = controllerType
    }
}

actor SnippetCompiler {
    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let workspaceSupport = WorkspaceSupport()

    init() {
        rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("SafeAreaPreviewSnippets", isDirectory: true)
    }

    func compile(source: String, workspace: WorkspaceSelection?) async throws -> LoadedSnippet {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let moduleName = "UserSnippet_\(token)"
        let className = "UserSnippetViewController_\(token)"
        let sessionDirectory = rootDirectory.appendingPathComponent(token, isDirectory: true)
        let bundleURL = sessionDirectory.appendingPathComponent("\(moduleName).bundle", isDirectory: true)
        let executableURL = bundleURL.appendingPathComponent("Contents/MacOS/\(moduleName)")
        let userSourceURL = sessionDirectory.appendingPathComponent("SnippetRoot.swift")
        let wrapperSourceURL = sessionDirectory.appendingPathComponent("SnippetWrapper.swift")
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")

        try fileManager.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: userSourceURL, atomically: true, encoding: .utf8)
        try wrapperSource(className: className).write(to: wrapperSourceURL, atomically: true, encoding: .utf8)
        try infoPlist(moduleName: moduleName, className: className).write(to: infoPlistURL, atomically: true, encoding: .utf8)

        let workspaceContext = try await workspaceSupport.prepareCompilation(for: workspace)
        let output = try runCompiler(
            moduleName: moduleName,
            executableURL: executableURL,
            userSourceURL: userSourceURL,
            wrapperSourceURL: wrapperSourceURL,
            workingDirectory: sessionDirectory,
            workspaceContext: workspaceContext
        )

        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw SnippetCompilerError.invalidCompilerOutput
        }

        try embedRuntimeArtifacts(workspaceContext.runtimeArtifacts, into: bundleURL)

        guard let bundle = Bundle(path: bundleURL.path) else {
            throw SnippetCompilerError.invalidCompilerOutput
        }

        guard bundle.load() else {
            throw SnippetCompilerError.failedToLoadBundle(bundleURL)
        }

        guard let principalClass = bundle.principalClass else {
            throw SnippetCompilerError.missingPrincipalClass(bundleURL)
        }

        guard let controllerType = principalClass as? NSViewController.Type else {
            throw SnippetCompilerError.principalClassIsNotViewController(NSStringFromClass(principalClass))
        }

        if !output.isEmpty {
            print(output)
        }

        return LoadedSnippet(bundle: bundle, controllerType: controllerType)
    }

    private func runCompiler(
        moduleName: String,
        executableURL: URL,
        userSourceURL: URL,
        wrapperSourceURL: URL,
        workingDirectory: URL,
        workspaceContext: WorkspaceCompilationContext
    ) throws -> String {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        var arguments = [
            "swiftc",
            "-parse-as-library",
            "-emit-library",
            "-module-name", moduleName,
            userSourceURL.path,
            wrapperSourceURL.path,
        ]
        arguments.append(contentsOf: workspaceContext.compilerArguments)
        arguments.append(contentsOf: [
            "-o", executableURL.path,
        ])

        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.currentDirectoryURL = workingDirectory

        try process.run()
        process.waitUntilExit()

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw SnippetCompilerError.compilerFailed(output.isEmpty ? "Compilation failed." : output)
        }

        return output
    }

    private func embedRuntimeArtifacts(_ artifacts: [URL], into bundleURL: URL) throws {
        guard !artifacts.isEmpty else {
            return
        }

        let frameworksDirectory = bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        try fileManager.createDirectory(at: frameworksDirectory, withIntermediateDirectories: true)

        for artifact in artifacts {
            let destination = frameworksDirectory.appendingPathComponent(artifact.lastPathComponent, isDirectory: false)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: artifact, to: destination)
        }
    }

    private func wrapperSource(className: String) -> String {
        """
        import AppKit
        import SwiftUI

        @objc(\(className))
        final class \(className): NSViewController {
            override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
                super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func loadView() {
                self.view = NSHostingView(rootView: AnyView(SnippetRoot()))
            }
        }
        """
    }

    private func infoPlist(moduleName: String, className: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>en</string>
            <key>CFBundleExecutable</key>
            <string>\(moduleName)</string>
            <key>CFBundleIdentifier</key>
            <string>llc.goodhats.SafeAreaPreview.snippet.\(moduleName.lowercased())</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>\(moduleName)</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
            <key>NSPrincipalClass</key>
            <string>\(className)</string>
        </dict>
        </plist>
        """
    }
}

@MainActor
final class SnippetRunner: ObservableObject {
    enum State {
        case idle
        case compiling(String)
        case loaded(String)
        case failed(String)

        var id: String {
            switch self {
            case .idle:
                "idle"
            case .compiling:
                "compiling"
            case .loaded:
                "loaded"
            case .failed:
                "failed"
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var loadedSnippet: LoadedSnippet?

    var isCompiling: Bool {
        if case .compiling = state {
            true
        } else {
            false
        }
    }

    private let compiler = SnippetCompiler()

    func compile(source: String, workspace: WorkspaceSelection?) async {
        loadedSnippet = nil
        state = .compiling("Building a fresh runtime bundle for the current snippet.")

        do {
            let snippet = try await compiler.compile(source: source, workspace: workspace)
            loadedSnippet = snippet
            state = .loaded(successMessage(for: workspace))
        } catch {
            loadedSnippet = nil
            state = .failed(error.localizedDescription)
        }
    }

    private func successMessage(for workspace: WorkspaceSelection?) -> String {
        if let workspace {
            switch workspace.descriptor.kind {
            case .swiftPackage:
                if workspace.descriptor.importableModules.isEmpty {
                    return "Snippet compiled against the selected Swift package."
                } else {
                    return "Snippet compiled against modules from \(workspace.descriptor.displayName)."
                }
            case .xcodeProject, .xcodeWorkspace:
                if let scheme = workspace.scheme {
                    return "Snippet compiled against build products from the `\(scheme)` scheme."
                } else {
                    return "Snippet compiled against the selected Xcode workspace."
                }
            }
        }

        return "Snippet compiled against the system SDKs."
    }
}
