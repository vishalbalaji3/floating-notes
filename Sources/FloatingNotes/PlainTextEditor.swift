import AppKit
import SwiftUI
import WebKit

/// The responder-chain endpoint for the Format menu. CodeMirror also owns these shortcuts,
/// while these selectors let menu clicks invoke the exact same editor commands.
final class MarkdownWebView: WKWebView {
    @objc func toggleMarkdownBold(_ sender: Any?) { applyFormatting("bold") }
    @objc func toggleMarkdownItalic(_ sender: Any?) { applyFormatting("italic") }
    @objc func toggleMarkdownUnderline(_ sender: Any?) { applyFormatting("underline") }
    @objc func toggleMarkdownStrikethrough(_ sender: Any?) { applyFormatting("strikethrough") }
    @objc func insertMarkdownLink(_ sender: Any?) { applyFormatting("link") }
    @objc func toggleMarkdownInlineCode(_ sender: Any?) { applyFormatting("inlineCode") }
    @objc func insertMarkdownCodeBlock(_ sender: Any?) { applyFormatting("codeBlock") }
    @objc func toggleMarkdownBlockQuote(_ sender: Any?) { applyFormatting("quote") }

    func applyFormatting(_ action: String, level: Int? = nil) {
        let encodedAction = Self.javascriptLiteral(action)
        let levelArgument = level.map(String.init) ?? "1"
        evaluateJavaScript("window.applyFormatting(\(encodedAction), \(levelArgument))")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateEditorAppearance()
    }

    func updateEditorAppearance() {
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        let isDark = match == .darkAqua
        evaluateJavaScript(
            "document.documentElement.classList.toggle('theme-dark', \(isDark ? "true" : "false"))"
        )
    }

    fileprivate static func javascriptLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let array = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return String(array.dropFirst().dropLast())
    }
}

/// A CodeMirror 6 editor hosted in WKWebView. Markdown remains the source of truth on disk, but
/// formatting is previewed in place and unfolds back to source whenever the cursor enters it.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var pendingInsertion: PendingMarkdownInsertion?
    /// Changes whenever a different note is loaded; the coordinator swaps the editor's content
    /// in place so the web view (and its loaded CodeMirror page) survives note switches.
    var identity: UUID
    var initialCursorPosition: Int
    var onCursorChange: (Int) -> Void
    var onShowActions: () -> Void
    var onShowSettings: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> MarkdownWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "bridge")

        let webView = MarkdownWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .clear
        }
        context.coordinator.webView = webView

        let editorURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "Editor"
        ) ?? Bundle.module.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "Editor"
        )
        guard let editorURL else {
            assertionFailure("Missing bundled Markdown editor")
            return webView
        }
        webView.loadFileURL(editorURL, allowingReadAccessTo: editorURL.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ webView: MarkdownWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.isReady else { return }

        if context.coordinator.displayedIdentity != identity {
            context.coordinator.displayedIdentity = identity
            context.coordinator.setContent(text, cursor: initialCursorPosition)
            context.coordinator.focusEditor()
        } else if context.coordinator.editorText != text {
            context.coordinator.setContent(text, cursor: initialCursorPosition)
        }
        context.coordinator.applyPendingInsertionIfNeeded()
    }

    static func dismantleNSView(_ webView: MarkdownWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "bridge")
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: PlainTextEditor
        weak var webView: MarkdownWebView?
        var isReady = false
        var editorText = ""
        var displayedIdentity: UUID?
        private var lastAppliedInsertionID: UUID?

        init(_ parent: PlainTextEditor) {
            self.parent = parent
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            switch action {
            case "ready":
                isReady = true
                webView?.updateEditorAppearance()
                displayedIdentity = parent.identity
                setContent(parent.text, cursor: parent.initialCursorPosition)
                applyPendingInsertionIfNeeded()
                focusEditor()

            case "contentChanged":
                guard let content = body["content"] as? String else { return }
                editorText = content
                parent.text = content

            case "selectionChanged":
                guard let position = body["position"] as? NSNumber else { return }
                parent.onCursorChange(position.intValue)

            case "showActions":
                parent.onShowActions()

            case "showSettings":
                parent.onShowSettings()

            case "openURL":
                guard let value = body["url"] as? String,
                      let url = URL(string: value),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { return }
                NSWorkspace.shared.open(url)

            case "error":
                if let error = body["message"] as? String {
                    NSLog("Floating Notes editor error: %@", error)
                }

            default:
                break
            }
        }

        func setContent(_ content: String, cursor: Int) {
            guard let webView else { return }
            editorText = content
            let encoded = MarkdownWebView.javascriptLiteral(content)
            let clamped = min(max(0, cursor), (content as NSString).length)
            webView.evaluateJavaScript("window.setContent(\(encoded), \(clamped))")
        }

        /// Wait until the button/menu action that selected the note has finished, then move both
        /// AppKit and DOM focus into CodeMirror so typing can begin immediately.
        func focusEditor() {
            DispatchQueue.main.async { [weak self] in
                guard let webView = self?.webView else { return }
                webView.window?.makeFirstResponder(webView)
                webView.evaluateJavaScript("window.focusEditor()")
            }
        }

        func applyPendingInsertionIfNeeded() {
            guard isReady,
                  let pending = parent.pendingInsertion,
                  pending.id != lastAppliedInsertionID,
                  let webView else { return }
            lastAppliedInsertionID = pending.id

            switch pending.action {
            case .heading(let level): webView.applyFormatting("heading", level: level)
            case .bold: webView.applyFormatting("bold")
            case .italic: webView.applyFormatting("italic")
            case .underline: webView.applyFormatting("underline")
            case .strikethrough: webView.applyFormatting("strikethrough")
            case .link: webView.applyFormatting("link")
            case .inlineCode: webView.applyFormatting("inlineCode")
            case .codeBlock: webView.applyFormatting("codeBlock")
            case .quote: webView.applyFormatting("quote")
            case .bulletList: webView.applyFormatting("bulletList")
            case .numberedList: webView.applyFormatting("numberedList")
            case .checklist: webView.applyFormatting("checklist")
            }
        }
    }
}
