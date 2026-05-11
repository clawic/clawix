import PhotosUI
import SwiftUI
import UIKit
import WebKit

/// iPad / iPhone editor canvas. On regular size class (iPad landscape,
/// big iPad portrait), shows the desktop's three-column layout —
/// layers / canvas / inspector. On compact size class (iPhone or split
/// iPad), the canvas stays on top and layers + inspector live behind
/// two bottom-sheet tabs.
struct EditorView: View {
    let documentId: String
    var onClose: () -> Void

    @ObservedObject private var store: EditorStore = .shared
    @ObservedObject private var design: DesignStore = .shared

    @State private var draft: EditorDocument?
    @State private var selectedSlotId: String?
    @State private var saveError: String?
    @State private var exportMessage: String?
    @State private var isExporting: Bool = false
    @State private var saveTask: DispatchWorkItem?
    @State private var pendingDelete: Bool = false
    @State private var assetSlotId: String?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var sharePayload: SharePayload?
    @State private var compactPane: CompactPane = .canvas
    @State private var webViewRef = WebViewBox()
    @State private var inspectorSheetOpen: Bool = false
    @Environment(\.horizontalSizeClass) private var hSize

    enum CompactPane: String, CaseIterable, Identifiable {
        case canvas, layers
        var id: String { rawValue }
        var label: String {
            switch self {
            case .canvas: return "Canvas"
            case .layers: return "Layers"
            }
        }
    }

    private struct SharePayload: Identifiable {
        let id = UUID()
        let url: URL
    }

    final class WebViewBox {
        weak var webView: WKWebView?
    }

    var body: some View {
        Group {
            if let document = currentDocument, let template = design.template(id: document.templateId) {
                let style = design.style(id: document.styleId) ?? design.styles.first ?? fallbackStyle()
                let html = renderHTML(document: document, template: template, style: style)
                VStack(spacing: 0) {
                    topBar(document: document, template: template)
                    if let exportMessage { statusBanner(exportMessage).padding(.horizontal, 14).padding(.top, 8) }
                    if let saveError { errorBanner(saveError).padding(.horizontal, 14).padding(.top, 8) }
                    if hSize == .regular {
                        regularLayout(document: document, template: template, style: style, html: html)
                    } else {
                        compactLayout(document: document, template: template, style: style, html: html)
                    }
                }
            } else {
                notFound
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if draft == nil { draft = store.document(id: documentId) } }
        .onChange(of: photoPickerItem) { _, item in
            guard let item, let slotId = assetSlotId else { return }
            Task { await ingestPhoto(item: item, slotId: slotId) }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.url])
        }
        .confirmationDialog("Delete draft?", isPresented: $pendingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This editor document will be removed from disk.")
        }
        .photosPicker(isPresented: photosPresentation, selection: $photoPickerItem, matching: .images)
    }

    // MARK: - Layouts

    private func regularLayout(document: EditorDocument, template: TemplateManifest, style: StyleManifest, html: String) -> some View {
        HStack(spacing: 0) {
            EditorLayers(template: template, document: document, selectedSlotId: selectedSlotId) { slotId in
                selectedSlotId = slotId
            }
            .frame(width: 240)
            .background(Color.white.opacity(0.04))
            Divider().opacity(0.18)
            canvasContainer(document: document, template: template, html: html)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.18)
            inspectorBlock(document: document, template: template, style: style)
                .frame(width: 320)
                .background(Color.white.opacity(0.04))
        }
    }

    private func compactLayout(document: EditorDocument, template: TemplateManifest, style: StyleManifest, html: String) -> some View {
        ZStack(alignment: .bottom) {
            switch compactPane {
            case .canvas:
                canvasContainer(document: document, template: template, html: html)
            case .layers:
                EditorLayers(template: template, document: document, selectedSlotId: selectedSlotId) { slotId in
                    Haptics.selection()
                    selectedSlotId = slotId
                    compactPane = .canvas
                    inspectorSheetOpen = true
                }
            }
            compactFloatingDock
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .sheet(isPresented: $inspectorSheetOpen) {
            NavigationStack {
                ScrollView {
                    inspectorBlock(document: document, template: template, style: style)
                }
                .background(Palette.background.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        if let slot = template.slots.first(where: { $0.id == selectedSlotId }) {
                            VStack(spacing: 1) {
                                Text(slot.label)
                                    .font(BodyFont.system(size: 14, wght: 600))
                                    .foregroundColor(Palette.textPrimary)
                                Text(slot.kind.rawValue.uppercased())
                                    .font(BodyFont.system(size: 9.5, wght: 700))
                                    .foregroundColor(Color(white: 0.55))
                                    .tracking(0.4)
                            }
                        } else {
                            Text("Inspector")
                                .font(BodyFont.system(size: 14, wght: 600))
                                .foregroundColor(Palette.textPrimary)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            Haptics.tap()
                            inspectorSheetOpen = false
                        }
                        .foregroundStyle(Palette.textPrimary)
                    }
                }
            }
            .presentationDetents([.fraction(0.55), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.background)
        }
    }

    private var compactFloatingDock: some View {
        GlassEffectContainer {
            HStack(spacing: 10) {
                dockButton(icon: "rectangle", label: "Canvas", active: compactPane == .canvas) {
                    Haptics.selection()
                    compactPane = .canvas
                }
                dockButton(icon: "square.stack.3d.up", label: "Layers", active: compactPane == .layers) {
                    Haptics.selection()
                    compactPane = .layers
                }
                dockButton(icon: "slider.horizontal.3", label: "Inspector", active: false) {
                    Haptics.selection()
                    inspectorSheetOpen = true
                }
            }
        }
    }

    private func dockButton(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(BodyFont.system(size: 12.5, wght: 600))
            }
            .foregroundColor(active ? Palette.textPrimary : Color(white: 0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCapsule()
        }
        .buttonStyle(.plain)
    }

    private func canvasContainer(document: EditorDocument, template: TemplateManifest, html: String) -> some View {
        let dims = template.aspect.size
        return ZStack {
            Color.black.opacity(0.85)
            CanvasHost(
                html: html,
                baseURL: store.documentDir(for: document.id),
                selectedSlotId: selectedSlotId,
                box: webViewRef
            ) { message in
                handle(message: message)
            }
            .padding(20)
            .aspectRatio(CGFloat(dims.width / dims.height), contentMode: .fit)
        }
    }

    private func inspectorBlock(document: EditorDocument, template: TemplateManifest, style: StyleManifest) -> some View {
        EditorInspector(
            document: Binding(
                get: { draft ?? document },
                set: { draft = $0; scheduleSave() }
            ),
            template: template,
            style: style,
            selectedSlotId: selectedSlotId,
            availableStyles: design.styles,
            resolveAssetURL: { asset in store.assetURL(for: document, value: asset) }
        ) { slotId in
            Haptics.selection()
            assetSlotId = slotId
        } onCommit: {
            scheduleSave()
        }
    }

    // MARK: - Top bar

    private func topBar(document: EditorDocument, template: TemplateManifest) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                flushPendingSave()
                onClose()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                    Text("Done")
                        .font(BodyFont.system(size: 13, wght: 600))
                }
                .foregroundColor(Color(white: 0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassCapsule()
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(document.name)
                    .font(BodyFont.system(size: 15, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(template.name) · \(template.aspect.displayLabel)")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                ForEach(EditorExport.Format.allCases) { format in
                    Button("Export \(format.label)") {
                        Haptics.tap()
                        export(format: format)
                    }
                }
                Divider()
                Button("Delete draft", role: .destructive) {
                    Haptics.warning()
                    pendingDelete = true
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(white: 0.92))
                    .frame(width: 38, height: 38)
                    .glassCircle()
            }
            .disabled(isExporting)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func statusBanner(_ text: String) -> some View {
        bannerRow(text: text, icon: "checkmark.circle.fill", tint: Color(red: 0.40, green: 0.85, blue: 0.55)) {
            exportMessage = nil
        }
    }

    private func errorBanner(_ text: String) -> some View {
        bannerRow(text: text, icon: "exclamationmark.triangle.fill", tint: Color(red: 0.95, green: 0.45, blue: 0.45)) {
            saveError = nil
        }
    }

    private func bannerRow(text: String, icon: String, tint: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
            Text(text)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(2)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.65))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tint.opacity(0.30), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Wiring

    private var photosPresentation: Binding<Bool> {
        Binding(
            get: { assetSlotId != nil && photoPickerItem == nil },
            set: { if !$0 { assetSlotId = nil } }
        )
    }

    private var currentDocument: EditorDocument? {
        draft ?? store.document(id: documentId)
    }

    private func renderHTML(document: EditorDocument, template: TemplateManifest, style: StyleManifest) -> String {
        let options = RendererHTML.Options(includeEditorHarness: true) { slotId in
            guard let asset = document.data[slotId]?.asAsset else { return nil }
            return store.assetURL(for: document, value: asset)
        }
        return RendererHTML.render(document: document, template: template, style: style, options: options)
    }

    private func handle(message: EditorCanvasMessage) {
        switch message {
        case .click(let id, _):
            selectedSlotId = id
            if hSize != .regular { compactPane = .inspector }
        case .hover:
            break
        case .edit(let id, let text):
            guard var doc = draft ?? store.document(id: documentId) else { return }
            doc.data[id] = text.isEmpty ? .empty : .text(text)
            draft = doc
            scheduleSave()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let work = DispatchWorkItem { [self] in flushPendingSave() }
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

    private func ingestPhoto(item: PhotosPickerItem, slotId: String) async {
        defer { photoPickerItem = nil; assetSlotId = nil }
        guard var doc = draft ?? store.document(id: documentId) else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let asset = try store.storeAssetData(data, ext: "png", into: doc, slotId: slotId)
            doc.data[slotId] = .asset(asset)
            draft = doc
            flushPendingSave()
        } catch {
            saveError = "Could not attach photo: \(error.localizedDescription)"
        }
    }

    private func performDelete() {
        guard let doc = currentDocument else { return }
        do {
            try store.delete(doc)
            onClose()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func fallbackStyle() -> StyleManifest {
        DesignBuiltins.styles().first { $0.id == "claw" } ?? DesignBuiltins.styles()[0]
    }

    // MARK: - Export

    private func export(format: EditorExport.Format) {
        guard let doc = currentDocument else { return }
        guard let template = design.template(id: doc.templateId) else { return }
        let style = design.style(id: doc.styleId) ?? design.styles.first ?? fallbackStyle()
        let cleanOptions = RendererHTML.Options(includeEditorHarness: false) { slotId in
            guard let asset = doc.data[slotId]?.asAsset else { return nil }
            return store.assetURL(for: doc, value: asset)
        }
        let html = RendererHTML.render(document: doc, template: template, style: style, options: cleanOptions)
        let dims = template.aspect.size
        let url = EditorExport.tempURL(format: format, suggestedName: doc.name)
        switch format {
        case .html:
            do {
                try EditorExport.writeHTML(html, to: url)
                exportMessage = "Sharing HTML…"
                sharePayload = SharePayload(url: url)
            } catch { saveError = error.localizedDescription }
        case .svg:
            do {
                try EditorExport.writeSVG(html: html, width: dims.width, height: dims.height, to: url)
                exportMessage = "Sharing SVG…"
                sharePayload = SharePayload(url: url)
            } catch { saveError = error.localizedDescription }
        case .png:
            guard let webView = webViewRef.webView else { saveError = "Canvas not ready yet."; return }
            isExporting = true
            EditorExport.writePNG(webView: webView, to: url) { result in
                Task { @MainActor in
                    isExporting = false
                    switch result {
                    case .success: exportMessage = "Sharing PNG…"; sharePayload = SharePayload(url: url)
                    case .failure(let err): saveError = err.localizedDescription
                    }
                }
            }
        case .pdf:
            guard let webView = webViewRef.webView else { saveError = "Canvas not ready yet."; return }
            isExporting = true
            EditorExport.writePDF(webView: webView, to: url) { result in
                Task { @MainActor in
                    isExporting = false
                    switch result {
                    case .success: exportMessage = "Sharing PDF…"; sharePayload = SharePayload(url: url)
                    case .failure(let err): saveError = err.localizedDescription
                    }
                }
            }
        }
    }

    private var notFound: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(white: 0.45))
            Text("Editor document not found")
                .font(BodyFont.system(size: 15, wght: 500))
                .foregroundColor(Color(white: 0.70))
            Button("Close", action: onClose)
                .buttonStyle(.plain)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }
}

// MARK: - Canvas host

private struct CanvasHost: UIViewRepresentable {
    let html: String
    let baseURL: URL
    let selectedSlotId: String?
    let box: EditorView.WebViewBox
    var onMessage: (EditorCanvasMessage) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let bridge = HostBridge(onMessage: onMessage)
        controller.add(bridge, name: "clawixEditor")
        config.userContentController = controller
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.bounces = false
        view.scrollView.showsVerticalScrollIndicator = false
        view.scrollView.showsHorizontalScrollIndicator = false
        view.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.bridge = bridge
        context.coordinator.lastHTML = html
        DispatchQueue.main.async { self.box.webView = view }
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
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
                onMessage(.click(id: id, kind: payload["kind"] as? String))
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
