---
name: theme-factory
description: Produce variants of an existing Style by shifting tone (light/dark), density (compact/relaxed), or accent (palette rotation) while preserving the brand identity. Use when the user wants alternate themes derived from one brand.
keywords: [theme, variants, palette, factory, light, dark, density]
---

# theme-factory

Algorithmic generation of related Styles from one source Style. Produces new Styles that share `brand` and `voice` but differ in tone or density.

## Recipes

- **Light / Dark inversion**: swap `bg` and `fg`. Adjust `surface` and `surface-2` to keep contrast. Recompute `fg-muted` and `border` to be perceptually consistent.
- **Density**: tighten or relax `spacing.scale` by a factor (0.8 for compact, 1.25 for relaxed). Adjust typography `scale` proportionally.
- **Accent rotation**: keep all tokens, swap `accent` and `accent-2` for a complementary or analogous pair from the same hue family.
- **Editorial / Display**: keep colors, swap `typography.display.family` between a serif and a sans of similar weight.

## Procedure

1. Read the source Style: `claw style get <sourceId>`.
2. Decide the recipe based on the user's intent.
3. Build the variant Style by starting from the source and overlaying the recipe's deltas. Use:
   ```
   claw style create "<Source name> · Dark" --from <sourceId>
   ```
4. Apply the deltas to STYLE.md.
5. Render a preview using a Template the source already has examples in.
6. Report: the new style id and the deltas applied.

## Constraints

- Never change `brand.voice`, `brand.do_dont`, or `brand.taglines`. Identity is shared across variants.
- Each variant is a new Style, not a mutation of the source.
- Mention exact contrast ratios when producing a light/dark variant so the user can verify accessibility.
