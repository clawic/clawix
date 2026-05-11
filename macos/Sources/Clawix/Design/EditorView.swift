import SwiftUI
import WebKit

/// Three-column visual editor for one Template instance.
///
///   ┌────────────┬───────────────────┬────────────┐
///   │  Layers    │      Canvas       │ Inspector  │
///   │  (list)    │  (WKWebView)      │ (controls) │
///   └────────────┴───────────────────┴────────────┘
///
/// Selecting a slot anywhere (layers panel or canvas) syncs both
/// sides via `selectedSlotId`. Edits in the inspector mutate the
/// document binding and trigger a debounced auto-save + canvas
/// refresh. Double-click on a text slot in the canvas opens an
/// inline `contenteditable` editor that posts its committed text back
/// through the harness JS.
struct EditorView: View {
    let documentId: String
    @EnvironmentObject var appState: AppState
    @ObservedObject private var store: EditorStore = .shared
    @ObservedObject private var design: DesignStore = .shared

    @State private var draft: EditorDocument?
    @State private var selectedSlotId: String?
    @State private var saveError: String?
    @State private var exportMessage: String?
    @State private var isExporting: Bool = false
    @State private var saveTask: DispatchWorkItem?
    @State private var coordinator = CanvasCoordinator()
    @State private var pendingDelete: Bool = false

    fileprivate final class CanvasCoordinator: ObservableObject {
        weak var webView: WKWebView?
        var lastRenderedKey: String = ""
    }

    var body: some View {
        if let document = currentDocument, let template = design.template(id: document.templateId) {
            let style = design.style(id: document.styleId) ?? design.styles.first ?? fallbackStyle(template: template)
            let html = renderHTML(document: document, template: template, style: style)
            let dims = template.aspect.size
            return AnyView(
                VStack(spacing: 0) {
                    topBar(document: document, template: template)
                    Divider().opacity(0.18)
                    if let exportMessage {
                        statusBanner(exportMessage)
                            .padding(.horizontal, 18)
                            .padding(.top, 10)
                    }
                    if let saveError {
                        errorBanner(saveError)
                            .padding(.horizontal, 18)
                            .padding(.top, 10)
                    }
                    HStack(spacing: 0) {
                        EditorLayers(
                            template: template,
                            document: document,
                            selectedSlotId: selectedSlotId
                        ) { slotId in
                            selectedSlotId = slotId
                        }
                        .frame(width: 220)
                        .background(Palette.sidebar.opacity(0.45))
                        Divider().opacity(0.18)
                        ZStack {
                            Color.black.opacity(0.78)
                            CanvasHost(
                                html: html,
                                baseURL: store.documentDir(for: document.id),
                                selectedSlotId: selectedSlotId,
                                coordinator: coordinator
                            ) { message in
                                handle(message: message)
                            }
                            .padding(28)
                            .aspectRatio(CGFloat(dims.width / dims.height), contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider().opacity(0.18)
                        EditorInspector(
                            document: Binding(
                                get: { draft ?? document },
                                set: { draft = $0; scheduleSave() }
                            ),
                            template: template,
                            style: style,
                            selectedSlotId: selectedSlotId,
                            availableStyles: design.styles
                        ) { slotId, sourceURL in
                            attachAsset(slotId: slotId, sourceURL: sourceURL)
                        } onCommit: {
                            scheduleSave()
                        }
                        .frame(width: 320)
                        .background(Palette.sidebar.opacity(0.45))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
                .onAppear {
                    if draft == nil { draft = store.document(id: documentId) }
                }
                .onChange(of: documentId) { _, _ in draft = store.document(id: documentId) }
                .alert("Delete \(document.name)?", isPresented: $pendingDelete) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) { performDelete() }
                } message: {
                    Text("This editor document will be removed from disk. Its assets will be deleted too.")
                }
            )
        } else {
            return AnyView(notFound)
        }
    }

    // MARK: - Top bar

    private func topBar(document: EditorDocument, template: TemplateManifest) -> some View {
        HStack(spacing: 12) {
            Button {
                flushPendingSave()
                appState.currentRoute = .designTemplateDetail(id: template.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Back")
                        .font(BodyFont.system(size: 12.5, wght: 500))
                }
                .foregroundColor(Color(white: 0.65))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(document.name)
                    .font(BodyFont.system(size: 14, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(template.name) · \(template.aspect.displayLabel)")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(EditorExport.Format.allCases) { format in
                    Button {
                        export(format: format)
                    } label: {
                        Text(format.label)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.85))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(Palette.border, lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)
                    .opacity(isExporting ? 0.5 : 1.0)
                }
                Button {
                    pendingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.55))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.red.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func statusBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.40, green: 0.85, blue: 0.55))
            Text(text)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(2)
            Spacer()
            Button {
                exportMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.65))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.green.opacity(0.30), lineWidth: 0.5)
                )
        )
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.45))
            Text(text)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(2)
            Spacer()
            Button {
                saveError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.65))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.red.opacity(0.30), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Wiring

    private var currentDocument: EditorDocument? {
        draft ?? store.document(id: documentId)
    }

    private func handle(message: EditorCanvasMessage) {
        switch message {
        case .click(let id, _):
            selectedSlotId = id
        case .hover:
            break
        case .edit(let id, let text):
            guard var doc = draft ?? store.document(id: documentId) else { return }
            doc.data[id] = text.isEmpty ? .empty : .text(text)
            draft = doc
            scheduleSave()
        }
    }

    private func renderHTML(document: EditorDocument, template: TemplateManifest, style: StyleManifest) -> String {
        let options = RendererHTML.Options(includeEditorHarness: true) { slotId in
            guard let asset = document.data[slotId]?.asAsset else { return nil }
            return store.assetURL(for: document, value: asset)
        }
        return RendererHTML.render(document: document, template: template, style: style, options: options)
    }

    private func fallbackStyle(template: TemplateManifest) -> StyleManifest {
        DesignBuiltins.styles().first { $0.id == "claw" } ?? DesignBuiltins.styles()[0]
    }

    // MARK: - Save / asset

    private func scheduleSave() {
        saveTask?.cancel()
        let work = DispatchWorkItem { [self] in
            flushPendingSave()
        }
        saveTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func flushPendingSave() {
        guard let candidate = draft else { return }
        do {
            try store.update(candidate)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func attachAsset(slotId: String, sourceURL: URL) {
        guard var doc = draft ?? store.document(id: documentId) else { return }
        do {
            let asset = try store.storeAsset(sourceURL: sourceURL, into: doc, slotId: slotId)
            doc.data[slotId] = .asset(asset)
            draft = doc
            flushPendingSave()
        } catch {
            saveError = "Could not attach asset: \(error.localizedDescription)"
        }
    }

    private func performDelete() {
        guard let doc = currentDocument else { return }
        let templateId = doc.templateId
        do {
            try store.delete(doc)
            appState.currentRoute = .designTemplateDetail(id: templateId)
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Export

    private func export(format: EditorExport.Format) {
        guard let doc = currentDocument else { return }
        let panel = EditorExport.defaultSavePanel(for: format, suggestedName: doc.name.isEmpty ? "Untitled" : doc.name)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let template = design.template(id: doc.templateId) else { return }
        let style = design.style(id: doc.styleId) ?? design.styles.first ?? fallbackStyle(template: template)
        let cleanOptions = RendererHTML.Options(includeEditorHarness: false) { slotId in
            guard let asset = doc.data[slotId]?.asAsset else { return nil }
            return store.assetURL(for: doc, value: asset)
        }
        let html = RendererHTML.render(document: doc, template: template, style: style, options: cleanOptions)
        let dims = template.aspect.size
        switch format {
        case .html:
            do {
                try EditorExport.writeHTML(html, to: url)
                exportMessage = "Exported HTML to \(url.lastPathComponent)"
            } catch {
                saveError = error.localizedDescription
            }
        case .svg:
            do {
                try EditorExport.writeSVG(html: html, width: dims.width, height: dims.height, to: url)
                exportMessage = "Exported SVG to \(url.lastPathComponent)"
            } catch {
                saveError = error.localizedDescription
            }
        case .png:
            guard let webView = coordinator.webView else {
                saveError = "Canvas is still loading."
                return
            }
            isExporting = true
            EditorExport.writePNG(webView: webView, to: url) { result in
                Task { @MainActor in
                    isExporting = false
                    switch result {
                    case .success: exportMessage = "Exported PNG to \(url.lastPathComponent)"
                    case .failure(let err): saveError = err.localizedDescription
                    }
                }
            }
        case .pdf:
            guard let webView = coordinator.webView else {
                saveError = "Canvas is still loading."
                return
            }
            isExporting = true
            EditorExport.writePDF(webView: webView, to: url) { result in
                Task { @MainActor in
                    isExporting = false
                    switch result {
                    case .success: exportMessage = "Exported PDF to \(url.lastPathComponent)"
                    case .failure(let err): saveError = err.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - Not found

    private var notFound: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(white: 0.40))
            Text("Editor document not found")
                .font(BodyFont.system(size: 15, wght: 500))
                .foregroundColor(Color(white: 0.70))
            Button("Back to templates") {
                appState.currentRoute = .designTemplatesHome
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

/// Thin wrapper around `EditorCanvas` that keeps the `WKWebView`
/// reference live in the parent's coordinator so export helpers can
/// reach it without crawling the SwiftUI hierarchy.
private struct CanvasHost: NSViewRepresentable {
    let html: String
    let baseURL: URL
    let selectedSlotId: String?
    let coordinator: EditorView.CanvasCoordinator
    var onMessage: (EditorCanvasMessage) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let bridge = HostBridge(onMessage: onMessage)
        controller.add(bridge, name: "clawixEditor")
        config.userContentController = controller
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.bridge = bridge
        context.coordinator.lastHTML = html
        DispatchQueue.main.async {
            self.coordinator.webView = view
        }
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        }
        context.coordinator.bridge?.onMessage = onMessage
        let safeId = selectedSlotId.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" } ?? "null"
        webView.evaluateJavaScript("window.clawixSelectSlot && window.clawixSelectSlot(\(safeId));", completionHandler: nil)
    }

    func makeCoordinator() -> HostCoordinator { HostCoordinator() }

    final class HostCoordinator {
        var bridge: HostBridge?
        var lastHTML: String = ""
    }

    final class HostBridge: NSObject, WKScriptMessageHandler {
        var onMessage: (EditorCanvasMessage) -> Void

        init(onMessage: @escaping (EditorCanvasMessage) -> Void) {
            self.onMessage = onMessage
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }
            switch type {
            case "slot.click":
                guard let id = payload["id"] as? String else { return }
                let kind = payload["kind"] as? String
                onMessage(.click(id: id, kind: kind))
            case "slot.hover":
                onMessage(.hover(id: payload["id"] as? String))
            case "slot.edit":
                guard let id = payload["id"] as? String, let text = payload["text"] as? String else { return }
                onMessage(.edit(id: id, text: text))
            default:
                break
            }
        }
    }
}
