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

    // MARK: - Daemon Status (캐싱)

    /// 캐싱된 데몬 상태 — 10초마다 갱신
    private nonisolated(unsafe) let _daemonStatusLock = NSLock()
    private nonisolated(unsafe) var _cachedDaemonRunning: Bool = false
    private nonisolated(unsafe) var _lastDaemonCheck: Date = .distantPast

    var isDaemonRunning: Bool {
        _daemonStatusLock.lock()
        defer { _daemonStatusLock.unlock() }

        let now = Date()
        if now.timeIntervalSince(_lastDaemonCheck) < 10 {
            return _cachedDaemonRunning
        }

        let running = FileManager.default.fileExists(atPath: socketPath)
            && sendViaSocket("ping") != nil
        _cachedDaemonRunning = running
        _lastDaemonCheck = now
        return running
    }

    /// 데몬 상태 캐시 무효화 (설치 후 등)
    private func invalidateDaemonCache() {
        _daemonStatusLock.lock()
        _lastDaemonCheck = .distantPast
        _daemonStatusLock.unlock()
    }

    // MARK: - Public API

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

    /// 설치된 헬퍼 데몬의 버전 문자열을 반환한다. 데몬이 응답하지 않으면 nil.
    func getHelperVersion() -> String? {
        guard let response = sendViaSocket("version"),
              response.hasPrefix("OK ") else { return nil }
        return String(response.dropFirst(3)) // "OK " 제거
    }

    /// 앱 번들의 CFBundleVersion (빌드 번호)
    var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// 설치된 헬퍼와 앱 번들의 버전이 다르면 true
    var isHelperVersionMismatch: Bool {
        guard let installed = getHelperVersion() else {
            // 버전 응답 없음 = 구버전 헬퍼 (version 명령 미지원) → 업데이트 필요
            return isDaemonRunning
        }
        return installed != bundleVersion
    }

    /// Install the helper daemon (one-time, requires admin password)
    func installDaemon(completion: @escaping @Sendable (Bool) -> Void) {
        let helperPath = bundledHelperPath
        logger.info("Installing daemon from: \(helperPath)")

        DispatchQueue.global(qos: .userInitiated).async { [self, logger] in
            let ok = Self.runPrivileged(tool: helperPath, args: ["install-daemon"], logger: logger)
            if ok {
                // Wait for daemon socket to appear (up to 3 seconds)
                for _ in 0..<30 {
                    Thread.sleep(forTimeInterval: 0.1)
                    if FileManager.default.fileExists(atPath: "/tmp/BatteryAgentHelper.sock") { break }
                }
            }
            self.invalidateDaemonCache()
            completion(ok)
        }
    }

    // MARK: - Socket Communication

    private func sendCommand(_ command: String, completion: @escaping @Sendable (Bool) -> Void) {
        logger.info("SMC command: \(command)")

        DispatchQueue.global(qos: .userInitiated).async { [self, logger] in
            if let result = self.sendViaSocket(command) {
                logger.info("Socket result: \(result)")
                completion(result.hasPrefix("OK"))
            } else {
                logger.warning("Socket command failed: \(command) — daemon may not be running")
                completion(false)
            }
        }
    }

    private func sendViaSocket(_ command: String) -> String? {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        // 소켓 타임아웃 설정 (5초)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

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

    private static func runPrivileged(tool: String, args: [String], logger: Logger) -> Bool {
        var authRef: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authRef) == errAuthorizationSuccess,
              let auth = authRef else {
            logger.error("AuthorizationCreate failed")
            return false
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }

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

        typealias AuthExecFn = @convention(c) (
            AuthorizationRef,
            UnsafePointer<CChar>,
            AuthorizationFlags,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
            UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
        ) -> OSStatus

        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, "AuthorizationExecuteWithPrivileges") else {
            logger.error("AuthorizationExecuteWithPrivileges symbol not found")
            return false
        }
        let authExec = unsafeBitCast(sym, to: AuthExecFn.self)

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
