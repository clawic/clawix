import SwiftUI
import AppKit

struct ScreenToolsSettingsPage: View {
    @ObservedObject private var service = ScreenToolService.shared
    @ObservedObject private var macUtilities = MacUtilitiesController.shared

    @AppStorage(ScreenToolSettings.exportDirectoryKey) private var exportDirectory = ""
    @AppStorage(ScreenToolSettings.afterCaptureActionKey) private var afterCaptureAction = ScreenToolService.CaptureAction.quickOverlay.rawValue
    @AppStorage(ScreenToolSettings.imageFormatKey) private var imageFormat = ScreenToolService.ImageFormat.png.rawValue
    @AppStorage(ScreenToolSettings.selfTimerSecondsKey) private var selfTimerSeconds = 5
    @AppStorage(ScreenToolSettings.playSoundsKey) private var playSounds = true
    @AppStorage(ScreenToolSettings.includeCursorKey) private var includeCursor = false
    @AppStorage(ScreenToolSettings.captureWindowShadowKey) private var captureWindowShadow = true
    @AppStorage(ScreenToolSettings.showRecordingControlsKey) private var showRecordingControls = true
    @AppStorage(ScreenToolSettings.highlightRecordingClicksKey) private var highlightRecordingClicks = true
    @AppStorage(ScreenToolSettings.recordRecordingAudioKey) private var recordRecordingAudio = false
    @AppStorage(ScreenToolSettings.keepTextLineBreaksKey) private var keepTextLineBreaks = false
    @AppStorage(ScreenToolSettings.autoDetectTextLanguageKey) private var autoDetectTextLanguage = true

    private var actionBinding: Binding<ScreenToolService.CaptureAction> {
        Binding {
            ScreenToolService.CaptureAction(rawValue: afterCaptureAction) ?? .quickOverlay
        } set: {
            afterCaptureAction = $0.rawValue
        }
    }

    private var formatBinding: Binding<ScreenToolService.ImageFormat> {
        Binding {
            ScreenToolService.ImageFormat(rawValue: imageFormat) ?? .png
        } set: {
            imageFormat = $0.rawValue
        }
    }

    private var timerBinding: Binding<Int> {
        Binding {
            selfTimerSeconds == 0 ? 5 : selfTimerSeconds
        } set: {
            selfTimerSeconds = $0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Screen Tools",
                subtitle: "Capture, record, recognize text, pin references and manage local outputs."
            )

            SectionLabel(title: "Actions")
            SettingsCard {
                actionRow(
                    title: "All-In-One",
                    detail: "Open one menu with capture, recording, text, pin and history actions.",
                    symbol: "camera.viewfinder",
                    action: service.showAllInOneMenu
                )
                CardDivider()
                actionRow(
                    title: "Capture area",
                    detail: "Select a rectangular region and apply the default after-capture action.",
                    symbol: "crop",
                    action: service.captureArea
                )
                CardDivider()
                actionRow(
                    title: "Capture previous area",
                    detail: "Repeat the last selected area without selecting again.",
                    symbol: "rectangle.dashed",
                    action: service.capturePreviousArea
                )
                CardDivider()
                actionRow(
                    title: "Capture fullscreen",
                    detail: "Capture the active display directly.",
                    symbol: "rectangle.inset.filled",
                    action: service.captureFullscreen
                )
                CardDivider()
                actionRow(
                    title: "Capture window",
                    detail: "Pick one window and capture it.",
                    symbol: "macwindow",
                    action: service.captureWindow
                )
                CardDivider()
                actionRow(
                    title: "Scrolling capture",
                    detail: "Select an area, scroll it, and save a stitched local capture.",
                    symbol: "arrow.down.doc",
                    action: service.captureScrolling
                )
                CardDivider()
                actionRow(
                    title: "Self-timer",
                    detail: "Capture after the configured delay.",
                    symbol: "timer",
                    action: service.captureSelfTimer
                )
                CardDivider()
                actionRow(
                    title: "Record screen",
                    detail: "Open the system screen-recording selector and save a movie file locally.",
                    symbol: "record.circle",
                    action: service.recordScreen
                )
                CardDivider()
                actionRow(
                    title: "Capture text",
                    detail: "Select an area, recognize text on device, and copy it to the clipboard.",
                    symbol: "text.viewfinder",
                    action: { service.captureText(keepLineBreaks: keepTextLineBreaks) }
                )
                CardDivider()
                actionRow(
                    title: "Recognize last capture text",
                    detail: "Recognize text from the most recent local capture and copy it.",
                    symbol: "doc.text.viewfinder",
                    action: { service.recognizeLastCaptureText(keepLineBreaks: keepTextLineBreaks) }
                )
                CardDivider()
                actionRow(
                    title: "Hide desktop icons",
                    detail: "Toggle Finder desktop items for cleaner captures.",
                    symbol: "square.grid.3x3",
                    action: { macUtilities.perform(.toggleDesktopIcons) }
                )
            }

            SectionLabel(title: "Output")
            SettingsCard {
                SettingsRow {
                    RowLabel(title: "Export location", detail: currentExportLocation)
                } trailing: {
                    IconChipButton(symbol: "folder", label: "Choose…", action: chooseExportDirectory)
                }
                CardDivider()
                DropdownRow(
                    title: "After capture",
                    detail: "Default action for screenshot commands.",
                    options: ScreenToolService.CaptureAction.allCases.map { ($0, $0.title) },
                    selection: actionBinding,
                    minWidth: 230
                )
                CardDivider()
                DropdownRow(
                    title: "File format",
                    detail: "Image format used for local screenshots.",
                    options: ScreenToolService.ImageFormat.allCases.map { ($0, $0.title) },
                    selection: formatBinding,
                    minWidth: 120
                )
                CardDivider()
                DropdownRow(
                    title: "Self-timer interval",
                    detail: "Delay before timed fullscreen capture.",
                    options: [(3, "3 seconds"), (5, "5 seconds"), (10, "10 seconds")],
                    selection: timerBinding,
                    minWidth: 130
                )
                CardDivider()
                ToggleRow(title: "Play sounds", detail: "Use the system capture sound when available.", isOn: $playSounds)
            }

            SectionLabel(title: "Screenshot Options")
            SettingsCard {
                ToggleRow(title: "Show cursor", detail: "Include the pointer in fullscreen and timed captures.", isOn: $includeCursor)
                CardDivider()
                ToggleRow(title: "Capture window shadow", detail: "Keep the standard window shadow when capturing windows.", isOn: $captureWindowShadow)
            }

            SectionLabel(title: "Recording")
            SettingsCard {
                ToggleRow(title: "Show controls while recording", detail: "Keep the system recording controls visible during screen recordings.", isOn: $showRecordingControls)
                CardDivider()
                ToggleRow(title: "Highlight clicks", detail: "Show click feedback in screen recordings.", isOn: $highlightRecordingClicks)
                CardDivider()
                ToggleRow(title: "Record microphone audio", detail: "Capture audio from the default input device while recording.", isOn: $recordRecordingAudio)
            }

            SectionLabel(title: "Text Recognition")
            SettingsCard {
                ToggleRow(title: "Detect language automatically", detail: "Let on-device text recognition choose the language.", isOn: $autoDetectTextLanguage)
                CardDivider()
                ToggleRow(title: "Keep line breaks", detail: "Preserve recognized line breaks when copying text.", isOn: $keepTextLineBreaks)
            }

            SectionLabel(title: "Pins and History")
            SettingsCard {
                SettingsRow {
                    RowLabel(title: "Quick Access overlays", detail: "\(service.overlays.count) active")
                } trailing: {
                    IconChipButton(symbol: "xmark", label: "Close all", action: service.closeAllOverlays)
                }
                CardDivider()
                actionRow(
                    title: "Open image",
                    detail: "Choose a local image and show it in a Quick Access overlay.",
                    symbol: "photo",
                    action: service.chooseAndOpenImage
                )
                CardDivider()
                actionRow(
                    title: "Choose and pin an image",
                    detail: "Open an image in an always-on-top reference window.",
                    symbol: "pin",
                    action: service.chooseAndPinImage
                )
                CardDivider()
                actionRow(
                    title: "Pin last capture",
                    detail: "Pin the most recent local screenshot.",
                    symbol: "pin.fill",
                    action: service.pinLastCapture
                )
                CardDivider()
                actionRow(
                    title: "Show last capture",
                    detail: "Reopen the most recent local capture in a Quick Access overlay.",
                    symbol: "rectangle.on.rectangle",
                    action: service.showLastCaptureOverlay
                )
                CardDivider()
                actionRow(
                    title: "Markup last capture",
                    detail: "Open the most recent local capture for system markup.",
                    symbol: "pencil.and.outline",
                    action: service.markupLastCapture
                )
                CardDivider()
                actionRow(
                    title: "Restore last capture",
                    detail: "Make the most recent local capture active again and reopen it.",
                    symbol: "arrow.counterclockwise",
                    action: service.restoreLastCapture
                )
                CardDivider()
                actionRow(
                    title: "Copy last capture",
                    detail: "Copy the most recent local capture to the clipboard.",
                    symbol: "doc.on.doc",
                    action: service.copyLastCapture
                )
                CardDivider()
                actionRow(
                    title: "Open last capture",
                    detail: "Open the most recent local capture in its default app.",
                    symbol: "arrow.up.right.square",
                    action: service.openLastCapture
                )
                CardDivider()
                actionRow(
                    title: "Reveal last capture",
                    detail: "Show the most recent local capture in Finder.",
                    symbol: "folder",
                    action: service.revealLastCapture
                )
                CardDivider()
                actionRow(
                    title: "Open capture history",
                    detail: "Open a local list of recent captures with actions.",
                    symbol: "clock",
                    action: service.openCaptureHistory
                )
                CardDivider()
                actionRow(
                    title: "Reveal capture folder",
                    detail: "Show the local export folder in Finder.",
                    symbol: "folder",
                    action: service.revealCaptureFolder
                )
                CardDivider()
                SettingsRow {
                    RowLabel(title: "Open pins", detail: "\(service.pins.count) active")
                } trailing: {
                    IconChipButton(symbol: "xmark", label: "Close all", action: service.closeAllPins)
                }
            }
        }
    }

    private var currentExportLocation: LocalizedStringKey {
        let path = exportDirectory.isEmpty ? ScreenToolSettings.exportDirectoryURL.path : exportDirectory
        return LocalizedStringKey(path)
    }

    @ViewBuilder
    private func actionRow(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        SettingsRow {
            RowLabel(title: title, detail: detail)
        } trailing: {
            IconChipButton(symbol: symbol, label: "Run", isPrimary: true, action: action)
        }
    }

    private func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = ScreenToolSettings.exportDirectoryURL
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            exportDirectory = url.path
            ToastCenter.shared.show("Export location updated")
        }
    }
}
