---
name: template-render
description: Render a Template + data + Style into a final artifact in one of HTML, PDF, PNG, SVG or PPTX. Use whenever the user asks for a concrete deliverable like "make me a poster", "render a card", "give me a one-pager".
keywords: [render, template, output, pdf, png, svg, pptx, deliverable]
---

# template-render

The standard recipe for producing a deliverable from a Template and a Style.

## Procedure

1. Pick a Template:
   - If the user names a category ("a poster", "a card"), list candidates: `claw template list --category <cat>`.
   - If they describe a use-case, match by tags or name.
2. Pick a Style:
   - If they reference a brand or saved style, use that.
   - Otherwise default to the workspace's primary Style (often the first non-builtin or `claw`).
3. Compose data:
   - Read the template's slots from `claw template get <id>`.
   - For each slot, write a JSON field with `id` as the key.
   - Respect `maxLength`, `maxItems`, `required`.
4. Render:
   ```
   claw template render <templateId> --style <styleId> --data data.json --format pdf,png --out ./deliverable
   ```
5. Report back: the paths produced and a sentence describing what is in each.

## Formats

| Format | Renderer | Notes |
|---|---|---|
| html | direct | Canonical, fastest, no deps. |
| svg | wraps html in `<foreignObject>` | Use for scalable vector. |
| pdf | Playwright (Chromium) | Falls back to a minimal Node PDF if Playwright is unavailable. |
| png | Playwright (Chromium) | 2x deviceScaleFactor. |
| pptx | OpenXML (Node only) | Minimal one-slide PPTX. Best for `presentation` category. |

## Constraints

- Never hard-code style values into the data. The Style is the source of truth for color and typography.
- If the template declares `outputs` and the requested format is not in the list, fail with a clear error.
- Generated outputs go under `.claw/templates/<templateId>/outputs/` unless `--out` is specified.
