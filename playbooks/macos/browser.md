---
id: macos.browser
platform: macos
surface: browser
status: ready
priority: P1
tags:
  - regression
  - dummy
  - host
  - browser
  - navigation
intent: "Validate embedded browser navigation, tab controls, URL focus, screenshots, permission blocking, and safe local-page behavior."
entrypoints:
  - browser-route
  - command-menu
  - link-preview
  - new-browser-tab
variants:
  - blank-tab
  - local-url
  - blocked-external-url
  - reload
  - back-forward
  - close-tab
  - page-screenshot
required_state:
  app_mode: dummy
  data: local or blank browser page
  backend: no external network required
  window: browser route visible in the main macOS app window
safety:
  level: safe_dummy
  default: local or blank pages only
  requires_explicit_confirmation:
    - external web navigation
    - authenticated site access
    - screenshotting private pages
execution_mode:
  hermetic: required for browser chrome and blank/local route
  host: required for WKWebView rendering, screenshots, and real permission prompts
artifacts:
  - browser chrome screenshot
  - local page screenshot
  - permission or blocked-state screenshot
assertions:
  - browser route renders nonblank chrome
  - URL or tab state is visible
  - local navigation does not require external network
  - external or authenticated navigation is blocked without confirmation
known_risks:
  - WKWebView may load asynchronously
  - network state can make external pages flaky
  - page screenshots can capture private content
---

## Goal

Verify the embedded browser as a local, controllable app surface while preventing unapproved external navigation or private-page capture.

## Invariants

- Browser chrome must render before page assertions.
- Blank and local pages are the default validation target.
- External navigation requires confirmation.
- Screenshot actions must target only safe local/fixture content.

## Setup

- Launch in dummy mode.
- Open the browser route.
- Use `about:blank` or a local fixture URL.
- Disable or avoid real authenticated sessions.

## Entry Points

- Navigate to the browser route.
- Use browser menu commands.
- Open a link preview from a fixture chat.
- Create a new browser tab.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Page | blank, local URL, blocked external URL |
| Tab | new, close, switch |
| Navigation | reload, back, forward, URL focus |
| Capture | safe page screenshot, blocked private screenshot |
| Permission | no prompt, blocked prompt, explicit host check |

## Critical Cases

- `P1-browser-chrome`: browser route renders controls and blank page.
- `P1-local-navigation`: local URL loads without external network.
- `P1-external-block`: external navigation is not performed without confirmation.
- `P2-page-screenshot`: safe local page screenshot captures only the intended page.

## Steps

1. Open the browser route.
2. Confirm browser chrome and a blank or local page are visible.
3. Focus the URL field and enter a local URL.
4. Confirm loading state resolves to local content.
5. Exercise reload, new tab, close tab, and back/forward where available.
6. Attempt an external URL only as a blocked/no-run case unless confirmed.

## Expected Results

- Browser route is nonblank and controls are readable.
- Local page loads without external services.
- Tab controls update visible state.
- External or authenticated navigation remains blocked by default.

## Failure Signals

- Browser route renders blank chrome or blank page indefinitely.
- URL focus cannot be reached.
- Tab close leaves broken selection.
- External page opens without confirmation.
- Screenshot captures more than the browser window or safe page content.

## Evidence Checklist

| Check | Result |
| --- | --- |
| Browser chrome rendered | pass/fail/no-run |
| Local or blank page rendered | pass/fail/no-run |
| Tab/navigation controls checked | pass/fail/no-run |
| External navigation blocked or confirmed | pass/fail/no-run |
| Screenshot safety checked | pass/fail/no-run |

## Screenshot Checklist

- Blank browser route.
- Local URL rendered.
- Tab or URL focus state.
- Blocked external navigation state.
- Safe page screenshot result when applicable.

## Notes for Future Automation

- Treat browser chrome and page content as separate assertions.
- Prefer local fixture pages over remote URLs.
- Host validation should use window-only screenshots.
