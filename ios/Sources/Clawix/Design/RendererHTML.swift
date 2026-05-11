import Foundation

/// Swift mirror of the ClawJS HTML renderer. Produces a self-contained
/// HTML document for one `(Template, Style, data)` triplet, embedding
/// the style tokens as CSS variables and emitting each slot with
/// `data-slot-id` + `data-slot-kind` so the WKWebView bridge can map a
/// click back to the matching slot.
enum RendererHTML {
    struct Options {
        var includeEditorHarness: Bool = false
        var assetURLForSlot: (String) -> URL? = { _ in nil }
    }

    static func render(document: EditorDocument, template: TemplateManifest, style: StyleManifest, options: Options = Options()) -> String {
        let dims = aspectDimensions(template.aspect)
        let varsCSS = buildCSSVariables(style: style)
        let slotsHTML = template.slots.map { slot in renderSlot(slot: slot, document: document, style: style, options: options) }.joined(separator: "\n")
        let bodyClass = options.includeEditorHarness ? "editor" : "preview"
        let baseCSS = baseStyles(width: dims.width, height: dims.height)
        let harnessJS = options.includeEditorHarness ? Self.harnessJS : ""
        let body = """
<div class="frame" style="width:\(dims.width)px;height:\(dims.height)px">
  <div class="content">
\(slotsHTML)
  </div>
</div>
"""
        return """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=\(dims.width)">
  <style>:root{\(varsCSS)}\(baseCSS)</style>
</head>
<body class="\(bodyClass)">
\(body)
\(harnessJS)
</body>
</html>
"""
    }

    // MARK: - CSS

    private static func buildCSSVariables(style: StyleManifest) -> String {
        var lines: [String] = []
        let c = style.tokens.color
        let colors: [(String, String?)] = [
            ("--color-bg", c.bg), ("--color-surface", c.surface), ("--color-surface-2", c.surface2),
            ("--color-fg", c.fg), ("--color-fg-muted", c.fgMuted),
            ("--color-accent", c.accent), ("--color-accent-2", c.accent2),
            ("--color-success", c.success), ("--color-warn", c.warn), ("--color-danger", c.danger),
            ("--color-border", c.border), ("--color-overlay", c.overlay),
        ]
        for (name, value) in colors {
            if let value { lines.append("\(name):\(value)") }
        }
        for (name, value) in c.extras { lines.append("--color-\(name):\(value)") }
        let t = style.tokens.typography
        lines.append("--font-display:\(t.display.family)")
        lines.append("--font-body:\(t.body.family)")
        lines.append("--font-mono:\(t.mono.family)")
        let scaleMap: [(String, Double)] = [
            ("xs", t.scale.xs), ("sm", t.scale.sm), ("md", t.scale.md),
            ("lg", t.scale.lg), ("xl", t.scale.xl),
            ("2xl", t.scale.xl2), ("3xl", t.scale.xl3),
        ]
        for (key, value) in scaleMap {
            lines.append("--font-size-\(key):\(Int(value))px")
        }
        for (key, value) in style.tokens.spacing.scale {
            lines.append("--space-\(key):\(Int(value))px")
        }
        let r = style.tokens.radius
        lines.append("--radius-sm:\(Int(r.sm))px")
        lines.append("--radius-md:\(Int(r.md))px")
        lines.append("--radius-lg:\(Int(r.lg))px")
        lines.append("--radius-xl:\(Int(r.xl))px")
        lines.append("--radius-squircle:\(Int(r.squircle ?? r.lg))px")
        return lines.joined(separator: ";")
    }

    private static func baseStyles(width: Double, height: Double) -> String {
        return """
*{box-sizing:border-box;margin:0;padding:0}
html,body{font-family:var(--font-body);color:var(--color-fg);background:#111;}
body{display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px;-webkit-user-select:none;user-select:none;}
body.editor [data-slot-id]{outline:1px solid transparent;outline-offset:2px;transition:outline-color 90ms ease-out;border-radius:4px;cursor:pointer;}
body.editor [data-slot-id]:hover{outline-color:rgba(87,199,255,0.55);}
body.editor [data-slot-id].is-selected{outline:2px solid #57c7ff;outline-offset:2px;}
.frame{position:relative;background:var(--color-surface);border-radius:var(--radius-lg);overflow:hidden;border:1px solid var(--color-border,transparent);display:flex;flex-direction:column;box-shadow:0 36px 80px rgba(0,0,0,0.45);}
.content{flex:1;display:flex;flex-direction:column;gap:var(--space-4,16px);padding:var(--space-12,48px);}
.heading{font-family:var(--font-display);font-size:var(--font-size-2xl);line-height:1.05;letter-spacing:-0.02em;color:var(--color-fg);}
.subheading{font-family:var(--font-display);font-size:var(--font-size-lg);line-height:1.2;color:var(--color-fg-muted,var(--color-fg));}
.body{font-family:var(--font-body);font-size:var(--font-size-md);line-height:1.5;color:var(--color-fg);white-space:pre-wrap;}
.list{font-family:var(--font-body);font-size:var(--font-size-md);line-height:1.6;color:var(--color-fg);padding-left:var(--space-5,20px);}
.list li{margin-bottom:var(--space-2,8px);}
.quote{font-family:var(--font-display);font-size:var(--font-size-xl);line-height:1.3;color:var(--color-accent);font-style:italic;border-left:3px solid var(--color-accent);padding-left:var(--space-4,16px);white-space:pre-wrap;}
.metric{font-family:var(--font-display);font-size:var(--font-size-3xl);line-height:1.0;color:var(--color-accent);letter-spacing:-0.02em;}
.button{display:inline-block;padding:var(--space-3,12px) var(--space-5,20px);background:var(--color-accent);color:var(--color-bg);font-family:var(--font-body);font-size:var(--font-size-md);border-radius:var(--radius-squircle);text-decoration:none;align-self:flex-start;}
.image{background:var(--color-surface-2,var(--color-surface));border-radius:var(--radius-md);min-height:160px;display:flex;align-items:center;justify-content:center;color:var(--color-fg-muted);font-family:var(--font-mono);font-size:var(--font-size-xs);overflow:hidden;border:1px dashed rgba(255,255,255,0.10);}
.image img{width:100%;height:100%;object-fit:cover;border-radius:var(--radius-md);}
.logo{font-family:var(--font-display);font-size:var(--font-size-md);font-weight:700;color:var(--color-fg);letter-spacing:-0.01em;display:inline-flex;align-items:center;gap:8px;}
.logo img{max-height:36px;width:auto;}
.divider{height:1px;background:var(--color-border,var(--color-fg-muted));opacity:0.3;}
.shape{background:var(--color-accent);border-radius:var(--radius-md);min-height:40px;}
.table{font-family:var(--font-body);font-size:var(--font-size-sm);width:100%;border-collapse:collapse;}
.table th,.table td{text-align:left;padding:var(--space-2,8px) var(--space-3,12px);border-bottom:1px solid var(--color-border,var(--color-fg-muted));}
.slot-empty{color:var(--color-fg-muted,var(--color-fg));opacity:0.4;font-style:italic;}
"""
    }

    // MARK: - Slots

    private static func renderSlot(slot: TemplateSlot, document: EditorDocument, style: StyleManifest, options: Options) -> String {
        let value = document.data[slot.id] ?? .empty
        let attrs = "data-slot-id=\"\(escAttr(slot.id))\" data-slot-kind=\"\(slot.kind.rawValue)\""
        switch slot.kind {
        case .heading:
            return "<h1 class=\"heading\" \(attrs)>\(renderText(value, slot: slot))</h1>"
        case .subheading:
            return "<h2 class=\"subheading\" \(attrs)>\(renderText(value, slot: slot))</h2>"
        case .body:
            return "<p class=\"body\" \(attrs)>\(renderText(value, slot: slot))</p>"
        case .quote:
            return "<blockquote class=\"quote\" \(attrs)>\(renderText(value, slot: slot))</blockquote>"
        case .metric:
            return "<div class=\"metric\" \(attrs)>\(renderText(value, slot: slot, emptyPlaceholder: "—"))</div>"
        case .button:
            let label = value.asText ?? slot.label
            return "<a class=\"button\" href=\"#\" \(attrs)>\(escMultiline(label))</a>"
        case .image:
            if let asset = value.asAsset, let url = options.assetURLForSlot(slot.id) {
                return "<div class=\"image\" \(attrs)><img src=\"\(url.absoluteString)\" alt=\"\(escAttr(slot.label))\" data-asset=\"\(escAttr(asset.filename))\"/></div>"
            }
            return "<div class=\"image\" \(attrs)>\(escMultiline(slot.label))</div>"
        case .logo:
            if let url = options.assetURLForSlot(slot.id) {
                return "<div class=\"logo\" \(attrs)><img src=\"\(url.absoluteString)\" alt=\"logo\"/></div>"
            }
            return "<div class=\"logo\" \(attrs)>\(escMultiline(style.name))</div>"
        case .divider:
            return "<div class=\"divider\" \(attrs)></div>"
        case .shape:
            return "<div class=\"shape\" \(attrs)></div>"
        case .list:
            let items = value.asItems ?? []
            if items.isEmpty {
                return "<ul class=\"list\" \(attrs)><li class=\"slot-empty\">[\(escMultiline(slot.label))]</li></ul>"
            }
            let li = items.map { "<li>\(escMultiline($0))</li>" }.joined()
            return "<ul class=\"list\" \(attrs)>\(li)</ul>"
        case .table:
            let text = value.asText ?? ""
            let rows = text.split(separator: "\n").map { row in
                row.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
            }
            if rows.isEmpty {
                return "<div class=\"slot-empty\" \(attrs)>[\(escMultiline(slot.label))]</div>"
            }
            let head = rows.first!.map { "<th>\(escMultiline($0))</th>" }.joined()
            let body = rows.dropFirst().map { row in
                "<tr>" + row.map { "<td>\(escMultiline($0))</td>" }.joined() + "</tr>"
            }.joined()
            return "<table class=\"table\" \(attrs)><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table>"
        }
    }

    private static func renderText(_ value: SlotValue, slot: TemplateSlot, emptyPlaceholder: String? = nil) -> String {
        if let text = value.asText, !text.isEmpty {
            return escMultiline(text)
        }
        let placeholder = emptyPlaceholder ?? "[\(slot.label)]"
        return "<span class=\"slot-empty\">\(escMultiline(placeholder))</span>"
    }

    // MARK: - Aspect

    private static func aspectDimensions(_ aspect: TemplateAspect) -> (width: Double, height: Double) {
        let size = aspect.size
        return (width: size.width, height: size.height)
    }

    // MARK: - Escaping

    private static func escAttr(_ value: String) -> String { esc(value) }

    private static func esc(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escMultiline(_ value: String) -> String {
        esc(value).replacingOccurrences(of: "\n", with: "<br>")
    }

    // MARK: - Harness

    /// JS script injected into the canvas when the editor is in author
    /// mode. Posts three messages to the host:
    ///   - `{type:"slot.click", id, kind, rect}` on click
    ///   - `{type:"slot.hover", id}` on hover (debounced)
    ///   - `{type:"slot.edit", id, text}` after an inline contenteditable
    ///     commit (Enter or blur)
    private static let harnessJS: String = """
<script>
(function(){
  const post = (payload) => {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.clawixEditor) {
      window.webkit.messageHandlers.clawixEditor.postMessage(payload);
    }
  };
  let lastHover = null;
  document.addEventListener('mousemove', (e) => {
    const slot = e.target.closest('[data-slot-id]');
    const id = slot ? slot.getAttribute('data-slot-id') : null;
    if (id !== lastHover) {
      lastHover = id;
      post({ type: 'slot.hover', id: id });
    }
  });
  document.addEventListener('click', (e) => {
    const slot = e.target.closest('[data-slot-id]');
    if (!slot) return;
    document.querySelectorAll('[data-slot-id].is-selected').forEach((el) => el.classList.remove('is-selected'));
    slot.classList.add('is-selected');
    const rect = slot.getBoundingClientRect();
    post({
      type: 'slot.click',
      id: slot.getAttribute('data-slot-id'),
      kind: slot.getAttribute('data-slot-kind'),
      rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
    });
  });
  document.addEventListener('dblclick', (e) => {
    const slot = e.target.closest('[data-slot-id]');
    if (!slot) return;
    const kind = slot.getAttribute('data-slot-kind');
    if (kind === 'heading' || kind === 'subheading' || kind === 'body' || kind === 'quote' || kind === 'button' || kind === 'metric') {
      slot.setAttribute('contenteditable', 'true');
      slot.focus();
      const range = document.createRange();
      range.selectNodeContents(slot);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
      const commit = () => {
        const text = slot.innerText || '';
        slot.removeAttribute('contenteditable');
        slot.removeEventListener('blur', commit);
        slot.removeEventListener('keydown', enterCommit);
        post({ type: 'slot.edit', id: slot.getAttribute('data-slot-id'), text: text });
      };
      const enterCommit = (ev) => {
        if (ev.key === 'Enter' && !ev.shiftKey) { ev.preventDefault(); slot.blur(); }
        if (ev.key === 'Escape') { slot.blur(); }
      };
      slot.addEventListener('blur', commit);
      slot.addEventListener('keydown', enterCommit);
    }
  });
  window.clawixSelectSlot = (id) => {
    document.querySelectorAll('[data-slot-id].is-selected').forEach((el) => el.classList.remove('is-selected'));
    if (id) {
      const el = document.querySelector('[data-slot-id="' + CSS.escape(id) + '"]');
      if (el) el.classList.add('is-selected');
    }
  };
})();
</script>
"""
}
