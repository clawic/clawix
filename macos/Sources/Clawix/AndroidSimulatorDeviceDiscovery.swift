import Foundation
import AppKit

extension AndroidSimulatorFramebufferController {
    nonisolated static func connectedEmulators(adbPath: String) async throws -> [AndroidEmulatorDevice] {
        let result = try await runTool(adbPath, ["devices"])
        guard result.status == 0 else {
            throw AndroidSimulatorError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let serials = result.stdout
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> (String, String)? in
                let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
                guard parts.count >= 2, parts[0].hasPrefix("emulator-") else { return nil }
                return (parts[0], parts[1])
            }

        var devices: [AndroidEmulatorDevice] = []
        for (serial, state) in serials {
            let avdName = try? await avdName(adbPath: adbPath, serial: serial)
            devices.append(AndroidEmulatorDevice(serial: serial, state: state, avdName: avdName))
        }
        return devices
    }

    nonisolated static func waitForBootedEmulator(
        adbPath: String,
        preferredAVDName: String?,
        previousSerials: Set<String>
    ) async throws -> AndroidEmulatorDevice {
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            let devices = try await connectedEmulatorStates(adbPath: adbPath)
            let sorted = devices.sorted { lhs, rhs in
                let lhsNew = !previousSerials.contains(lhs.serial)
                let rhsNew = !previousSerials.contains(rhs.serial)
                if lhsNew != rhsNew { return lhsNew && !rhsNew }
                return lhs.serial < rhs.serial
            }
            for device in sorted where device.state == "device" {
                let booted = try? await runTool(adbPath, [
                    "-s", device.serial,
                    "shell", "getprop", "sys.boot_completed"
                ])
                if booted?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                    _ = try? await runTool(adbPath, ["-s", device.serial, "shell", "input", "keyevent", "82"])
                    return AndroidEmulatorDevice(
                        serial: device.serial,
                        state: device.state,
                        avdName: preferredAVDName ?? device.avdName
                    )
                }
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw AndroidSimulatorError.commandFailed("Timed out waiting for the Android emulator to boot.")
    }

    nonisolated static func connectedEmulatorStates(adbPath: String) async throws -> [AndroidEmulatorDevice] {
        let result = try await runTool(adbPath, ["devices"], timeout: 8)
        guard result.status == 0 else {
            throw AndroidSimulatorError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> AndroidEmulatorDevice? in
                let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
                guard parts.count >= 2, parts[0].hasPrefix("emulator-") else { return nil }
                return AndroidEmulatorDevice(serial: parts[0], state: parts[1], avdName: nil)
            }
    }

    nonisolated static func avdName(adbPath: String, serial: String) async throws -> String? {
        let result = try await runTool(adbPath, ["-s", serial, "emu", "avd", "name"])
        guard result.status == 0 else { return nil }
        return result.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "OK" }
    }

    nonisolated static func screenshot(adbPath: String, serial: String) async throws -> Data {
        let result = try await runTool(adbPath, ["-s", serial, "exec-out", "screencap", "-p"], captureBinary: true)
        guard result.status == 0 else {
            throw AndroidSimulatorError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdoutData
    }


}
