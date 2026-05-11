import AppKit

@MainActor
final class IOSSimulatorHIDBridge {
    let device: SimDevice

    private typealias ObjCInitScreenFn = @convention(c) (AnyObject, Selector, AnyObject, UInt32) -> AnyObject?
    private typealias HIDTargetForScreenFn = @convention(c) (AnyObject) -> UInt64
    private typealias HIDMouseMessageFn = @convention(c) (
        UnsafePointer<CGPoint>,
        UnsafePointer<CGPoint>,
        UInt64,
        UInt,
        CGSize,
        UInt32
    ) -> UnsafeMutableRawPointer?
    private typealias HIDNoArgMessageFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias HIDPointerEventMessageFn = @convention(c) (UnsafeMutableRawPointer, UInt64) -> UnsafeMutableRawPointer?
    private typealias HIDSendMessageFn = @convention(c) (
        AnyObject,
        Selector,
        UnsafeMutableRawPointer?,
        Bool,
        AnyObject?,
        AnyObject?
    ) -> Void
    private typealias IOHIDCreateDigitizerEventFn = @convention(c) (
        CFAllocator?,
        UInt64,
        UInt32,
        UInt32,
        UInt32,
        UInt32,
        UInt32,
        CGFloat,
        CGFloat,
        CGFloat,
        CGFloat,
        CGFloat,
        Bool,
        Bool,
        UInt32
    ) -> UnsafeMutableRawPointer?
    private typealias IOHIDCreateDigitizerFingerEventFn = @convention(c) (
        CFAllocator?,
        UInt64,
        UInt32,
        UInt32,
        UInt32,
        CGFloat,
        CGFloat,
        CGFloat,
        CGFloat,
        CGFloat,
        Bool,
        Bool,
        UInt32
    ) -> UnsafeMutableRawPointer?
    private typealias IOHIDAppendEventFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32) -> Void
    private typealias IOHIDSetIntegerValueFn = @convention(c) (UnsafeMutableRawPointer, UInt32, Int) -> Void
    private typealias IOHIDSetFloatValueFn = @convention(c) (UnsafeMutableRawPointer, UInt32, CGFloat) -> Void

    private static let simulatorKitPath = "/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
    private static let coreSimulatorPath = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"
    private static let ioKitPath = "/System/Library/Frameworks/IOKit.framework/IOKit"
    private static let mainScreenID: UInt32 = 1
    private static let digitizerEventRange: UInt32 = 1 << 0
    private static let digitizerEventTouch: UInt32 = 1 << 1
    private static let digitizerEventPosition: UInt32 = 1 << 2
    private static let digitizerTransducerHand: UInt32 = 3
    private static let digitizerFieldMajorRadius: UInt32 = 0xB0014
    private static let digitizerFieldMinorRadius: UInt32 = 0xB0015
    private static let digitizerFieldDisplayIntegrated: UInt32 = 0xB0019

    private let client: AnyObject
    private let target: UInt64
    let screenSize: CGSize
    private let mouseMessage: HIDMouseMessageFn
    private let pointerEventMessage: HIDPointerEventMessageFn?
    private let createDigitizerEvent: IOHIDCreateDigitizerEventFn?
    private let createDigitizerFingerEvent: IOHIDCreateDigitizerFingerEventFn?
    private let appendHIDEvent: IOHIDAppendEventFn?
    private let setHIDIntegerValue: IOHIDSetIntegerValueFn?
    private let setHIDFloatValue: IOHIDSetFloatValueFn?
    private let sendMessage: HIDSendMessageFn

    init?(device: SimDevice) {
        self.device = device
        _ = Self.loadFramework(Self.coreSimulatorPath)
        let ioKit = Self.loadFramework(Self.ioKitPath)
        guard
            let simulatorKit = Self.loadFramework(Self.simulatorKitPath),
            let simDevice = Self.resolveSimDevice(udid: device.udid),
            let screen = Self.createScreen(device: simDevice),
            let client = Self.createClient(device: simDevice),
            let targetForScreenSymbol = dlsym(simulatorKit, "IndigoHIDTargetForScreen"),
            let mouseMessageSymbol = dlsym(simulatorKit, "IndigoHIDMessageForMouseNSEvent"),
            let createMouseSymbol = dlsym(simulatorKit, "IndigoHIDMessageToCreateMouseService"),
            let objcMessageSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
        else {
            return nil
        }

        let targetForScreen = unsafeBitCast(targetForScreenSymbol, to: HIDTargetForScreenFn.self)
        let createMouseMessage = unsafeBitCast(createMouseSymbol, to: HIDNoArgMessageFn.self)
        self.mouseMessage = unsafeBitCast(mouseMessageSymbol, to: HIDMouseMessageFn.self)
        self.pointerEventMessage = dlsym(simulatorKit, "IndigoHIDMessageForPointerEventFromHIDEventRef")
            .map { unsafeBitCast($0, to: HIDPointerEventMessageFn.self) }
        self.createDigitizerEvent = ioKit.flatMap { dlsym($0, "IOHIDEventCreateDigitizerEvent") }
            .map { unsafeBitCast($0, to: IOHIDCreateDigitizerEventFn.self) }
        self.createDigitizerFingerEvent = ioKit.flatMap { dlsym($0, "IOHIDEventCreateDigitizerFingerEvent") }
            .map { unsafeBitCast($0, to: IOHIDCreateDigitizerFingerEventFn.self) }
        self.appendHIDEvent = ioKit.flatMap { dlsym($0, "IOHIDEventAppendEvent") }
            .map { unsafeBitCast($0, to: IOHIDAppendEventFn.self) }
        self.setHIDIntegerValue = ioKit.flatMap { dlsym($0, "IOHIDEventSetIntegerValue") }
            .map { unsafeBitCast($0, to: IOHIDSetIntegerValueFn.self) }
        self.setHIDFloatValue = ioKit.flatMap { dlsym($0, "IOHIDEventSetFloatValue") }
            .map { unsafeBitCast($0, to: IOHIDSetFloatValueFn.self) }
        self.sendMessage = unsafeBitCast(objcMessageSymbol, to: HIDSendMessageFn.self)
        self.client = client
        self.target = targetForScreen(screen)
        self.screenSize = CGSize(width: 1206, height: 2622)

        send(createMouseMessage())
    }

    enum TouchPhase {
        case began
        case moved
        case ended
    }

    func sendTouchEvent(phase: TouchPhase, point: CGPoint, screenSize: CGSize) {
        guard
            let pointerEventMessage,
            let createDigitizerEvent,
            let createDigitizerFingerEvent,
            let appendHIDEvent,
            let setHIDIntegerValue,
            let setHIDFloatValue
        else {
            return
        }

        let touchX = min(max(point.x, 0), max(1, screenSize.width))
        let touchY = min(max(point.y, 0), max(1, screenSize.height))
        let mask: UInt32
        let isTouching: Bool
        switch phase {
        case .began:
            mask = Self.digitizerEventRange | Self.digitizerEventTouch | Self.digitizerEventPosition
            isTouching = true
        case .moved:
            mask = Self.digitizerEventPosition
            isTouching = true
        case .ended:
            mask = Self.digitizerEventRange | Self.digitizerEventTouch
            isTouching = false
        }

        guard
            let parent = createDigitizerEvent(
                kCFAllocatorDefault,
                mach_absolute_time(),
                Self.digitizerTransducerHand,
                0,
                0,
                mask,
                0,
                0,
                0,
                0,
                0,
                0,
                isTouching,
                isTouching,
                0
            ),
            let finger = createDigitizerFingerEvent(
                kCFAllocatorDefault,
                mach_absolute_time(),
                1,
                1,
                mask,
                touchX,
                touchY,
                0,
                isTouching ? 0.5 : 0,
                0,
                isTouching,
                isTouching,
                0
            )
        else {
            return
        }

        setHIDIntegerValue(parent, Self.digitizerFieldDisplayIntegrated, 1)
        setHIDFloatValue(finger, Self.digitizerFieldMajorRadius, 0.04)
        setHIDFloatValue(finger, Self.digitizerFieldMinorRadius, 0.04)
        appendHIDEvent(parent, finger, 0)
        send(pointerEventMessage(parent, target))
    }

    func sendMouseEvent(type: NSEvent.EventType, point: CGPoint, previousPoint: CGPoint, screenSize: CGSize) {
        let width = max(1, screenSize.width)
        let height = max(1, screenSize.height)
        var current = CGPoint(
            x: min(max(point.x / width, 0), 1),
            y: 1 - min(max(point.y / height, 0), 1)
        )
        var previous = CGPoint(
            x: min(max(previousPoint.x / width, 0), 1),
            y: 1 - min(max(previousPoint.y / height, 0), 1)
        )
        let unitScreenSize = CGSize(width: 1, height: 1)
        let message = mouseMessage(
            &current,
            &previous,
            target,
            UInt(type.rawValue),
            unitScreenSize,
            0
        )
        send(message)
    }

    private func send(_ message: UnsafeMutableRawPointer?) {
        guard let message else { return }
        sendMessage(
            client,
            NSSelectorFromString("sendWithMessage:freeWhenDone:completionQueue:completion:"),
            message,
            true,
            nil,
            nil
        )
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

    private static func createClient(device: AnyObject) -> AnyObject? {
        guard
            let clientClass = NSClassFromString("SimulatorKit.SimDeviceLegacyHIDClient") as AnyObject?,
            let allocated = clientClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject
        else {
            return nil
        }
        return allocated
            .perform(NSSelectorFromString("initWithDevice:error:"), with: device, with: nil)?
            .takeUnretainedValue()
    }
}
