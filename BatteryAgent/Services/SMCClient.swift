import Foundation
import os.log

final class SMCClient: Sendable {

    static let shared = SMCClient()

    private let socketPath = "/tmp/BatteryAgentHelper.sock"

    nonisolated private let logger = Logger(
        subsystem: Constants.appBundleIdentifier,
        category: "SMCClient"
    )

    nonisolated private init() {}

    // MARK: - Public API

    var isDaemonRunning: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    func enableCharging(completion: @escaping @Sendable (Bool) -> Void) {
        sendCommand("enable-charging", completion: completion)
    }

    func disableCharging(completion: @escaping @Sendable (Bool) -> Void) {
        sendCommand("disable-charging", completion: completion)
    }

    func setForceDischarge(_ enabled: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        let cmd = enabled ? "enable-force-discharge" : "disable-force-discharge"
        sendCommand(cmd, completion: completion)
    }

    /// Install the helper daemon (one-time, requires admin password)
    func installDaemon(completion: @escaping @Sendable (Bool) -> Void) {
        let helperPath = bundledHelperPath
        logger.info("Installing daemon from: \(helperPath)")

        DispatchQueue.global(qos: .userInitiated).async { [logger] in
            let script = """
            do shell script "'\(helperPath)' install-daemon" with administrator privileges
            """
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            let result = appleScript?.executeAndReturnError(&error)

            if let error {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown"
                logger.error("Install failed: \(msg)")
                completion(false)
            } else {
                let output = result?.stringValue ?? ""
                logger.info("Install result: \(output)")
                completion(output.hasPrefix("OK"))
            }
        }
    }

    // MARK: - Socket Communication

    private func sendCommand(_ command: String, completion: @escaping @Sendable (Bool) -> Void) {
        logger.info("SMC command: \(command)")

        DispatchQueue.global(qos: .userInitiated).async { [self, logger] in
            if self.isDaemonRunning {
                let result = self.sendViaSocket(command)
                logger.info("Socket result: \(result ?? "nil")")
                completion(result?.hasPrefix("OK") ?? false)
            } else {
                // Daemon not running — use osascript fallback
                logger.info("Daemon not running, using osascript fallback")
                let success = self.runWithAdminPrivileges(command)
                completion(success)
            }
        }
    }

    private func sendViaSocket(_ command: String) -> String? {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                pathPtr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                    _ = strcpy(dest, ptr)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return nil }

        // Send command
        command.withCString { ptr in
            _ = write(sock, ptr, strlen(ptr))
        }

        // Read response
        var buffer = [UInt8](repeating: 0, count: 1024)
        let bytesRead = read(sock, &buffer, 1023)
        guard bytesRead > 0 else { return nil }

        return String(bytes: buffer.prefix(bytesRead), encoding: .utf8)
    }

    // MARK: - Fallback: osascript

    private func runWithAdminPrivileges(_ command: String) -> Bool {
        let helperPath = bundledHelperPath
        let script = """
        do shell script "'\(helperPath)' \(command)" with administrator privileges
        """

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown"
            logger.error("osascript failed: \(msg)")
            return false
        }

        let output = result?.stringValue ?? ""
        logger.info("osascript output: \(output)")
        return true
    }

    private var bundledHelperPath: String {
        if let path = Bundle.main.path(forAuxiliaryExecutable: "BatteryAgentHelper") {
            return path
        }
        return (Bundle.main.bundlePath as NSString)
            .appendingPathComponent("Contents/MacOS/BatteryAgentHelper")
    }
}
