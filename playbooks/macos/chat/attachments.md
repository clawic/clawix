---
id: macos.chat.attachments
platform: macos
surface: chat
status: ready
intent: "Validate visual attachment staging, preview, removal, drag-and-drop, and send behavior for composer files and images."
entrypoints:
  - plus-menu-add
  - drag-to-window
  - drag-to-composer
  - bridge-attachment
variants:
  - single-image
  - single-file
  - multiple-files
  - attachment-only-send
  - text-plus-attachment-send
  - remove-before-send
  - image-preview-open-close
required_state:
  app_mode: dummy
  data: synthetic public fixture files only
  backend: fake or intercepted for send
  window: main macOS app window visible and focused
safety:
  default: isolated
  requires_explicit_confirmation:
    - attaching private user files
    - uploading files to a real backend
    - sending files to a paid model
  forbidden_without_confirmation:
    - dragging files from user private folders
execution_mode:
  hermetic: required for fixture-backed staging and fake send
  host: required for real drag-and-drop, file picker behavior, and image preview rendering
artifacts:
  - staged attachment screenshot
  - image preview screenshot
  - sent user bubble screenshot
assertions:
  - attachment chip or preview is visible after staging
  - send enables for attachment-only drafts
  - removing an attachment updates send enablement correctly
  - sent user bubble shows the attachment representation
known_risks:
  - file picker access depends on host permissions
  - image decoding differs by file type
  - drag-and-drop cannot be fully validated without host mode
---

## Goal

Verify that users can add, inspect, remove, and send attachments through every supported macOS interaction path without leaking private files or sending to real services by default.

## Invariants

- Only synthetic fixture files are used by default.
- Staged attachments must be visible before send.
- Attachment-only drafts must enable send.
- Removing the last attachment from an empty draft must disable send.
- Sent messages must preserve a visible representation of the attachment.
- Image previews must open and close without changing the underlying message.

## Setup

- Prepare one small fixture image and one small fixture text or markdown file.
- Launch in dummy mode with fake backend responses.
- Keep the main window focused.
- Do not use files from user documents, screenshots, downloads, or source folders unless explicitly requested.

## Entry Points

- Open the plus menu and choose an attachment action.
- Drag a fixture file onto the app window.
- Drag a fixture file directly onto the composer.
- Receive a fixture attachment through a bridge-originated message.

## Variant Matrix

| Dimension | Variants |
| --- | --- |
| Source | plus menu, drag to window, drag to composer, bridge |
| File kind | image, text-like file, multiple mixed files |
| Draft | attachment only, text plus attachment, remove before send |
| Preview | thumbnail only, full preview overlay, close preview |
| Runtime | fake send, host drag-and-drop, real send only with confirmation |

## Steps

1. Open a new-chat composer.
2. Add a fixture image through the plus menu.
3. Confirm a thumbnail or chip appears.
4. Confirm send is enabled even with no text.
5. Open the image preview and close it.
6. Send through the fake backend.
7. Confirm the resulting user bubble shows the attachment.

Alternate passes:

1. Drag a fixture file onto the app window and confirm the drop overlay or staged chip appears.
2. Drag a fixture file directly onto the composer and confirm it stages in the same place.
3. Add multiple fixture files and confirm each can be seen or removed.
4. Remove all staged attachments from an empty draft and confirm send disables.
5. Add text plus an attachment and confirm both appear after send.

## Expected Results

- Attachment UI appears immediately after staging.
- Image thumbnails render without dark or blank placeholders.
- Full image preview opens over the app and can be dismissed.
- Attachment chips do not overlap composer controls.
- Fake send clears staged attachments.
- The transcript shows the attachment in the user message.

## Failure Signals

- File stages invisibly.
- Send remains disabled for an attachment-only draft.
- Removed attachments still send.
- Preview opens blank or cannot close.
- Dragging into the window has no visible response in host mode.
- A private file is used without explicit confirmation.

## Screenshot Checklist

- Attachment staged in composer.
- Multiple attachments staged.
- Image preview overlay.
- User bubble after attachment send.
- Empty draft after removing last attachment.

## Notes for Future Automation

- Use small deterministic fixtures checked into test resources only if the runner needs persistent fixtures.
- Future automation should capture drag-and-drop separately from plus-menu selection because drag behavior is host-dependent.
- Bridge attachment coverage needs a fixture frame with file and image metadata.
