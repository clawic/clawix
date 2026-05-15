import AppKit

extension ScreenToolService {
    func showAllInOneMenu() {
        guard featureVisible else { return }
        guard authorize("showAllInOneMenu") else { return }
        let menu = NSMenu()
        let target = ScreenToolMenuActionTarget { [weak self] action in
            guard let self else { return }
            self.allInOneMenu = nil
            self.allInOneMenuTarget = nil
            switch action {
            case .captureArea:         self.captureArea()
            case .capturePreviousArea: self.capturePreviousArea()
            case .captureFullscreen:   self.captureFullscreen()
            case .captureWindow:       self.captureWindow()
            case .captureScrolling:    self.captureScrolling()
            case .captureSelfTimer:    self.captureSelfTimer()
            case .recordScreen:        self.recordScreen()
            case .captureText:         self.captureText()
            case .recognizeLastText:   self.recognizeLastCaptureText()
            case .hideDesktopIcons:    MacUtilitiesController.shared.perform(.toggleDesktopIcons)
            case .openImage:           self.chooseAndOpenImage()
            case .pinImage:            self.chooseAndPinImage()
            case .pinLastCapture:      self.pinLastCapture()
            case .showLastCapture:     self.showLastCaptureOverlay()
            case .markupLastCapture:   self.markupLastCapture()
            case .restoreLastCapture:  self.restoreLastCapture()
            case .copyLastCapture:     self.copyLastCapture()
            case .openLastCapture:     self.openLastCapture()
            case .revealLastCapture:   self.revealLastCapture()
            case .captureHistory:      self.openCaptureHistory()
            case .revealCaptureFolder: self.revealCaptureFolder()
            case .closeAllOverlays:    self.closeAllOverlays()
            case .closeAllPins:        self.closeAllPins()
            }
        }
        allInOneMenu = menu
        allInOneMenuTarget = target

        func addItem(_ title: String, action: ScreenToolMenuAction, symbol: String) {
            let item = NSMenuItem(title: title, action: #selector(ScreenToolMenuActionTarget.runScreenToolMenuAction(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = action.rawValue
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            menu.addItem(item)
        }

        addItem("Capture Area", action: .captureArea, symbol: "crop")
        addItem("Capture Previous Area", action: .capturePreviousArea, symbol: "rectangle.dashed")
        addItem("Capture Fullscreen", action: .captureFullscreen, symbol: "rectangle.inset.filled")
        addItem("Capture Window", action: .captureWindow, symbol: "macwindow")
        addItem("Scrolling Capture", action: .captureScrolling, symbol: "arrow.down.doc")
        addItem("Self-Timer", action: .captureSelfTimer, symbol: "timer")
        menu.addItem(.separator())
        addItem("Record Screen", action: .recordScreen, symbol: "record.circle")
        addItem("Capture Text", action: .captureText, symbol: "text.viewfinder")
        addItem("Recognize Last Capture Text", action: .recognizeLastText, symbol: "doc.text.viewfinder")
        addItem("Hide Desktop Icons", action: .hideDesktopIcons, symbol: "square.grid.3x3")
        menu.addItem(.separator())
        addItem("Open Image...", action: .openImage, symbol: "photo")
        addItem("Pin Image...", action: .pinImage, symbol: "pin")
        addItem("Pin Last Capture", action: .pinLastCapture, symbol: "pin.fill")
        addItem("Show Last Capture", action: .showLastCapture, symbol: "rectangle.on.rectangle")
        addItem("Markup Last Capture", action: .markupLastCapture, symbol: "pencil.and.outline")
        addItem("Restore Last Capture", action: .restoreLastCapture, symbol: "arrow.counterclockwise")
        addItem("Copy Last Capture", action: .copyLastCapture, symbol: "doc.on.doc")
        addItem("Open Last Capture", action: .openLastCapture, symbol: "arrow.up.right.square")
        addItem("Reveal Last Capture", action: .revealLastCapture, symbol: "folder")
        addItem("Capture History...", action: .captureHistory, symbol: "clock")
        addItem("Reveal Capture Folder", action: .revealCaptureFolder, symbol: "folder")
        addItem("Close All Overlays", action: .closeAllOverlays, symbol: "xmark")
        addItem("Close All Pins", action: .closeAllPins, symbol: "xmark")

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
