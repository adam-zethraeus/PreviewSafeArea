import SwiftUI
import PreviewSafeArea

struct ContentView: View {
    @AppStorage("snippetSource") private var source = SnippetTemplate.defaultSource
    @AppStorage("workspacePath") private var workspacePath = ""
    @AppStorage("workspaceScheme") private var workspaceScheme = ""

    @State private var runner = SnippetRunner()
    @State private var workspaceDescriptor: WorkspaceDescriptor?
    @State private var workspaceStatus: WorkspaceStatus = .idle

    private let workspaceSupport = WorkspaceSupport()

    var body: some View {
        HSplitView {
            editorPane
                .frame(minWidth: 380, idealWidth: 470)

            previewPane
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 680)
        .task {
            await bootstrap()
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workspace")
                            .font(.title3.weight(.semibold))

                        Text("Point the snippet compiler at a Swift package, Xcode project, or workspace.")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if workspaceDescriptor != nil {
                        Button("Clear") {
                            clearWorkspace()
                        }
                        .disabled(isInspectingWorkspace)
                    }

                    Button(isInspectingWorkspace ? "Inspecting..." : "Choose Workspace") {
                        chooseWorkspace()
                    }
                    .disabled(isInspectingWorkspace || runner.isCompiling)
                }

                workspacePanel
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Snippet")
                            .font(.title2.weight(.semibold))

                        Text("Define a `SnippetRoot: View`, then run it inside the safe-area preview.")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Reset Example") {
                        source = SnippetTemplate.defaultSource
                    }
                    .disabled(runner.isCompiling)

                    Button(runner.isCompiling ? "Compiling..." : "Run Snippet") {
                        Task {
                            await runner.compile(source: source, workspace: workspaceSelection)
                        }
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(runner.isCompiling || isInspectingWorkspace || workspaceNeedsSchemeSelection)
                }

                TextEditor(text: $source)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    }

                statusPane
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var workspacePanel: some View {
        if let descriptor = workspaceDescriptor {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Type") {
                    Text(descriptor.kind.displayName)
                }

                LabeledContent("Path") {
                    Text(descriptor.url.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }

                if !descriptor.schemes.isEmpty {
                    Picker("Scheme", selection: $workspaceScheme) {
                        Text("Select a scheme").tag("")
                        ForEach(descriptor.schemes, id: \.self) { scheme in
                            Text(scheme).tag(scheme)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if !descriptor.importableModules.isEmpty {
                    LabeledContent("Modules") {
                        Text(descriptor.importableModules.joined(separator: ", "))
                            .font(.system(.caption, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                    }
                } else {
                    Text(descriptor.schemes.isEmpty
                         ? "No importable library targets were discovered."
                         : "Build products from the selected scheme will be made available at compile time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if case let .failed(message) = workspaceStatus {
                    Text(message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(.background.secondary.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(isInspectingWorkspace ? "Inspecting workspace..." : "No workspace selected")
                    .font(.subheadline.weight(.medium))

                Text("Snippets can still use system frameworks without a workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if case let .failed(message) = workspaceStatus {
                    Text(message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var statusPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            if workspaceNeedsSchemeSelection {
                statusRow(label: "Choose a scheme to compile against this workspace", color: .orange)
            }

            switch runner.state {
            case .idle:
                statusRow(label: "Ready", color: .secondary)
            case .compiling:
                statusRow(label: "Compiling snippet...", color: .orange)
            case .loaded:
                statusRow(label: "Loaded", color: .green)
            case let .failed(message):
                statusRow(label: "Compile failed", color: .red)
                ScrollView {
                    Text(message)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 200)
                .padding(10)
                .background(.background.secondary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .animation(.default, value: runner.state.id)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Safe Area Preview")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            PreviewSafeArea {
                Group {
                    if let snippet = runner.loadedSnippet {
                        LoadedSnippetView(snippet: snippet)
                    } else {
                        placeholderView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
            .padding(20)
        }
        .background(.background.secondary.opacity(0.15))
    }

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text(runner.isCompiling ? "Building snippet..." : "No compiled snippet yet")
                .font(.headline)

            Text("Run the code on the left to render it here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workspaceSelection: WorkspaceSelection? {
        guard let workspaceDescriptor else {
            return nil
        }

        let scheme = workspaceDescriptor.schemes.isEmpty ? nil : workspaceScheme
        return WorkspaceSelection(descriptor: workspaceDescriptor, scheme: scheme)
    }

    private var isInspectingWorkspace: Bool {
        if case .inspecting = workspaceStatus {
            true
        } else {
            false
        }
    }

    private var workspaceNeedsSchemeSelection: Bool {
        guard let workspaceDescriptor else {
            return false
        }

        return !workspaceDescriptor.schemes.isEmpty && workspaceScheme.isEmpty
    }

    private func statusRow(label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.subheadline.weight(.medium))
        }
    }

    private func bootstrap() async {
        if let restoredURL = restoredWorkspaceURL {
            await inspectWorkspace(at: restoredURL)
        }

        await runner.compile(source: source, workspace: workspaceSelection)
    }

    private var restoredWorkspaceURL: URL? {
        guard !workspacePath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: workspacePath)
    }

    private func chooseWorkspace() {
        guard let url = WorkspacePicker.pickWorkspace() else {
            return
        }

        workspacePath = url.path
        Task {
            await inspectWorkspace(at: url)
        }
    }

    private func clearWorkspace() {
        workspaceDescriptor = nil
        workspaceStatus = .idle
        workspacePath = ""
        workspaceScheme = ""
    }

    private func inspectWorkspace(at url: URL) async {
        workspaceStatus = .inspecting

        do {
            let descriptor = try await workspaceSupport.inspect(url: url)
            workspaceDescriptor = descriptor
            workspaceStatus = .loaded

            if descriptor.schemes.isEmpty {
                workspaceScheme = ""
            } else if !descriptor.schemes.contains(workspaceScheme) {
                workspaceScheme = descriptor.schemes.first ?? ""
            }
        } catch {
            workspaceDescriptor = nil
            workspaceStatus = .failed(error.localizedDescription)
        }
    }
}

private enum WorkspaceStatus {
    case idle
    case inspecting
    case loaded
    case failed(String)
}

enum SnippetTemplate {
    static let defaultSource = """
    import SwiftUI

    struct SnippetRoot: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [.orange, .yellow, .mint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 20) {
                    Text("SnippetRoot")
                        .font(.largeTitle.weight(.bold))

                    Text("Try `.ignoresSafeArea()`, `.safeAreaInset`, or your own layout code.")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)

                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                        .frame(width: 220, height: 120)
                        .overlay {
                            Text("Drag the handles to change the safe area.")
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                }
                .padding(32)
            }
        }
    }
    """
}

#Preview {
    ContentView()
}
