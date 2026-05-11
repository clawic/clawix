import SwiftUI
import AppKit
import ClawixSimulatorKitShim

struct IOSSimulatorNativeDisplayView: NSViewRepresentable {
    let display: IOSSimulatorNativeDisplayDescriptor

    func makeNSView(context: Context) -> NativeDisplayHostView {
        let view = NativeDisplayHostView()
        view.configure(display: display)
        return view
    }

    func updateNSView(_ nsView: NativeDisplayHostView, context: Context) {
        nsView.configure(display: display)
    }

    final class NativeDisplayHostView: NSView {
        private typealias ObjCInitScreenFn = @convention(c) (AnyObject, Selector, AnyObject, UInt32) -> AnyObject?
        private typealias ObjCInitFrameFn = @convention(c) (AnyObject, Selector, CGRect) -> AnyObject?

        private var configuredUDID: String?
        private var displayView: NSView?
        private var retainedScreen: AnyObject?
        private var retainedDisplay: AnyObject?

        private static let simulatorKitPath = "/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
        private static let coreSimulatorPath = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"
        private static let mainScreenID: UInt32 = 1
        private static let allInputs: UInt = 7

        override var isFlipped: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            setAccessibilityElement(true)
            setAccessibilityRole(.group)
            setAccessibilityLabel("Embedded iOS Simulator")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(display: IOSSimulatorNativeDisplayDescriptor) {
            guard configuredUDID != display.deviceUDID else { return }
            configuredUDID = display.deviceUDID
            displayView?.removeFromSuperview()
            displayView = nil
            retainedScreen = nil
            retainedDisplay = nil

            guard
                Self.loadFramework(Self.coreSimulatorPath) != nil,
                let simulatorKit = Self.loadFramework(Self.simulatorKitPath),
                let simDevice = Self.resolveSimDevice(udid: display.deviceUDID),
                let screen = Self.createScreen(device: simDevice),
                let view = Self.createDisplayView(),
                let connect = dlsym(simulatorKit, "$s12SimulatorKit14SimDisplayViewC7connect6screen6inputsyAA0C12DeviceScreenC_AC0j5InputI0VtKFTj")
            else {
                return
            }

            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
            addSubview(view)
            displayView = view
            retainedScreen = screen
            retainedDisplay = view
            needsLayout = true
            ClawixSimKitConnectDisplayView(
                connect,
                Unmanaged.passUnretained(view).toOpaque(),
                Unmanaged.passUnretained(screen).toOpaque(),
                Self.allInputs
            )
        }

        override func layout() {
            super.layout()
            guard let displayView else { return }
            let maxRect = bounds.insetBy(dx: 2, dy: 2)
            let aspect: CGFloat = 1206.0 / 2622.0
            var width = maxRect.width
            var height = width / aspect
            if height > maxRect.height {
                height = maxRect.height
                width = height * aspect
            }
            displayView.frame = CGRect(
                x: maxRect.midX - width / 2,
                y: maxRect.midY - height / 2,
                width: width,
                height: height
            )
        }

        private static func createDisplayView() -> NSView? {
            guard
                let displayClass = NSClassFromString("SimulatorKit.SimDisplayView") as AnyObject?,
                let allocated = displayClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
                let objcMessageSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
            else {
                return nil
            }
            let initFrame = unsafeBitCast(objcMessageSymbol, to: ObjCInitFrameFn.self)
            return initFrame(
                allocated,
                NSSelectorFromString("initWithFrame:"),
                CGRect(x: 0, y: 0, width: 393, height: 852)
            ) as? NSView
        }

        private static func loadFramework(_ path: String) -> UnsafeMutableRawPointer? {
            if let handle = dlopen(path, RTLD_NOLOAD | RTLD_NOW | RTLD_GLOBAL) {
                return handle
            }
            return dlopen(path, RTLD_NOW | RTLD_GLOBAL)
        }

        private static func resolveSimDevice(udid: String) -> AnyObject? {
            guard
                let contextClass = NSClassFromString("SimServiceContext") as? NSObject.Type,
                let context = contextClass.perform(
                    NSSelectorFromString("sharedServiceContextForDeveloperDir:error:"),
                    with: "/Applications/Xcode.app/Contents/Developer" as NSString,
                    with: nil
                )?.takeUnretainedValue() as? NSObject
            else {
                return nil
            }

            _ = context.perform(NSSelectorFromString("connectWithError:"), with: nil)
            guard
                let set = context.perform(NSSelectorFromString("defaultDeviceSetWithError:"), with: nil)?
                    .takeUnretainedValue() as? NSObject,
                let devices = set.value(forKey: "devices") as? NSArray
            else {
                return nil
            }

            for case let device as NSObject in devices {
                guard
                    let uuid = device.perform(NSSelectorFromString("UDID"))?.takeUnretainedValue() as? NSUUID,
                    uuid.uuidString == udid
                else {
                    continue
                }
                return device
            }
            return nil
        }

        private static func createScreen(device: AnyObject) -> AnyObject? {
            guard
                let screenClass = NSClassFromString("SimulatorKit.SimDeviceScreen") as AnyObject?,
                let allocated = screenClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
                let objcMessageSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
            else {
                return nil
            }

            let initScreen = unsafeBitCast(objcMessageSymbol, to: ObjCInitScreenFn.self)
            return initScreen(
                allocated,
                NSSelectorFromString("initWithDevice:screenID:"),
                device,
                mainScreenID
            )
        }
    }
}
