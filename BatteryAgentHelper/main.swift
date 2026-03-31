import Foundation

// BatteryAgentHelper - SMC control CLI tool
// Runs as root LaunchDaemon, listens for commands via Unix socket

let socketPath = "/tmp/BatteryAgentHelper.sock"
let helperVersion = "1.5.5"

func main() -> Int32 {
    guard CommandLine.arguments.count >= 2 else {
        fputs("Usage: BatteryAgentHelper <command>\n", stderr)
        fputs("Commands: daemon, enable-charging, disable-charging, enable-force-discharge, disable-force-discharge, status, install-daemon\n", stderr)
        return 1
    }

    let command = CommandLine.arguments[1]

    switch command {
    case "daemon":
        return runDaemon()
    case "install-daemon":
        return installDaemon()
    case "uninstall-daemon":
        return uninstallDaemon()
    default:
        return runDirectCommand(command)
    }
}

// MARK: - Direct Command (requires root)

func runDirectCommand(_ command: String) -> Int32 {
    let smc = SMCController()
    do {
        try smc.open()
        defer { smc.close() }

        switch command {
        case "enable-charging":
            try smc.enableCharging()
            let verifyKey = smc.keyExists("CHTE") ? "CHTE" : "CH0B"
            let bytes = try smc.readKey(verifyKey)
            fputs("INFO: \(verifyKey) = \(bytes.map { String(format: "0x%02X", $0) }.joined(separator: " "))\n", stderr)
            print("OK: Charging enabled")

        case "disable-charging":
            try smc.disableCharging()
            let verifyKey = smc.keyExists("CHTE") ? "CHTE" : "CH0B"
            let bytes = try smc.readKey(verifyKey)
            fputs("INFO: \(verifyKey) = \(bytes.map { String(format: "0x%02X", $0) }.joined(separator: " "))\n", stderr)
            print("OK: Charging disabled")

        case "enable-force-discharge":
            try smc.enableForceDischarge()
            print("OK: Force discharge enabled")

        case "disable-force-discharge":
            try smc.disableForceDischarge()
            print("OK: Force discharge disabled")

        case "status":
            var status: [String] = []
            let keysToProbe = [
                "CH0B", "CH0C", "CH0I", "CH0J",
                "CHTE", "CHIE", "CHBI",
                "BCLM", "F0Ac"
            ]
            for key in keysToProbe {
                if smc.keyExists(key) {
                    do {
                        let bytes = try smc.readKey(key)
                        let hex = bytes.map { String(format: "0x%02X", $0) }.joined(separator: " ")
                        let info = try smc.getKeyInfo(key)
                        status.append("\(key)(size=\(info.dataSize))=[\(hex)]")
                    } catch {
                        status.append("\(key)=read_error")
                    }
                }
            }
            print("OK: \(status.joined(separator: " "))")

        default:
            fputs("Unknown command: \(command)\n", stderr)
            return 1
        }
        return 0
    } catch {
        fputs("ERROR: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

// MARK: - Daemon Mode (Unix Socket Server)

func runDaemon() -> Int32 {
    fputs("BatteryAgentHelper daemon v\(helperVersion) starting...\n", stderr)

    // Remove old socket
    unlink(socketPath)

    // Create Unix socket
    let sock = socket(AF_UNIX, SOCK_STREAM, 0)
    guard sock >= 0 else {
        fputs("ERROR: Failed to create socket\n", stderr)
        return 1
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    socketPath.withCString { ptr in
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                _ = strcpy(dest, ptr)
            }
        }
    }

    let bindResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bindResult == 0 else {
        fputs("ERROR: Failed to bind socket: \(String(cString: strerror(errno)))\n", stderr)
        close(sock)
        return 1
    }

    // Restrict socket access to root and admin group only
    chmod(socketPath, 0o770)
    let adminGroup = "admin"
    adminGroup.withCString { groupName in
        if let grp = getgrnam(groupName) {
            chown(socketPath, 0, grp.pointee.gr_gid)
        }
    }

    guard listen(sock, 5) == 0 else {
        fputs("ERROR: Failed to listen\n", stderr)
        close(sock)
        return 1
    }

    fputs("Listening on \(socketPath)\n", stderr)

    // Open SMC once
    let smc = SMCController()
    do {
        try smc.open()
    } catch {
        fputs("ERROR: Failed to open SMC: \(error.localizedDescription)\n", stderr)
        close(sock)
        return 1
    }

    // Accept loop
    while true {
        var clientAddr = sockaddr_un()
        var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let client = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(sock, sockPtr, &clientLen)
            }
        }
        guard client >= 0 else { continue }

        // Read command
        var buffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = read(client, &buffer, 255)
        guard bytesRead > 0 else {
            close(client)
            continue
        }

        let cmd = String(bytes: buffer.prefix(bytesRead), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        fputs("Received command: \(cmd)\n", stderr)

        var response: String
        do {
            switch cmd {
            case "enable-charging":
                try smc.enableCharging()
                response = "OK"
            case "disable-charging":
                try smc.disableCharging()
                response = "OK"
            case "enable-force-discharge":
                try smc.enableForceDischarge()
                response = "OK"
            case "disable-force-discharge":
                try smc.disableForceDischarge()
                response = "OK"
            case "status":
                let chargingKey = smc.keyExists("CHTE") ? "CHTE" : "CH0B"
                let dischargeKey = smc.keyExists("CHIE") ? "CHIE" : "CH0I"
                let cb = try smc.readKey(chargingKey)
                let db = try smc.readKey(dischargeKey)
                let chargingDisabled = cb.first != 0x00
                let forceDischarge = db.first != 0x00
                response = "OK charging_disabled=\(chargingDisabled) force_discharge=\(forceDischarge)"
            case "ping":
                response = "OK pong"
            case "version":
                response = "OK \(helperVersion)"
            default:
                response = "ERROR unknown command"
            }
        } catch {
            response = "ERROR \(error.localizedDescription)"
        }

        // Send response
        response.withCString { ptr in
            _ = write(client, ptr, strlen(ptr))
        }
        close(client)
    }
}

// MARK: - Install/Uninstall Daemon

func installDaemon() -> Int32 {
    let src = CommandLine.arguments[0]
    let dst = "/usr/local/bin/BatteryAgentHelper"
    let plistPath = "/Library/LaunchDaemons/com.zerolive.BatteryAgentHelper.plist"

    do {
        // Copy binary — /bin/cp preserves code signature (extended attributes)
        if FileManager.default.fileExists(atPath: dst) {
            try FileManager.default.removeItem(atPath: dst)
        }
        let cpTask = Process()
        cpTask.executableURL = URL(fileURLWithPath: "/bin/cp")
        cpTask.arguments = [src, dst]
        try cpTask.run()
        cpTask.waitUntilExit()
        guard cpTask.terminationStatus == 0 else {
            fputs("ERROR: /bin/cp failed with status \(cpTask.terminationStatus)\n", stderr)
            return 1
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst)

        // Create LaunchDaemon plist
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.zerolive.BatteryAgentHelper</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(dst)</string>
                <string>daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>/tmp/BatteryAgentHelper.log</string>
        </dict>
        </plist>
        """
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)

        // Unload existing daemon (try both modern and legacy methods, suppress errors)
        let devNull = FileHandle(forWritingAtPath: "/dev/null")

        let bootoutTask = Process()
        bootoutTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootoutTask.arguments = ["bootout", "system/com.zerolive.BatteryAgentHelper"]
        bootoutTask.standardError = devNull
        bootoutTask.standardOutput = devNull
        try? bootoutTask.run()
        bootoutTask.waitUntilExit()

        // Legacy unload fallback
        let unloadTask = Process()
        unloadTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unloadTask.arguments = ["unload", plistPath]
        unloadTask.standardError = devNull
        unloadTask.standardOutput = devNull
        try? unloadTask.run()
        unloadTask.waitUntilExit()

        // Remove stale socket
        try? FileManager.default.removeItem(atPath: "/tmp/BatteryAgentHelper.sock")

        // Load daemon (modern method: bootstrap into system domain)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootstrap", "system", plistPath]
        try task.run()
        task.waitUntilExit()

        // Fallback to legacy load if bootstrap fails
        if task.terminationStatus != 0 {
            let legacyTask = Process()
            legacyTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            legacyTask.arguments = ["load", "-w", plistPath]
            try legacyTask.run()
            legacyTask.waitUntilExit()
        }

        print("OK: Daemon installed and started")
        return 0
    } catch {
        fputs("ERROR: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

func uninstallDaemon() -> Int32 {
    let plistPath = "/Library/LaunchDaemons/com.zerolive.BatteryAgentHelper.plist"
    let binPath = "/usr/local/bin/BatteryAgentHelper"

    // Modern bootout
    let bootoutTask = Process()
    bootoutTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    bootoutTask.arguments = ["bootout", "system/com.zerolive.BatteryAgentHelper"]
    try? bootoutTask.run()
    bootoutTask.waitUntilExit()

    // Legacy fallback
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["unload", plistPath]
    try? task.run()
    task.waitUntilExit()

    try? FileManager.default.removeItem(atPath: plistPath)
    try? FileManager.default.removeItem(atPath: binPath)
    unlink(socketPath)

    print("OK: Daemon uninstalled")
    return 0
}

exit(main())
