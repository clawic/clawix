import Foundation

/// Compile-time seed for the 10 built-in Styles and 30 built-in Templates
/// that ship with Clawix's Design surface. On first launch the
/// `DesignStore` writes these to disk so the user always opens the
/// surface to a populated catalog instead of an empty grid.
///
/// The seed mirrors what `claw style|template install-builtins` writes
/// from the framework side. As long as the schema matches both surfaces
/// converge on the same set; the ClawJS pin only needs to bump when the
/// schema itself evolves.
enum DesignBuiltins {
    static let seededAt: String = "2026-05-11T00:00:00Z"

    // MARK: - Styles

    static func styles() -> [StyleManifest] {
        styleSeeds.map { seed in
            StyleManifest(
                schemaVersion: 1,
                id: seed.id,
                name: seed.name,
                description: seed.description,
                tags: seed.tags,
                tokens: tokens(for: seed),
                brand: StyleBrand(
                    voice: "Tone for the \(seed.name) style. Capture how copy reads in this voice.",
                    doDont: "- Do: keep copy aligned with the \(seed.name) mood.\n- Don't: introduce conflicting visual cues outside this style."
                ),
                imagery: StyleImagery(
                    generationPromptSuffix: defaultImagerySuffix(seed)
                ),
                overrides: [:],
                references: [],
                examples: [],
                createdAt: seededAt,
                updatedAt: seededAt,
                builtin: true
            )
        }
    }

    private struct StyleSeed {
        let id: String
        let name: String
        let description: String
        let tags: [String]
        let bg: String
        let surface: String
        let panel: String
        let fg: String
        let fgMuted: String
        let accent: String
        let accent2: String
        let border: String
        let display: String
        let body: String
        let mono: String
    }

    private static let styleSeeds: [StyleSeed] = [
        StyleSeed(id: "editorial", name: "Editorial",
                  description: "Serif-led editorial theme. Warm paper background, deep ink foreground.",
                  tags: ["builtin", "editorial", "print"],
                  bg: "#f5f0e8", surface: "#fffaf2", panel: "#fffaf2",
                  fg: "#151719", fgMuted: "#6d655d",
                  accent: "#b9412f", accent2: "#244f7a", border: "#e1d8c8",
                  display: "Georgia, 'Times New Roman', serif",
                  body: "Georgia, 'Times New Roman', serif",
                  mono: "'SFMono-Regular', Consolas, monospace"),
        StyleSeed(id: "studio", name: "Studio",
                  description: "Bright neutral background with teal accent. Balanced sans for product decks.",
                  tags: ["builtin", "studio", "product"],
                  bg: "#f8f7f3", surface: "#ffffff", panel: "#ffffff",
                  fg: "#1d2328", fgMuted: "#65717b",
                  accent: "#0f8b8d", accent2: "#f25f5c", border: "#e6e3dc",
                  display: "Inter, Arial, sans-serif",
                  body: "Inter, Arial, sans-serif",
                  mono: "'SFMono-Regular', Consolas, monospace"),
        StyleSeed(id: "midnight", name: "Midnight",
                  description: "Deep navy backdrop with luminous accent. Reads well in dim rooms.",
                  tags: ["builtin", "dark", "presentation"],
                  bg: "#09111f", surface: "#111f33", panel: "#111f33",
                  fg: "#f6f8fb", fgMuted: "#a9b7c8",
                  accent: "#57c7ff", accent2: "#a78bfa", border: "#1d2d49",
                  display: "Inter, Arial, sans-serif",
                  body: "Inter, Arial, sans-serif",
                  mono: "'SFMono-Regular', Consolas, monospace"),
        StyleSeed(id: "signal", name: "Signal",
                  description: "Forest-toned dark theme. Green/amber accents for data dashboards.",
                  tags: ["builtin", "dark", "data"],
                  bg: "#0e1512", surface: "#17231d", panel: "#17231d",
                  fg: "#f3f8f1", fgMuted: "#a8b8ad",
                  accent: "#59d98e", accent2: "#ffd166", border: "#1b2e25",
                  display: "Aptos, Arial, sans-serif",
                  body: "Aptos, Arial, sans-serif",
                  mono: "'SFMono-Regular', Consolas, monospace"),
        StyleSeed(id: "paper", name: "Paper",
                  description: "Cool paper background, blue/orange accents. Friendly for documentation.",
                  tags: ["builtin", "paper", "docs"],
                  bg: "#fbfaf7", surface: "#f0eee8", panel: "#f0eee8",
                  fg: "#202124", fgMuted: "#6f6f68",
                  accent: "#3867d6", accent2: "#e15f41", border: "#e1ddd1",
                  display: "Aptos, Arial, sans-serif",
                  body: "Aptos, Arial, sans-serif",
                  mono: "'SFMono-Regular', Consolas, monospace"),
        StyleSeed(id: "executive", name: "Executive",
                  description: "Conservative business theme. Navy + ochre on cool white.",
                  tags: ["builtin", "business", "report"],
                  bg: "#f6f7f9", surface: "#ffffff", panel: "#ffffff",
                  fg: "#111827", fgMuted: "#5f6b7a",
                  accent: "#1f4e79", accent2: "#9a6a19", border: "#dfe3ea",
                  display: "Arial, sans-serif",
                  body: "Arial, sans-serif",
                  mono: "'SFMono-Regular', Consolas, monospace"),
        StyleSeed(id: "product", name: "Product",
                  description: "Cool product launch theme. Teal + blue accents, heavy whitespace.",
                  tags: ["builtin", "product", "launch"],
                  bg: "#f7fbff", surface: "#ffffff", panel: "#ffffff",
                  fg: "#112033", fgMuted: "#617084",
                  accent: "#0d9488", accent2: "#2563eb", border: "#dde7f0",
                  display: "Inter, Arial, sans-serif",
                  body: "Inter, Arial, sans-serif",
                  mono: "'SFMono-Regular', Consolas, monospace"),
        StyleSeed(id: "mono", name: "Mono",
                  description: "Monospace throughout. Stark grayscale for code-heavy artifacts.",
                  tags: ["builtin", "mono", "technical"],
                  bg: "#f4f4f2", surface: "#ffffff", panel: "#ffffff",
                  fg: "#171717", fgMuted: "#686868",
                  accent: "#111111", accent2: "#777777", border: "#e0e0de",
                  display: "'SFMono-Regular', Consolas, monospace",
                  body: "'SFMono-Regular', Consolas, monospace",
                  mono: "'SFMono-Regular', Consolas, monospace"),
        StyleSeed(id: "warm", name: "Warm",
                  description: "Warm cream background with terracotta and teal. Community-friendly.",
                  tags: ["builtin", "warm", "brand"],
                  bg: "#fff7ed", surface: "#fffbf4", panel: "#fffbf4",
                  fg: "#241a14", fgMuted: "#7c6254",
                  accent: "#c2410c", accent2: "#0f766e", border: "#f0e3d2",
                  display: "Aptos, Arial, sans-serif",
                  body: "Aptos, Arial, sans-serif",
                  mono: "'SFMono-Regular', Consolas, monospace"),
        StyleSeed(id: "claw", name: "Claw",
                  description: "Default Claw house style. Teal anchor with cool secondary.",
                  tags: ["builtin", "claw", "house"],
                  bg: "#f7f7f4", surface: "#ffffff", panel: "#ffffff",
                  fg: "#141a1f", fgMuted: "#62707d",
                  accent: "#15a3a3", accent2: "#315c9c", border: "#e1e2dd",
                  display: "'Source Sans 3', Arial, sans-serif",
                  body: "'Source Sans 3', Arial, sans-serif",
                  mono: "'Ubuntu Mono', 'SFMono-Regular', monospace"),
    ]

    private static func tokens(for seed: StyleSeed) -> StyleTokens {
        StyleTokens(
            color: StyleColorTokens(
                bg: seed.bg,
                surface: seed.surface,
                surface2: seed.panel,
                fg: seed.fg,
                fgMuted: seed.fgMuted,
                accent: seed.accent,
                accent2: seed.accent2,
                success: "#16a34a",
                warn: "#eab308",
                danger: "#dc2626",
                border: seed.border,
                overlay: "#0000004D"
            ),
            typography: StyleTypographyTokens(
                display: StyleTypographyStack(family: seed.display, source: "system"),
                body: StyleTypographyStack(family: seed.body, source: "system"),
                mono: StyleTypographyStack(family: seed.mono, source: "system"),
                scale: StyleTypographyScale(xs: 12, sm: 14, md: 16, lg: 20, xl: 28, xl2: 40, xl3: 56)
            ),
            spacing: StyleSpacingTokens(unit: 4, scale: [
                "0": 0, "1": 4, "2": 8, "3": 12, "4": 16, "5": 20, "6": 24,
                "8": 32, "10": 40, "12": 48, "16": 64, "20": 80, "24": 96
            ]),
            radius: StyleRadiusTokens(none: 0, sm: 4, md: 8, lg: 12, xl: 20, full: 9999, squircle: 16),
            shadow: StyleShadowTokens(
                sm: StyleShadowToken(offsetX: 0, offsetY: 1, blur: 2, color: "\(seed.fg)1A"),
                md: StyleShadowToken(offsetX: 0, offsetY: 4, blur: 12, color: "\(seed.fg)26"),
                lg: StyleShadowToken(offsetX: 0, offsetY: 10, blur: 28, color: "\(seed.fg)33")
            ),
            motion: StyleMotionTokens(
                curves: [
                    "ease-out-cubic": "cubic-bezier(0.215, 0.61, 0.355, 1)",
                    "ease-in-out":    "cubic-bezier(0.65, 0, 0.35, 1)",
                    "ease-out-back":  "cubic-bezier(0.34, 1.56, 0.64, 1)",
                    "linear":         "linear"
                ],
                durations: ["xs": 120, "sm": 180, "md": 240, "lg": 320, "xl": 480]
            )
        )
    }

    private static func defaultImagerySuffix(_ seed: StyleSeed) -> String {
        let palette = "palette \(seed.accent), \(seed.accent2), \(seed.bg)"
        if seed.tags.contains("dark")       { return "\(palette); cinematic, low-key lighting, deep shadows" }
        if seed.tags.contains("editorial")  { return "\(palette); editorial photography, soft natural light, paper texture" }
        if seed.tags.contains("product")    { return "\(palette); clean studio backdrop, soft directional light, product render" }
        if seed.tags.contains("mono")       { return "\(palette); high-contrast monochrome, grain texture" }
        if seed.tags.contains("warm")       { return "\(palette); warm afternoon sunlight, golden hour, cozy ambience" }
        return "\(palette); balanced studio light, neutral background"
    }

    // MARK: - Templates

    static func templates() -> [TemplateManifest] {
        templateSeeds.map { seed in
            TemplateManifest(
                schemaVersion: 1,
                id: seed.id,
                name: seed.name,
                category: seed.category,
                aspect: seed.aspect,
                description: seed.description,
                tags: seed.tags + ["builtin"],
                slots: seed.slots,
                variants: [
                    TemplateVariant(id: "default", label: "Default"),
                    TemplateVariant(id: "alt", label: "Alternate")
                ],
                outputs: seed.outputs,
                defaultStyleId: nil,
                builtin: true,
                createdAt: seededAt,
                updatedAt: seededAt
            )
        }
    }

    private struct TemplateSeed {
        let id: String
        let name: String
        let category: TemplateCategory
        let aspect: TemplateAspect
        let description: String
        let tags: [String]
        let slots: [TemplateSlot]
        let outputs: [String]
    }

    private static func heading(_ id: String = "heading", _ label: String = "Heading", max: Int = 88) -> TemplateSlot {
        TemplateSlot(id: id, kind: .heading, label: label, required: true, maxLength: max)
    }
    private static func subheading(_ id: String = "subheading", _ label: String = "Subheading", max: Int = 170) -> TemplateSlot {
        TemplateSlot(id: id, kind: .subheading, label: label, maxLength: max)
    }
    private static func body(_ id: String = "body", _ label: String = "Body", max: Int = 520) -> TemplateSlot {
        TemplateSlot(id: id, kind: .body, label: label, multiline: true, maxLength: max)
    }
    private static func list(_ id: String = "bullets", _ label: String = "Bullets", maxItems: Int = 6, max: Int = 105) -> TemplateSlot {
        TemplateSlot(id: id, kind: .list, label: label, maxLength: max, maxItems: maxItems)
    }
    private static func image(_ id: String = "image", _ label: String = "Image") -> TemplateSlot {
        TemplateSlot(id: id, kind: .image, label: label)
    }
    private static func logo(_ id: String = "logo", _ label: String = "Logo") -> TemplateSlot {
        TemplateSlot(id: id, kind: .logo, label: label)
    }
    private static func button(_ id: String = "cta", _ label: String = "Call to action", max: Int = 24) -> TemplateSlot {
        TemplateSlot(id: id, kind: .button, label: label, maxLength: max)
    }
    private static func metric(_ id: String, _ label: String) -> TemplateSlot {
        TemplateSlot(id: id, kind: .metric, label: label, maxLength: 72)
    }
    private static func table(_ id: String, _ label: String) -> TemplateSlot {
        TemplateSlot(id: id, kind: .table, label: label)
    }
    private static func quote(_ id: String = "quote", _ label: String = "Quote", max: Int = 340) -> TemplateSlot {
        TemplateSlot(id: id, kind: .quote, label: label, required: true, multiline: true, maxLength: max)
    }
    private static func text(_ id: String, _ label: String, kind: TemplateSlotKind = .body, max: Int = 120) -> TemplateSlot {
        TemplateSlot(id: id, kind: kind, label: label, maxLength: max)
    }

    private static let templateSeeds: [TemplateSeed] = [
        // Presentation (6)
        TemplateSeed(id: "presentation.title-only", name: "Presentation · Title",
                     category: .presentation, aspect: .named("16:9"),
                     description: "Opening slide with title, subtitle and presenter line.",
                     tags: ["presentation", "opening"],
                     slots: [heading("title", "Title"), subheading("subtitle", "Subtitle"), text("presenter", "Presenter", max: 80), logo()],
                     outputs: ["html", "pdf", "png", "pptx"]),
        TemplateSeed(id: "presentation.agenda", name: "Presentation · Agenda",
                     category: .presentation, aspect: .named("16:9"),
                     description: "Agenda slide with numbered list of sections.",
                     tags: ["presentation", "agenda"],
                     slots: [heading("title", "Title", max: 58), list("items", "Agenda items", maxItems: 8, max: 80)],
                     outputs: ["html", "pdf", "png", "pptx"]),
        TemplateSeed(id: "presentation.content", name: "Presentation · Content",
                     category: .presentation, aspect: .named("16:9"),
                     description: "Heading with bullets and supporting body copy.",
                     tags: ["presentation"],
                     slots: [heading(), subheading(), list(), body()],
                     outputs: ["html", "pdf", "png", "pptx"]),
        TemplateSeed(id: "presentation.comparison", name: "Presentation · Comparison",
                     category: .presentation, aspect: .named("16:9"),
                     description: "Two-column comparison with title.",
                     tags: ["presentation", "compare"],
                     slots: [
                        heading("title", "Title"),
                        text("left_title", "Left column title", kind: .subheading, max: 60),
                        text("left_body",  "Left column body", max: 400),
                        text("right_title","Right column title", kind: .subheading, max: 60),
                        text("right_body", "Right column body", max: 400),
                     ],
                     outputs: ["html", "pdf", "png", "pptx"]),
        TemplateSeed(id: "presentation.metric-grid", name: "Presentation · Metric grid",
                     category: .presentation, aspect: .named("16:9"),
                     description: "Title plus 3-4 highlighted metrics.",
                     tags: ["presentation", "metric"],
                     slots: [
                        heading("title", "Title"),
                        metric("m1_value", "Metric 1 value"), metric("m1_label", "Metric 1 label"),
                        metric("m2_value", "Metric 2 value"), metric("m2_label", "Metric 2 label"),
                        metric("m3_value", "Metric 3 value"), metric("m3_label", "Metric 3 label"),
                        metric("m4_value", "Metric 4 value"), metric("m4_label", "Metric 4 label"),
                     ],
                     outputs: ["html", "pdf", "png", "pptx"]),
        TemplateSeed(id: "presentation.closing", name: "Presentation · Closing",
                     category: .presentation, aspect: .named("16:9"),
                     description: "Final slide with thank-you message and contact.",
                     tags: ["presentation", "closing"],
                     slots: [heading("title", "Title"), subheading("subtitle", "Subtitle"), text("contact", "Contact", max: 120)],
                     outputs: ["html", "pdf", "png", "pptx"]),

        // Cards (4)
        TemplateSeed(id: "card.birthday", name: "Card · Birthday",
                     category: .card, aspect: .named("1:1"),
                     description: "Square birthday card with greeting and name.",
                     tags: ["card", "birthday"],
                     slots: [heading("greeting", "Greeting", max: 30), text("recipient", "Recipient name", kind: .subheading, max: 40), body("message", "Message", max: 240), image()],
                     outputs: ["html", "pdf", "png", "svg"]),
        TemplateSeed(id: "card.thank-you", name: "Card · Thank you",
                     category: .card, aspect: .named("1:1"),
                     description: "Thank-you note with sender and recipient.",
                     tags: ["card", "thanks"],
                     slots: [heading("greeting", "Greeting", max: 30), body("message", "Message", max: 320), text("signer", "Signed by", max: 60)],
                     outputs: ["html", "pdf", "png", "svg"]),
        TemplateSeed(id: "card.invitation", name: "Card · Invitation",
                     category: .card, aspect: .named("1:1"),
                     description: "Event invitation with date, place and dress code.",
                     tags: ["card", "invitation"],
                     slots: [heading("title", "Event title", max: 60), subheading("subtitle", "Subtitle", max: 90), text("date", "Date / time", max: 60), text("place", "Place", max: 120), button("rsvp", "RSVP label")],
                     outputs: ["html", "pdf", "png", "svg"]),
        TemplateSeed(id: "card.gift", name: "Card · Gift",
                     category: .card, aspect: .named("1:1"),
                     description: "Gift card with code and amount.",
                     tags: ["card", "gift"],
                     slots: [heading("title", "Title", max: 32), metric("amount", "Amount"), text("code", "Code", max: 32), body("terms", "Terms", max: 180)],
                     outputs: ["html", "pdf", "png", "svg"]),

        // Posters (3)
        TemplateSeed(id: "poster.event", name: "Poster · Event",
                     category: .poster, aspect: .named("a4-portrait"),
                     description: "Event poster with hero image, headline, date/place.",
                     tags: ["poster", "event"],
                     slots: [heading("title", "Title"), subheading("subtitle", "Subtitle"), text("date", "Date / time", max: 60), text("place", "Place", max: 120), image("hero", "Hero image"), logo()],
                     outputs: ["html", "pdf", "png", "svg"]),
        TemplateSeed(id: "poster.quote", name: "Poster · Quote",
                     category: .poster, aspect: .named("a4-portrait"),
                     description: "Quote poster with attribution.",
                     tags: ["poster", "quote"],
                     slots: [quote(), text("attribution", "Attribution", max: 60)],
                     outputs: ["html", "pdf", "png", "svg"]),
        TemplateSeed(id: "poster.announcement", name: "Poster · Announcement",
                     category: .poster, aspect: .named("a4-portrait"),
                     description: "Announcement poster with strong headline and body.",
                     tags: ["poster", "announcement"],
                     slots: [heading(), body()],
                     outputs: ["html", "pdf", "png", "svg"]),

        // Social post (5)
        TemplateSeed(id: "social-post.square-quote", name: "Social · Square quote",
                     category: .socialPost, aspect: .named("1:1"),
                     description: "Square quote post with attribution and logo.",
                     tags: ["social", "quote"],
                     slots: [quote("quote", "Quote", max: 220), text("attribution", "Attribution", max: 60), logo()],
                     outputs: ["html", "pdf", "png", "svg"]),
        TemplateSeed(id: "social-post.story-quote", name: "Social · Story quote",
                     category: .socialPost, aspect: .named("9:16"),
                     description: "Vertical story quote with safe zones for UI overlays.",
                     tags: ["social", "story"],
                     slots: [quote("quote", "Quote", max: 180), text("attribution", "Attribution", max: 60)],
                     outputs: ["html", "pdf", "png", "svg"]),
        TemplateSeed(id: "social-post.square-product", name: "Social · Square product",
                     category: .socialPost, aspect: .named("1:1"),
                     description: "Product showcase with headline, image and CTA.",
                     tags: ["social", "product"],
                     slots: [heading("title", "Title", max: 60), image(), text("price", "Price line", max: 30), button()],
                     outputs: ["html", "pdf", "png", "svg"]),
        TemplateSeed(id: "social-post.story-product", name: "Social · Story product",
                     category: .socialPost, aspect: .named("9:16"),
                     description: "Vertical product story.",
                     tags: ["social", "story", "product"],
                     slots: [heading("title", "Title", max: 50), image(), text("price", "Price line", max: 30), button("swipe", "Swipe label")],
                     outputs: ["html", "pdf", "png", "svg"]),
        TemplateSeed(id: "social-post.carousel-3up", name: "Social · Carousel 3-up",
                     category: .socialPost, aspect: .named("4:5"),
                     description: "Three-card carousel piece for portrait posts.",
                     tags: ["social", "carousel"],
                     slots: [heading("title", "Title"), body("card1", "Card 1", max: 220), body("card2", "Card 2", max: 220), body("card3", "Card 3", max: 220)],
                     outputs: ["html", "pdf", "png", "svg"]),

        // One-pager (2)
        TemplateSeed(id: "one-pager.product", name: "One-pager · Product",
                     category: .onePager, aspect: .named("a4-portrait"),
                     description: "Product one-pager with hero, three benefits and CTA.",
                     tags: ["one-pager", "product"],
                     slots: [logo(), heading("title", "Headline", max: 80), subheading("subtitle", "Subhead", max: 160), image("hero", "Hero image"), list("benefits", "Benefits", maxItems: 5, max: 120), button()],
                     outputs: ["html", "pdf", "png"]),
        TemplateSeed(id: "one-pager.profile", name: "One-pager · Profile",
                     category: .onePager, aspect: .named("a4-portrait"),
                     description: "Person profile one-pager.",
                     tags: ["one-pager", "profile"],
                     slots: [image("portrait", "Portrait"), heading("name", "Name", max: 40), subheading("role", "Role", max: 80), body("bio", "Bio", max: 500), list("highlights", "Highlights", maxItems: 4, max: 100)],
                     outputs: ["html", "pdf", "png"]),

        // CV (2)
        TemplateSeed(id: "cv.executive", name: "CV · Executive",
                     category: .cv, aspect: .named("a4-portrait"),
                     description: "Executive-style CV with experience timeline.",
                     tags: ["cv", "executive"],
                     slots: [heading("name", "Name", max: 60), subheading("title", "Title", max: 80), text("contact", "Contact", max: 200), body("summary", "Summary", max: 400), list("experience", "Experience entries", maxItems: 8, max: 220), list("education", "Education entries", maxItems: 4, max: 120)],
                     outputs: ["html", "pdf"]),
        TemplateSeed(id: "cv.minimal", name: "CV · Minimal",
                     category: .cv, aspect: .named("a4-portrait"),
                     description: "Minimal one-page CV.",
                     tags: ["cv", "minimal"],
                     slots: [heading("name", "Name", max: 60), subheading("title", "Title", max: 80), text("contact", "Contact", max: 200), list("experience", "Experience entries", maxItems: 5, max: 200), list("skills", "Skills", maxItems: 8, max: 60)],
                     outputs: ["html", "pdf"]),

        // Single-instance categories
        TemplateSeed(id: "invoice.standard", name: "Invoice · Standard",
                     category: .invoice, aspect: .named("a4-portrait"),
                     description: "Standard invoice with line items, totals and bank info.",
                     tags: ["invoice"],
                     slots: [logo(), heading("title", "Title", max: 40), text("issuer", "Issuer block", max: 240), text("client", "Client block", max: 240), text("number", "Invoice number", max: 40), text("date", "Issue date", max: 40), text("due", "Due date", max: 40), table("items", "Line items"), metric("total", "Total"), body("notes", "Notes", max: 320)],
                     outputs: ["html", "pdf"]),
        TemplateSeed(id: "certificate.award", name: "Certificate · Award",
                     category: .certificate, aspect: .named("a4-landscape"),
                     description: "Award certificate with recipient and reason.",
                     tags: ["certificate"],
                     slots: [logo(), heading("title", "Title", max: 60), text("recipient", "Recipient", kind: .subheading, max: 80), body("reason", "Reason / citation", max: 320), text("issuer", "Issuer", max: 80), text("date", "Date", max: 40)],
                     outputs: ["html", "pdf", "png"]),
        TemplateSeed(id: "menu.restaurant", name: "Menu · Restaurant",
                     category: .menu, aspect: .named("a4-portrait"),
                     description: "Restaurant menu with sections of dishes.",
                     tags: ["menu", "food"],
                     slots: [heading("title", "Title", max: 60), subheading("subtitle", "Subtitle", max: 120), table("starters", "Starters"), table("mains", "Mains"), table("desserts", "Desserts"), text("footer", "Footer note", max: 240)],
                     outputs: ["html", "pdf", "png"]),
        TemplateSeed(id: "flyer.event", name: "Flyer · Event",
                     category: .flyer, aspect: .named("a4-portrait"),
                     description: "Event flyer with hero, key details and CTA.",
                     tags: ["flyer", "event"],
                     slots: [image("hero", "Hero image"), heading("title", "Title", max: 60), subheading("subtitle", "Subtitle", max: 120), body("details", "Details", max: 320), button()],
                     outputs: ["html", "pdf", "png", "svg"]),

        // Email (2)
        TemplateSeed(id: "email.newsletter", name: "Email · Newsletter",
                     category: .email, aspect: .custom(width: 600, height: 1200, unit: "px"),
                     description: "Newsletter email with header, three story blocks and footer.",
                     tags: ["email", "newsletter"],
                     slots: [logo(), heading("title", "Title", max: 80), body("intro", "Intro", max: 400), text("story1_title", "Story 1 title", kind: .subheading, max: 80), body("story1_body", "Story 1 body", max: 320), text("story2_title", "Story 2 title", kind: .subheading, max: 80), body("story2_body", "Story 2 body", max: 320), text("story3_title", "Story 3 title", kind: .subheading, max: 80), body("story3_body", "Story 3 body", max: 320), button(), text("footer", "Footer", max: 320)],
                     outputs: ["html"]),
        TemplateSeed(id: "email.transactional", name: "Email · Transactional",
                     category: .email, aspect: .custom(width: 600, height: 800, unit: "px"),
                     description: "Transactional email with single primary action.",
                     tags: ["email", "transactional"],
                     slots: [logo(), heading("title", "Title", max: 80), body("body", "Body", max: 600), button("cta", "Primary CTA", max: 30), text("footer", "Footer", max: 240)],
                     outputs: ["html"]),

        // Business card (1)
        TemplateSeed(id: "business-card.standard", name: "Business card · Standard",
                     category: .businessCard, aspect: .custom(width: 85, height: 55, unit: "mm"),
                     description: "Standard 85x55mm business card.",
                     tags: ["business-card"],
                     slots: [logo(), heading("name", "Name", max: 40), text("title", "Title", kind: .subheading, max: 60), body("contact", "Contact lines", max: 160)],
                     outputs: ["html", "pdf", "png", "svg"]),

        // Web landing (1)
        TemplateSeed(id: "web-landing.product", name: "Web landing · Product",
                     category: .webLanding, aspect: .custom(width: 1280, height: 2400, unit: "px"),
                     description: "Long-scroll product landing with hero, features and CTA.",
                     tags: ["web", "landing"],
                     slots: [logo(), heading("hero_title", "Hero title", max: 80), subheading("hero_subtitle", "Hero subtitle", max: 200), button("hero_cta", "Hero CTA", max: 30), image("hero_image", "Hero image"), text("feature1_title", "Feature 1 title", kind: .subheading, max: 60), body("feature1_body", "Feature 1 body", max: 320), text("feature2_title", "Feature 2 title", kind: .subheading, max: 60), body("feature2_body", "Feature 2 body", max: 320), text("feature3_title", "Feature 3 title", kind: .subheading, max: 60), body("feature3_body", "Feature 3 body", max: 320), button("footer_cta", "Footer CTA", max: 30)],
                     outputs: ["html", "png"]),
    ]
}
