---
name: style-apply
description: Apply a Style to any artifact in the workspace (presentation, card, poster, social post, web page). Use when the user says "apply style X", "render this with style X", or wants to reuse a saved style on a new piece.
keywords: [style, apply, render, template, brand]
---

# style-apply

Take an existing Style (`.claw/styles/<id>/`) and apply it to a Template instance, producing one or more outputs.

## Inputs

- `styleId`: id of an existing Style. List with `claw style list`.
- `templateId`: id of an existing Template. List with `claw template list [--category <cat>]`.
- `variantId`: optional, defaults to the template's first variant.
- `data`: a JSON file with values for the template's slots.
- `format`: one or more of `html`, `pdf`, `png`, `svg`, `pptx`. Defaults to `html`.

## Procedure

1. Confirm both resources exist:
   ```
   claw style get <styleId>
   claw template get <templateId>
   ```
2. Compose the `data.json` for the template's slots. For each slot the template declares:
   - `kind`: `heading`, `subheading`, `body`, `list`, `quote`, `metric`, `image`, `logo`, `button`, `divider`, `shape`, `table`.
   - `required`: whether to fail if missing.
   - `maxLength` / `maxItems`: respect these or surface a warning.
3. Render:
   ```
   claw template render <templateId> --style <styleId> --data data.json --format <fmt> --out <path>
   ```
4. Register the output as a generated example under the style for future "more like this" requests.

## Constraints

- Never edit the Style as a side effect of applying it. Applying is a read on the Style.
- If a slot is required and missing, fail with a clear error pointing at the slot id.
- Multiple formats can be produced in one call: `--format pdf,png,html`.
