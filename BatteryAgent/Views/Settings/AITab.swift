import SwiftUI

struct AITab: View {
    @Bindable var viewModel: BatteryViewModel

    enum ConnectionStatus {
        case unknown, checking, connected(String), disconnected(String)
        var color: Color {
            switch self {
            case .connected: return .green
            case .disconnected: return .red
            case .checking: return .yellow
            case .unknown: return .gray
            }
        }
        var label: String {
            switch self {
            case .unknown: return "확인 안됨"
            case .checking: return "확인 중..."
            case .connected(let model): return "연결됨 (\(model))"
            case .disconnected(let reason): return reason
            }
        }
    }

    // Claude Code
    @State private var claudePath: String? = nil
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var isCheckingConnection = false

    // 분석 상태
    @State private var isAnalyzing = false
    @State private var report = ""
    @State private var isCopied = false

    struct AppliedSettings { var chargeLimit: Int }
    @State private var appliedSettings: AppliedSettings? = nil

    var body: some View {
        Form {
            Section("Claude Code") {
                HStack {
                    Text("claude 경로")
                    Spacer()
                    Text(claudePath ?? "감지 안됨")
                        .font(.caption)
                        .foregroundStyle(claudePath != nil ? Color.secondary : Color.red)
                }

                if claudePath == nil {
                    Text("npm install -g @anthropic-ai/claude-code")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.orange)
                }

                HStack {
                    Text("연결 상태")
                    Spacer()
                    Circle()
                        .fill(connectionStatus.color)
                        .frame(width: 8, height: 8)
                    Text(connectionStatus.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Button {
                    checkConnection()
                } label: {
                    HStack {
                        if isCheckingConnection {
                            ProgressView().controlSize(.small)
                            Text("연결 확인 중...")
                        } else {
                            Image(systemName: "network")
                            Text("연결 확인")
                        }
                    }
                }
                .controlSize(.small)
                .disabled(isCheckingConnection || claudePath == nil)
            }

            Section("AI 자동 설정") {
                Button {
                    requestAnalysis()
                } label: {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                                .controlSize(.small)
                            Text("Claude 분석 중...")
                        } else {
                            Image(systemName: "brain")
                            Text("AI 자동 설정")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(isAnalyzing || claudePath == nil || !isConnected)

                if !report.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("분석 결과")
                            .font(.caption.bold())
                        ScrollView {
                            Text(report)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                        .padding(8)
                        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                        HStack {
                            if let applied = appliedSettings {
                                Text("충전 제한 \(applied.chargeLimit)% 적용됨")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Button {
                                copyReport()
                            } label: {
                                Label(isCopied ? "복사됨" : "복사", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            claudePath = findClaudePath()
            if claudePath != nil { checkConnection() }
        }
    }

    // MARK: - 연결 확인

    private var isConnected: Bool {
        if case .connected = connectionStatus { return true }
        return false
    }

    private func checkConnection() {
        guard let path = claudePath else { return }
        isCheckingConnection = true
        connectionStatus = .checking

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            // --print -p 패턴으로 실제 API 인증 확인 (동작 확인된 패턴)
            process.arguments = ["--print", "-p", "Say 'OK' if you can hear me.", "--model", "claude-sonnet-4-6"]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()

                // 30초 타임아웃
                var timedOut = false
                let timer = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                        timedOut = true
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timer)
                process.waitUntilExit()
                timer.cancel()

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let _ = (String(data: outData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                DispatchQueue.main.async {
                    isCheckingConnection = false
                    if timedOut {
                        connectionStatus = .disconnected("타임아웃 (30초)")
                    } else if process.terminationStatus == 0 {
                        connectionStatus = .connected("claude-sonnet-4-6")
                    } else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = (String(data: errData, encoding: .utf8) ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        // 주요 오류 메시지 파싱 (참고: Rust/Tauri 동작 코드 기준)
                        let combined = errMsg.lowercased()
                        let reason: String
                        if combined.contains("authentication") || combined.contains("auth") || combined.contains("not logged in") || combined.contains("login") {
                            reason = "로그인 필요 — 터미널에서 'claude' 실행 후 로그인"
                        } else if combined.contains("subscription") || combined.contains("pro") || combined.contains("max") {
                            reason = "Claude Pro/Max 구독 필요"
                        } else if combined.contains("api key") || combined.contains("api_key") {
                            reason = "API 키 오류"
                        } else if combined.contains("network") || combined.contains("connect") || combined.contains("timeout") {
                            reason = "네트워크 오류"
                        } else if errMsg.isEmpty {
                            reason = "알 수 없는 오류"
                        } else {
                            reason = String(errMsg.prefix(80))
                        }
                        connectionStatus = .disconnected(reason)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isCheckingConnection = false
                    connectionStatus = .disconnected(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Claude 경로 감지

    private func findClaudePath() -> String? {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let candidates = [
            home + "/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home + "/.claude/bin/claude",
            "/usr/bin/claude"
        ]
        // PATH에서도 탐색
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let full = "\(dir)/claude"
                if FileManager.default.isExecutableFile(atPath: full) { return full }
            }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Process 실행

    private func runClaude(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let path = claudePath else {
            completion(.failure(NSError(
                domain: "",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "claude 명령어를 찾을 수 없습니다.\n설치: npm install -g @anthropic-ai/claude-code"]
            )))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--print", "-p", prompt, "--model", "claude-sonnet-4-6"]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    completion(.success(output))
                } else {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? "알 수 없는 오류"
                    completion(.failure(NSError(
                        domain: "",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: errMsg]
                    )))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - 프롬프트 구성

    private func buildPrompt() -> String {
        let s = viewModel.batteryState
        return """
        다음 맥북 배터리 상태를 분석하고 최적 충전 설정을 추천해주세요.

        ## 배터리 현재 상태
        {
          "currentCharge": \(s.currentCharge),
          "isCharging": \(s.isCharging),
          "isPluggedIn": \(s.isPluggedIn),
          "healthPercentage": \(s.healthPercentage),
          "cycleCount": \(s.cycleCount),
          "designCapacity": \(s.designCapacity),
          "maxCapacity": \(s.maxCapacity),
          "temperature": \(String(format: "%.1f", s.temperature)),
          "voltage": \(String(format: "%.3f", s.voltage)),
          "adapterWatts": \(s.adapterWatts)
        }

        ## 현재 설정
        {
          "chargeLimit": \(viewModel.chargeLimit),
          "dischargeFloor": \(viewModel.dischargeFloor),
          "isManaging": \(viewModel.isManaging),
          "rechargeMode": "\(viewModel.rechargeMode == .smart ? "smart" : "manual")"
        }

        반드시 아래 JSON 형식으로만 응답하세요 (설명 없이 JSON만):
        {
          "chargeLimit": 80,
          "dischargeFloor": 20,
          "isManaging": true,
          "rechargeMode": "smart",
          "report": "분석 내용과 추천 이유를 한국어로 작성"
        }
        """
    }

    // MARK: - JSON 추출

    private func extractJSON(from text: String) -> [String: Any]? {
        let patterns = ["```json\\s*([\\s\\S]*?)```", "```\\s*([\\s\\S]*?)```", "(\\{[\\s\\S]*\\})"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let jsonStr = String(text[range])
                if let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return json
                }
            }
        }
        return nil
    }

    // MARK: - 설정 적용

    private func applySettings(from json: [String: Any]) {
        if let v = json["chargeLimit"] as? Int, (20...100).contains(v) { viewModel.chargeLimit = v }
        if let v = json["dischargeFloor"] as? Int, (5...50).contains(v) { viewModel.dischargeFloor = v }
        if let v = json["isManaging"] as? Bool { viewModel.isManaging = v }
        if let v = json["rechargeMode"] as? String { viewModel.rechargeMode = v == "manual" ? .manual : .smart }
    }

    // MARK: - 분석 요청

    private func requestAnalysis() {
        isAnalyzing = true
        report = ""
        appliedSettings = nil

        let prompt = buildPrompt()

        runClaude(prompt: prompt) { result in
            DispatchQueue.main.async {
                isAnalyzing = false
                switch result {
                case .success(let output):
                    if let json = extractJSON(from: output) {
                        applySettings(from: json)
                        report = (json["report"] as? String) ?? output
                        appliedSettings = AppliedSettings(chargeLimit: viewModel.chargeLimit)
                    } else {
                        report = output
                    }
                case .failure(let error):
                    report = "오류: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 결과 복사

    private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
}

