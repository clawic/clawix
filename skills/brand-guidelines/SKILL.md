---
name: brand-guidelines
description: Given an existing Style, generate a human-readable brand guidelines document covering colors, typography, voice, do/don't, imagery rules, and usage examples. Use when the user asks for a brand book, brand guide, or design system document.
keywords: [brand, guidelines, brand-book, documentation, style-guide]
---

# brand-guidelines

Produce a readable brand guidelines artifact from a Style. The artifact is itself rendered via a Template + Style application, not free-form prose.

## Procedure

1. Read the Style: `claw style get <styleId>`.
2. Choose the rendering shape:
   - For a one-pager (single page brand summary) use `one-pager.product` or `one-pager.profile`.
   - For a long-form brand book, generate sections per area (colors, typography, voice, imagery, usage) and concatenate.
3. Build the data:
   - Colors: list named tokens with hex values.
   - Typography: list stacks (display, body, mono) and the size scale.
   - Voice: copy the `## Voice` section from STYLE.md verbatim.
   - Do/Don't: copy the `## Do / Don't` section verbatim. If empty, do not invent.
   - Imagery: copy `imagery.photography`, `imagery.illustration`, `imagery.iconography` if set, plus the `generation_prompt_suffix`.
4. Render `pdf` + `html` outputs using the same Style being documented (so the doc looks like the brand).
5. Surface a clear summary: where the doc was written and what sections were covered.

## Constraints

- Never invent rules the Style does not declare. Empty sections must remain empty.
- The brand book is generated, not authored by hand. Re-running it is idempotent given the same Style state.
- Use the Style being documented as both the source AND the rendering style for the artifact.
