import Foundation
import Security
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
            let ok = Self.runPrivileged(tool: helperPath, args: ["install-daemon"], logger: logger)
            if ok {
                // Wait for daemon socket to appear (up to 3 seconds)
                for _ in 0..<30 {
                    Thread.sleep(forTimeInterval: 0.1)
                    if FileManager.default.fileExists(atPath: "/tmp/BatteryAgentHelper.sock") { break }
                }
            }
            completion(ok)
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
                logger.info("Daemon not running, using privileged fallback")
                let success = Self.runPrivileged(
                    tool: self.bundledHelperPath,
                    args: [command],
                    logger: logger
                )
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

        command.withCString { ptr in
            _ = write(sock, ptr, strlen(ptr))
        }

        var buffer = [UInt8](repeating: 0, count: 1024)
        let bytesRead = read(sock, &buffer, 1023)
        guard bytesRead > 0 else { return nil }

        return String(bytes: buffer.prefix(bytesRead), encoding: .utf8)
    }

    // MARK: - Privileged Execution

    /// Runs `tool` with `args` as root using the native macOS authorization dialog.
    /// Uses Security framework's AuthorizationExecuteWithPrivileges — no Apple Events permission needed.
    private static func runPrivileged(tool: String, args: [String], logger: Logger) -> Bool {
        // 1. Create authorization reference
        var authRef: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authRef) == errAuthorizationSuccess,
              let auth = authRef else {
            logger.error("AuthorizationCreate failed")
            return false
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        // 2. Show native macOS password dialog
        let authStatus: OSStatus = kAuthorizationRightExecute.withCString { namePtr in
            var item = AuthorizationItem(name: namePtr, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPtr in
                var rights = AuthorizationRights(count: 1, items: itemPtr)
                return AuthorizationCopyRights(
                    auth, &rights, nil,
                    [.interactionAllowed, .preAuthorize, .extendRights],
                    nil
                )
            }
        }

        guard authStatus == errAuthorizationSuccess else {
            logger.error("Authorization denied or cancelled: \(authStatus)")
            return false
        }

        // 3. Invoke AuthorizationExecuteWithPrivileges via dlsym
        // (deprecated but functional; accessed this way to avoid compiler warnings)
        // Signature: OSStatus(AuthorizationRef, const char*, AuthorizationFlags, char*const*, FILE**)
        typealias AuthExecFn = @convention(c) (
            AuthorizationRef,                                        // authorization
            UnsafePointer<CChar>,                                    // pathToTool
            AuthorizationFlags,                                      // options
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,     // arguments
            UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?       // communicationsPipe
        ) -> OSStatus

        // RTLD_DEFAULT = (void *)(-2) on Darwin — searches all currently loaded libraries
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, "AuthorizationExecuteWithPrivileges") else {
            logger.error("AuthorizationExecuteWithPrivileges symbol not found")
            return false
        }
        let authExec = unsafeBitCast(sym, to: AuthExecFn.self)

        // 4. Build null-terminated C argument array and execute
        let cArgs: [UnsafeMutablePointer<CChar>] = args.compactMap { strdup($0) }
        defer { cArgs.forEach { free($0) } }
        var argv: [UnsafeMutablePointer<CChar>?] = cArgs.map { Optional($0) } + [nil]

        let status: OSStatus = tool.withCString { toolPath in
            argv.withUnsafeMutableBufferPointer { buf in
                authExec(auth, toolPath, [], buf.baseAddress, nil)
            }
        }

        if status != errAuthorizationSuccess {
            logger.error("AuthorizationExecuteWithPrivileges failed: \(status)")
            return false
        }
        return true
    }

    // MARK: - Helper Path

    private var bundledHelperPath: String {
        if let path = Bundle.main.path(forAuxiliaryExecutable: "BatteryAgentHelper") {
            return path
        }
        return (Bundle.main.bundlePath as NSString)
            .appendingPathComponent("Contents/MacOS/BatteryAgentHelper")
    }
}
