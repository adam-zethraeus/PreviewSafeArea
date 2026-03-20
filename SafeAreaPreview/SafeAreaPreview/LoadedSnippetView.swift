import AppKit
import SwiftUI

struct LoadedSnippetView: NSViewControllerRepresentable {
    let snippet: LoadedSnippet

    func makeNSViewController(context: Context) -> NSViewController {
        snippet.controllerType.init(nibName: nil, bundle: snippet.bundle)
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
    }
}
