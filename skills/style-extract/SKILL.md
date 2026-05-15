---
name: style-extract
description: Inspect a reference (web URL, image, PDF, screenshot) and propose a candidate Style for the workspace. Use when the user says "save this style", "guarda este estilo", or shares a reference and wants to reapply it later.
keywords: [style, design, brand, extract, palette, tokens, reference]
---

# style-extract

Take an external reference (a URL, an image, a PDF) and turn it into a candidate `Style` in the workspace under `.claw/styles/<id>/STYLE.md`.

## Inputs

- A reference source, one of:
  - HTTP(S) URL of a webpage
  - Local image path (JPG/PNG)
  - Local PDF path
- Optional name for the style. Otherwise derive from the source.

## Procedure

1. If the source is a local file, register it as a Reference first:
   ```
   claw ref add --type <image|pdf> --source <path> --name "<source name>"
   ```
   If the source is a URL, register it as a `web` reference:
   ```
   claw ref add --type web --source <url> --name "<page title>"
   ```
2. Analyse the reference visually:
   - Extract the dominant palette (4-8 colors). Pick the most saturated as `accent`, the darkest as `fg`, the lightest as `bg`, neutral as `surface`.
   - Identify dominant typography. Treat headline font as `display`, body font as `body`. If unsure, default to `Inter, Arial, sans-serif`.
   - Note any motion or interaction patterns visible (transitions, hover, scroll behavior).
3. Build a Style manifest by starting from the closest builtin (`claw style builtins`) and adjusting tokens. Use `claw style create` to scaffold:
   ```
   claw style create "<Name>" --from <closest-builtin> --description "Extracted from <source>"
   ```
4. Edit the generated `STYLE.md` to set the extracted palette and fonts, and to write a short `## Voice` section if the reference has copy.
5. Link the reference back to the style:
   ```
   claw ref link <referenceId> --style <styleId>
   ```
6. Report back to the user: the style id, what was extracted, and any uncertainty so they can refine.

## Constraints

- Never invent logo files. Leave `brand.logos` empty if not provided.
- Color extraction must use the actual reference, not a guessed palette. If the image cannot be loaded, fail clearly.
- The candidate Style is editable. The user is expected to refine it after the first pass.
