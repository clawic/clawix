# Telegram Integration QA Lab Scenario

Status: ACTIVE

Boundary: Clawix host approval, Telegram Bot API, ClawJS connector runtime

## Purpose

Track Telegram live validation from the Clawix side without moving connector
truth out of ClawJS. Clawix may request approvals and show state; the official
API matrix and connector harness remain framework-owned.

## Required Evidence

- ClawJS Telegram official API matrix and hermetic package tests.
- Signed-host approval path for any live credential lease.
- Explicit operator approval for public webhook, payment, destructive,
  uploaded-asset, phone/account-role, game, Passport, or managed-bot-token
  checks.
- Confirmation that Clawix did not read, print, store, or pass a raw Telegram
  bot token through UI code.

## Expected Result

Clawix reports Telegram as validated only for rows that have corresponding
framework evidence. Missing live prerequisites are `EXTERNAL PENDING`.
Hermetic framework coverage counts as local contract validation, not proof that
a live Telegram bot/account flow has passed.
