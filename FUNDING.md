# Funding

This document describes how the Clawix and ClawJS project sustains itself
in practice. It is a sibling of `CONSTITUTION.md`, not a part of it. The
constitution declares the red lines (no paywalls inside the app, no
lock-in, no data leaving the device, no data loss); this document explains
what remains within those limits.

The constitution is intentionally silent on business model (see "Scope and
non-goals"). This file documents the present plan; it can evolve without
amending the constitution, as long as the red lines stay intact.

## Principles

1. **The upstream stays free, forever.** The codebase under our ownership
   keeps the open-source license, the absence of paywalls inside the app,
   and the absence of paywalls against user data. None of this is
   contingent on revenue.

2. **The user pays for inference, not for the app.** Per principle II.7,
   the cost of running agents (model calls, hosted endpoints, paid APIs)
   is the user's, paid through credentials the user owns. Bring-your-own
   key is canonical.

3. **Hosted services are opt-in and complementary, never required.** Any
   service the project may host (managed inference, mesh relay, off-device
   scheduled execution) is one option among many, alongside self-hosted
   and third-party-hosted alternatives. The constitution's VIII.7 keeps a
   self-hosted path on every layer.

4. **Forks may monetize; we do not police them.** Our license permits any
   third party to fork and commercialize. The constitution binds upstream;
   it does not constrain downstream. The user's recourse against any
   downstream paywall is to return to the upstream.

## Present sources of sustenance

This is the current plan. It will change as the project evolves. Update
this section, not the constitution, when the plan changes.

- Maintainer time funded by the maintainer's own work and savings.
- Donations are accepted but not solicited as a primary funding model.
- Optional, opt-in hosted services may be added as the project grows; each
  one ships with a self-hosted equivalent.
- Enterprise support, training, and custom adapters may be offered
  separately, never as a precondition to using the project.

## What we do not do

These are constitutional red lines, restated here for clarity:

- We do not place any feature, integration, or data behind a paywall
  inside the app.
- We do not gate the user's own data behind any subscription, tier, or
  payment.
- We do not lock the user into any specific provider of inference,
  storage, or transport.
- We do not collect telemetry to fund the project, sell, or trade.

If a sustainable path forward would require crossing any of these, we
abandon the path, not the red lines.
