import SwiftUI
import AppKit

extension AndroidSimulatorFramebufferController {
    func runStartup() async {
        state = .locatingTools
        do {
            let toolchain = try await Self.locateToolchain()
            let adb = toolchain.adbPath
            let emulator = toolchain.emulatorPath
            adbPath = adb
            emulatorPath = emulator
            availableAVDs = toolchain.avds
            state = .locatingDevice

            let beforeDevices = try await Self.connectedEmulators(adbPath: adb)
            let device: AndroidEmulatorDevice
            var ownsDevice = false
            if let existing = Self.selectConnectedDevice(
                from: beforeDevices,
                preferredAVDName: payload?.avdName
            ) {
                device = existing
            } else {
                let avd = try Self.selectAVD(from: availableAVDs, preferredName: payload?.avdName)
                state = .booting(avd.displayName)
                try await launchHeadlessAVD(avd, emulatorPath: emulator)
                device = try await Self.waitForBootedEmulator(
                    adbPath: adb,
                    preferredAVDName: avd.name,
                    previousSerials: Set(beforeDevices.map(\.serial))
                )
                ownsDevice = true
            }

            if Task.isCancelled { return }
            selectedDevice = device
            ownsSelectedDevice = ownsDevice
            state = .capturing(device.displayName)
            await captureOnce(adbPath: adb, device: device, markRunning: true)
            startCaptureLoop(adbPath: adb, device: device)
        } catch {
            if !Task.isCancelled {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func launchHeadlessAVD(_ avd: AndroidAVDChoice, emulatorPath: String?) async throws {
        guard let emulatorPath else {
            throw AndroidSimulatorError.commandFailed("Android Emulator was not found. Install Android SDK Emulator and create at least one AVD.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: emulatorPath)
        process.arguments = [
            "-avd", avd.name,
            "-no-window",
            "-no-audio",
            "-no-boot-anim",
            "-no-metrics",
            "-gpu", "swiftshader_indirect"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        emulatorProcess = process
    }

    func startCaptureLoop(adbPath: String, device: AndroidEmulatorDevice) {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                if self?.pointerIsActive == true {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    continue
                }
                await self?.captureOnce(adbPath: adbPath, device: device, markRunning: true)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func captureOnce(adbPath: String, device: AndroidEmulatorDevice, markRunning: Bool) async {
        guard !captureInFlight else { return }
        captureInFlight = true
        defer { captureInFlight = false }

        do {
            let png = try await Self.screenshot(adbPath: adbPath, serial: device.serial)
            if Task.isCancelled { return }
            guard let image = NSImage(data: png) else {
                throw AndroidSimulatorError.commandFailed("Emulator returned an unreadable screenshot.")
            }
            consecutiveCaptureFailures = 0
            frameImage = image
            statusLine = "\(device.displayName) · \(Int(image.size.width))x\(Int(image.size.height)) · embedded · interactive"
            if markRunning {
                state = .running(device.displayName)
            }
        } catch {
            if !Task.isCancelled {
                consecutiveCaptureFailures += 1
                if frameImage != nil && consecutiveCaptureFailures < 3 {
                    statusLine = "\(device.displayName) · display capture retrying · embedded · interactive"
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }


}
