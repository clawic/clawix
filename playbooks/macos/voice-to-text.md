---
id: macos.voice-to-text
platform: macos
surface: settings
status: ready
priority: P1
tags:
  - regression
  - dummy
  - host
  - voice
  - settings
intent: "Validate Voice to Text setup, permissions, recording states, transcription preferences, vocabulary, replacements, prompt editing, and safe fixture-backed dictation behavior."
entrypoints:
  - settings-voice-to-text
  - composer-mic-button
  - global-hotkey
  - onboarding-card
variants:
  - permissions-not-determined
  - permissions-granted
  - language-auto
  - forced-language
  - filler-removal
  - vocabulary-term
  - replacement-rule
  - prompt-editing
  - recorder-style
  - fixture-transcription
required_state:
  app_mode: dummy
  data: fixture transcription text and public vocabulary examples
  backend: fixture transcription or intercepted cloud providers
  window: main macOS app window visible and focused
safety:
  level: host_local
  default: isolated fixture transcription
  requires_explicit_confirmation:
    - real microphone permission changes
    - real cloud transcription provider call
    - recording private user speech
execution_mode:
  hermetic: required for fixture transcription and settings state
  host: required for TCC permissions, global hotkey, and real overlay placement
artifacts:
  - Voice to Text settings screenshot
  - composer recording state screenshot
  - transcribing or resulting draft screenshot
assertions:
  - permission state is explicit
  - language/model/replacement controls visibly update
  - fixture transcription reaches the target text surface
  - no real cloud or microphone path runs without confirmation
known_risks:
  - macOS TCC state varies by machine
  - hotkeys require host focus and permissions
  - cloud provider state must be intercepted by default
---

## Goal

Verify that Voice to Text can be configured and visually exercised with fixture transcription while clearly separating hermetic UI coverage from real host permission coverage.

## Invariants

- The settings page must show permission state, language, model, cleanup, vocabulary, replacements, prompt, and recorder options.
- Fixture transcription must not use a real microphone or cloud provider.
- Permission prompts, real recordings, and provider calls require explicit confirmation.
- Recording, transcribing, and final text states must be visually distinct.

## Setup

- Launch in dummy mode.
- Use fixture transcription text.
- Open Settings -> Voice to Text and an isolated composer.
- Do not grant, revoke, or request real permissions unless the task is host validation.

## Entry Points

- Open Voice to Text from Settings.
- Click the composer microphone button.
- Use the global hotkey in host mode.
- Open the onboarding or setup card when permissions are incomplete.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Permission | not determined, denied, granted |
| Input source | composer mic, global hotkey, fixture runner |
| Language | auto, explicit locale |
| Cleanup | filler removal on/off, replacement rule, vocabulary term |
| Provider | local fixture, local model, cloud provider blocked without confirmation |

## Critical Cases

- `P1-settings-state`: settings controls render and update visibly.
- `P1-fixture-transcription`: fixture text lands in the composer without real audio.
- `P1-permission-clarity`: permission state is visible and not misleading.
- `P2-host-hotkey`: host mode confirms overlay placement and hotkey routing.

## Steps

1. Open Voice to Text settings.
2. Confirm permission state and setup guidance are visible.
3. Change language and cleanup controls; confirm visible state changes.
4. Add a public vocabulary term or replacement rule and verify it appears.
5. Start fixture-backed recording from the composer.
6. Confirm recording state appears, then transcribing state, then final draft text.
7. Verify no real provider call or microphone capture occurred.

## Expected Results

- Settings state is readable and persistent within the isolated run.
- Recording UI replaces normal composer controls intentionally.
- Fixture transcription appears in the composer or target text surface.
- Host-only paths are clearly marked as no-run unless explicitly validated.

## Failure Signals

- Permission state is blank or contradictory.
- A real microphone or cloud provider is used without confirmation.
- Recording or transcribing state gets stuck.
- Fixture text does not reach the target surface.
- Replacement or vocabulary UI saves invisibly.

## Evidence Checklist

| Check | Result |
| --- | --- |
| Settings state checked | pass/fail/no-run |
| Fixture transcription checked | pass/fail/no-run |
| Permission path classified hermetic vs host | pass/fail/no-run |
| No real audio/provider use confirmed | pass/fail/no-run |
| Required screenshots captured | pass/fail/no-run |

## Screenshot Checklist

- Voice to Text settings page.
- Permission/setup state.
- Recording toolbar or overlay.
- Transcribing state.
- Final composer draft after fixture transcription.

## Notes for Future Automation

- Prefer fixture transcription environment controls over real audio.
- Host hotkey checks should run separately from settings-only checks.
- Do not assert exact permission text across macOS versions; assert visible state and action availability.
