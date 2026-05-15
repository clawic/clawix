---
name: canvas-design
description: Apply the 90/10 visual-to-text rule when composing a piece on a canvas (poster, card, social post). Use when the deliverable lives on a single fixed surface where each element competes for attention.
keywords: [canvas, layout, poster, card, social, composition, hierarchy]
---

# canvas-design

A canvas piece (one fixed-aspect surface that the viewer takes in at a glance) succeeds when one element dominates. The 90/10 rule:

- **90% of the canvas is the protagonist**: a strong headline, a single image, a quote. One element only.
- **10% supports**: attribution, date, logo, CTA, micro-copy.

## Procedure

1. Identify the protagonist. Ask: "if the viewer reads nothing else, what must they see?"
2. Pick a Template whose dominant slot matches that intent:
   - Poster announcement: `poster.announcement` (heading dominant) or `poster.event` (hero image dominant).
   - Quote piece: `poster.quote` or `social-post.square-quote`.
   - Product showcase: `social-post.square-product` or `flyer.event`.
3. Reduce supporting copy. Use the maxLength of supporting slots aggressively; if your text exceeds, cut.
4. Pick a Style whose `accent` is bold enough to anchor the protagonist. For dim backgrounds use `midnight` or `signal`; for warm pieces use `warm` or `editorial`.
5. Render PNG + PDF + SVG to give the user format choices.

## Anti-patterns

- Three competing headlines on one canvas. Pick one.
- Dense paragraphs of body copy on a poster. If it reads like a paragraph, it belongs in a one-pager or brochure, not a canvas piece.
- Logo larger than the headline. Logo lives in the 10%.
- Stock-photo backgrounds with text on top without a scrim. Either use a clean background, or add a `shape` slot behind the text to create contrast.

## Constraints

- Never use more than 2 distinct accent colors in a single canvas.
- Maintain at least 4.5:1 contrast between text and its immediate background.
- Respect platform safe zones: for `9:16` story posts, keep critical content inside the middle 80% vertically.
