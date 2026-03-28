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
    @State private var showErrorDetail = false
    @State private var errorDetail = ""

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
                    if let path = claudePath {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("감지 안됨")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if claudePath == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Claude Code가 설치되어 있지 않거나 경로를 찾을 수 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("npm install -g @anthropic-ai/claude-code")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }

                HStack {
                    // 자동 감지 버튼
                    Button {
                        claudePath = findClaudePath()
                        if claudePath != nil { checkConnection() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                            Text("자동 감지")
                        }
                    }
                    .controlSize(.small)

                    // 직접 찾기 버튼
                    Button {
                        browseForClaude()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("찾아보기")
                        }
                    }
                    .controlSize(.small)
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

                    // 에러 시 상세 보기 버튼
                    if case .disconnected = connectionStatus {
                        Button {
                            showErrorDetail = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.borderless)
                        .help("에러 상세 보기")
                    }
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
            // 저장된 경로 먼저 확인
            if let saved = UserDefaults.standard.string(forKey: "claudeCodePath"),
               FileManager.default.isExecutableFile(atPath: saved) {
                claudePath = saved
            } else {
                claudePath = findClaudePath()
            }
            if claudePath != nil, case .unknown = connectionStatus { checkConnection() }
        }
        .alert("연결 오류 상세", isPresented: $showErrorDetail) {
            Button("확인", role: .cancel) {}
            Button("복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(errorDetail, forType: .string)
            }
        } message: {
            Text(errorDetail)
        }
    }

    // MARK: - 파일 찾기 (NSOpenPanel)

    private func browseForClaude() {
        let panel = NSOpenPanel()
        panel.title = "Claude Code 실행 파일 선택"
        panel.message = "claude 실행 파일을 선택하세요 (보통 ~/.local/bin/claude)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true

        // 기본 경로 설정
        let home = FileManager.default.homeDirectoryForCurrentUser
        panel.directoryURL = home.appendingPathComponent(".local/bin")

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            // 실행 가능한 파일인지 확인
            if FileManager.default.isExecutableFile(atPath: path) {
                claudePath = path
                UserDefaults.standard.set(path, forKey: "claudeCodePath")
                checkConnection()
            } else {
                errorDetail = """
                선택한 파일을 실행할 수 없습니다.

                경로: \(path)

                확인 사항:
                • 실행 권한이 있는지 확인 (chmod +x \(path))
                • claude 바이너리가 맞는지 확인
                """
                showErrorDetail = true
            }
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
            // 1단계: 파일 존재 및 실행 가능 여부
            guard FileManager.default.isExecutableFile(atPath: path) else {
                DispatchQueue.main.async {
                    isCheckingConnection = false
                    let detail = """
                    Claude Code 실행 파일을 찾을 수 없습니다.

                    경로: \(path)

                    해결 방법:
                    1. 터미널에서 'which claude'로 경로 확인
                    2. '찾아보기' 버튼으로 직접 선택
                    3. Claude Code 미설치 시:
                       npm install -g @anthropic-ai/claude-code
                    """
                    errorDetail = detail
                    connectionStatus = .disconnected("실행 파일 없음")
                }
                return
            }

            // 2단계: 실행 테스트
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--print", "-p", "Reply with only your model name (e.g. claude-opus-4-6)."]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()

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
                let output = (String(data: outData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = (String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                DispatchQueue.main.async {
                    isCheckingConnection = false

                    if timedOut {
                        errorDetail = """
                        연결 시간 초과 (30초)

                        가능한 원인:
                        • 네트워크 연결 불안정
                        • Anthropic API 서버 응답 지연
                        • 방화벽/프록시가 API 요청을 차단

                        해결 방법:
                        1. 인터넷 연결 확인
                        2. 터미널에서 'claude --version' 실행
                        3. VPN/프록시 사용 시 해제 후 재시도
                        """
                        connectionStatus = .disconnected("타임아웃 (30초)")
                        return
                    }

                    if process.terminationStatus == 0 {
                        let modelName = output.isEmpty ? "claude" : output.components(separatedBy: .newlines).last ?? "claude"
                        connectionStatus = .connected(modelName)
                        // 성공한 경로 저장
                        UserDefaults.standard.set(path, forKey: "claudeCodePath")
                        return
                    }

                    // 에러 분석
                    let combined = errMsg.lowercased()
                    let (reason, detail) = analyzeError(combined: combined, errMsg: errMsg, exitCode: process.terminationStatus)
                    errorDetail = detail
                    connectionStatus = .disconnected(reason)
                }
            } catch {
                DispatchQueue.main.async {
                    isCheckingConnection = false
                    errorDetail = """
                    프로세스 실행 실패

                    경로: \(path)
                    오류: \(error.localizedDescription)

                    해결 방법:
                    1. 터미널에서 '\(path) --version' 실행 가능한지 확인
                    2. '찾아보기' 버튼으로 올바른 경로 선택
                    3. 실행 권한 확인: chmod +x \(path)
                    """
                    connectionStatus = .disconnected("실행 실패")
                }
            }
        }
    }

    // MARK: - 에러 분석

    private func analyzeError(combined: String, errMsg: String, exitCode: Int32) -> (reason: String, detail: String) {
        if combined.contains("authentication") || combined.contains("auth")
            || combined.contains("not logged in") || combined.contains("login")
            || combined.contains("unauthenticated") {
            return (
                "로그인 필요",
                """
                Claude Code에 로그인되어 있지 않습니다.

                해결 방법:
                1. 터미널을 열고 'claude' 입력
                2. 안내에 따라 로그인 (Anthropic 계정 또는 API 키)
                3. 로그인 완료 후 여기서 '연결 확인' 재시도

                원본 에러:
                \(errMsg)
                """
            )
        }

        if combined.contains("subscription") || combined.contains("pro")
            || combined.contains("max") || combined.contains("plan") {
            return (
                "구독 필요",
                """
                Claude Pro 또는 Max 구독이 필요합니다.

                Claude Code는 유료 구독(Pro/Max) 또는 API 키가 필요합니다.

                해결 방법:
                1. claude.ai에서 Pro/Max 구독
                2. 또는 API 키 사용: console.anthropic.com에서 발급

                원본 에러:
                \(errMsg)
                """
            )
        }

        if combined.contains("api key") || combined.contains("api_key")
            || combined.contains("invalid key") || combined.contains("invalid_api_key") {
            return (
                "API 키 오류",
                """
                API 키가 유효하지 않습니다.

                해결 방법:
                1. console.anthropic.com에서 API 키 확인
                2. 터미널에서 'claude' 실행 후 API 키 재설정
                3. 환경 변수 ANTHROPIC_API_KEY 확인

                원본 에러:
                \(errMsg)
                """
            )
        }

        if combined.contains("network") || combined.contains("connect")
            || combined.contains("timeout") || combined.contains("econnrefused")
            || combined.contains("dns") || combined.contains("fetch") {
            return (
                "네트워크 오류",
                """
                Anthropic API 서버에 연결할 수 없습니다.

                해결 방법:
                1. 인터넷 연결 확인
                2. VPN/프록시 사용 시 해제 후 재시도
                3. 방화벽에서 api.anthropic.com 허용
                4. 터미널에서 'curl https://api.anthropic.com' 테스트

                원본 에러:
                \(errMsg)
                """
            )
        }

        if combined.contains("rate limit") || combined.contains("429")
            || combined.contains("too many") {
            return (
                "요청 제한 초과",
                """
                API 요청 제한에 도달했습니다.

                해결 방법:
                1. 잠시 후 (1-2분) 재시도
                2. 다른 작업에서 Claude Code 사용 중이라면 완료 후 재시도

                원본 에러:
                \(errMsg)
                """
            )
        }

        if combined.contains("permission") || combined.contains("eacces") {
            return (
                "권한 오류",
                """
                Claude Code 실행 권한이 없습니다.

                해결 방법:
                터미널에서 실행:
                chmod +x \(claudePath ?? "claude")

                원본 에러:
                \(errMsg)
                """
            )
        }

        if combined.contains("not found") || combined.contains("enoent")
            || combined.contains("no such file") {
            return (
                "모듈 누락",
                """
                Claude Code의 일부 모듈을 찾을 수 없습니다.

                해결 방법:
                1. Claude Code 재설치:
                   npm uninstall -g @anthropic-ai/claude-code
                   npm install -g @anthropic-ai/claude-code
                2. Node.js 버전 확인: node --version (18+ 필요)

                원본 에러:
                \(errMsg)
                """
            )
        }

        // 알 수 없는 에러
        return (
            errMsg.isEmpty ? "알 수 없는 오류 (종료 코드: \(exitCode))" : String(errMsg.prefix(60)),
            """
            예기치 않은 오류가 발생했습니다.

            종료 코드: \(exitCode)

            해결 방법:
            1. 터미널에서 'claude --version' 실행
            2. 'claude --print -p "hello"' 직접 테스트
            3. Claude Code 재설치: npm install -g @anthropic-ai/claude-code

            \(errMsg.isEmpty ? "에러 메시지 없음" : "원본 에러:\n\(errMsg)")
            """
        )
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
            process.arguments = ["--print", "-p", prompt]

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
