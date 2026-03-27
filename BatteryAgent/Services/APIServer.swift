import Foundation
import os.log

/// Thread-safe box for passing [String: Any] between dispatch queues.
private final class ResultBox: @unchecked Sendable {
    var value: [String: Any] = ["error": "Not found", "code": 404]
}

final class APIServer: @unchecked Sendable {
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private weak var viewModel: BatteryViewModel?
    private let logger = Logger(subsystem: Constants.appBundleIdentifier, category: "APIServer")
    var port: UInt16 = 18080

    @MainActor
    func start(viewModel: BatteryViewModel) {
        guard !isRunning else { return }
        self.viewModel = viewModel
        let port = self.port
        DispatchQueue.global(qos: .utility).async { [self] in
            self.runServer(port: port)
        }
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            Darwin.close(serverSocket)
            serverSocket = -1
        }
    }

    private func runServer(port: UInt16) {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            logger.error("Failed to create socket")
            return
        }

        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            logger.error("Bind failed: \(String(cString: strerror(errno)))")
            return
        }

        guard Darwin.listen(serverSocket, 10) == 0 else {
            logger.error("Listen failed")
            return
        }

        isRunning = true
        logger.info("API server listening on localhost:\(port)")

        while isRunning {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverSocket, sockPtr, &clientLen)
                }
            }
            guard client >= 0 else { continue }

            DispatchQueue.global(qos: .userInitiated).async { [self] in
                self.handleClient(client)
            }
        }
    }

    private func handleClient(_ client: Int32) {
        defer { Darwin.close(client) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = read(client, &buffer, buffer.count - 1)
        guard bytesRead > 0 else { return }

        let requestStr = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""
        let lines = requestStr.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return }

        let method = String(parts[0])
        let path = String(parts[1])

        let bodyStr: String
        if let range = requestStr.range(of: "\r\n\r\n") {
            bodyStr = String(requestStr[range.upperBound...])
        } else {
            bodyStr = "{}"
        }

        // Dispatch to MainActor for ViewModel access
        let sem = DispatchSemaphore(value: 0)
        let resultBox = ResultBox()

        DispatchQueue.main.async { [weak self] in
            guard let self, let vm = self.viewModel, method == "POST" else {
                sem.signal()
                return
            }
            resultBox.value = self.route(path: path, body: bodyStr, viewModel: vm)
            sem.signal()
        }
        sem.wait()

        sendResponse(client: client, json: resultBox.value)
    }

    private func sendResponse(client: Int32, json: [String: Any]) {
        let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        let jsonStr = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"error\":\"serialize\"}"

        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(jsonStr.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        let response = header + jsonStr

        _ = response.withCString { ptr in
            Darwin.write(client, ptr, strlen(ptr))
        }
    }

    // MARK: - Router (called on main queue)

    @MainActor private func route(path: String, body: String, viewModel: BatteryViewModel) -> [String: Any] {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]

        switch path {
        case "/api/status":
            return statusResponse(viewModel: viewModel)
        case "/api/settings":
            return settingsResponse(json: json, viewModel: viewModel)
        case "/api/control":
            return controlResponse(json: json, viewModel: viewModel)
        case "/api/history":
            return historyResponse(json: json)
        case "/api/health":
            return healthResponse(viewModel: viewModel)
        default:
            return ["error": "Unknown endpoint: \(path)", "code": 404]
        }
    }

    @MainActor private func statusResponse(viewModel: BatteryViewModel) -> [String: Any] {
        let s = viewModel.batteryState
        return [
            "currentCharge": s.currentCharge,
            "isCharging": s.isCharging,
            "isPluggedIn": s.isPluggedIn,
            "maxCapacity": s.maxCapacity,
            "designCapacity": s.designCapacity,
            "cycleCount": s.cycleCount,
            "temperature": s.temperature,
            "voltage": s.voltage,
            "adapterWatts": s.adapterWatts,
            "timeRemaining": s.timeRemaining,
            "healthPercentage": s.healthPercentage,
            "chargeLimit": viewModel.chargeLimit,
            "dischargeFloor": viewModel.dischargeFloor,
            "rechargeThreshold": s.rechargeThreshold,
            "isManaging": viewModel.isManaging,
            "isForceDischarging": viewModel.isManaging && s.currentCharge > viewModel.chargeLimit
        ]
    }

    @MainActor private func settingsResponse(json: [String: Any], viewModel: BatteryViewModel) -> [String: Any] {
        let action = json["action"] as? String ?? "get"
        if action == "get" {
            return [
                "chargeLimit": viewModel.chargeLimit,
                "dischargeFloor": viewModel.dischargeFloor,
                "rechargeMode": viewModel.rechargeMode == .smart ? "smart" : "manual",
                "manualRechargeThreshold": viewModel.manualRechargeThreshold,
                "isManaging": viewModel.isManaging,
                "showPercentage": viewModel.showPercentage,
                "notifyOnComplete": viewModel.notifyOnComplete
            ]
        }

        var applied: [String: Any] = [:]
        if let v = json["chargeLimit"] as? Int, (20...100).contains(v) { viewModel.chargeLimit = v; applied["chargeLimit"] = v }
        if let v = json["dischargeFloor"] as? Int, (5...50).contains(v) { viewModel.dischargeFloor = v; applied["dischargeFloor"] = v }
        if let v = json["isManaging"] as? Bool { viewModel.isManaging = v; applied["isManaging"] = v }
        if let v = json["rechargeMode"] as? String { viewModel.rechargeMode = v == "manual" ? .manual : .smart; applied["rechargeMode"] = v }
        if let v = json["manualRechargeThreshold"] as? Int { viewModel.manualRechargeThreshold = v; applied["manualRechargeThreshold"] = v }
        if let v = json["showPercentage"] as? Bool { viewModel.showPercentage = v; applied["showPercentage"] = v }
        if let v = json["notifyOnComplete"] as? Bool { viewModel.notifyOnComplete = v; applied["notifyOnComplete"] = v }
        return ["ok": true, "applied": applied]
    }

    @MainActor private func controlResponse(json: [String: Any], viewModel: BatteryViewModel) -> [String: Any] {
        guard let command = json["command"] as? String else {
            return ["error": "Missing 'command'", "code": 400]
        }
        switch command {
        case "enable-charging": SMCClient.shared.enableCharging { _ in }
        case "disable-charging": SMCClient.shared.disableCharging { _ in }
        case "force-discharge": SMCClient.shared.setForceDischarge(true) { _ in }
        case "stop-force-discharge", "stop-discharge": SMCClient.shared.setForceDischarge(false) { _ in }
        case "toggle-managing": viewModel.isManaging.toggle()
        case "enable-managing": viewModel.isManaging = true
        case "disable-managing": viewModel.isManaging = false
        default: return ["error": "Unknown command: \(command)", "code": 400]
        }
        return ["ok": true, "command": command]
    }

    private func historyResponse(json: [String: Any]) -> [String: Any] {
        let hours = json["hours"] as? Int ?? 24
        let records = ChargeHistoryStore.shared.fetchRecords(hours: min(hours, 168))
        let fmt = ISO8601DateFormatter()
        let dicts: [[String: Any]] = records.map { [
            "timestamp": fmt.string(from: $0.timestamp),
            "charge": $0.charge,
            "isCharging": $0.isCharging,
            "isPluggedIn": $0.isPluggedIn
        ] }
        return ["records": dicts, "count": dicts.count]
    }

    @MainActor private func healthResponse(viewModel: BatteryViewModel) -> [String: Any] {
        let s = viewModel.batteryState
        let loss = max(0, s.designCapacity - s.maxCapacity)
        let estCycles: Int
        if s.cycleCount > 0 && loss > 0 {
            let perCycle = Double(loss) / Double(s.cycleCount)
            estCycles = perCycle > 0 ? Int(Double(s.maxCapacity) * 0.2 / perCycle) : 999
        } else {
            estCycles = 999
        }
        return [
            "healthPercentage": s.healthPercentage,
            "cycleCount": s.cycleCount,
            "maxCapacity": s.maxCapacity,
            "designCapacity": s.designCapacity,
            "temperature": s.temperature,
            "voltage": s.voltage,
            "capacityLossMah": loss,
            "estimatedCyclesRemaining": estCycles
        ]
    }
}
