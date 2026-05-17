# UI Pattern Notes

These notes are the short human-readable companion to the machine-readable
pattern manifests. They do not approve a surface as visually frozen; approval
still requires the protected-surface flow.

## sidebar-section

Groups sidebar rows under a compact heading or disclosure affordance. Keep the
section contract tied to the surrounding sidebar rhythm, not to an isolated
card-like block.

## sidebar-row

Represents a single actionable sidebar entry. Row height, icon bounds, label
baseline, selected state, hover treatment, and disclosure behavior are part of
the pattern contract.

## thin-scroller

Covers the narrow custom scrollbar treatment used by dense panes. Thickness,
track contrast, hover visibility, and parent clipping must be checked together.

## dropdown-menu

Used for compact command and selection menus. The arrow, row height, hover,
focus, disabled, and selected states must stay consistent even when width
varies with content.

## icon-chip-button

Small icon-led action control. Icon bounds, hit target, hover/pressed treatment,
and tooltip/copy ownership are governed together.

## composer-chrome

Input area around message composition. The pattern includes attachment affordance
placement, send-state behavior, typing latency, and error/loading states.

## sliding-segmented

Segment switcher with animated selection. Segment sizing may adapt to labels,
but height, indicator motion, focus, and selected contrast stay canonical.

## settings-surface

Dense configuration surface. The pattern governs hierarchy, grouping, form row
alignment, controls, and non-marketing copy style.

## design-surface

Surfaces used for design or visual configuration work. They must expose controls
without inventing new chrome outside the registry.

## chat-surface

Primary conversation surface. It governs scroll behavior, message density,
status affordances, loading/error states, and perceived latency expectations.

## sheet-chrome

Modal or sheet container treatment. Header, close action, footer actions,
keyboard focus, and overflow behavior are part of the pattern.

## toast

Transient feedback surface. Copy, severity, timing, focus safety, and stacking
rules are part of the contract.

## search-field

Search input chrome. Icon placement, clear action, focus treatment, busy state,
and empty/error text are governed together.

## terminal-surface

Terminal-like agent output or process pane. The pattern owns density, scroll,
font choice, selection behavior, and switching latency constraints.

## right-sidebar-surface

Agent side panels, browser/tool sidebars, and right-adjacent support panes. The
pattern owns panel state, browser/tool affordance copy, focus handoff, and the
right-sidebar/browser critical-flow budget.

## entity-card

Repeated entity summary block. Use only when a card is genuinely a repeated
item; page sections must not become nested decorative cards.
