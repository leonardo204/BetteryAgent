import SwiftUI
import Security

struct AITab: View {
    @Bindable var viewModel: BatteryViewModel
    @State private var apiEnabled: Bool = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.apiEnabled)
    @State private var apiPort: String = String(UserDefaults.standard.integer(forKey: Constants.UserDefaultsKey.apiPort).nonZeroOr(Int(Constants.defaultAPIPort)))
    @State private var connectionStatus: String = "확인 중..."

    // Claude API 설정
    @State private var claudeAPIKey: String = KeychainHelper.load(key: Constants.UserDefaultsKey.claudeAPIKey) ?? ""
    @State private var claudeAPIBase: String = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.claudeAPIBase) ?? ""
    @State private var claudeModel: String = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.claudeModel) ?? "claude-opus-4-5"

    // 분석 상태
    @State private var analysisResult: String = ""
    @State private var isAnalyzing = false
    @State private var isCopied = false

    // 추천 설정 파싱
    @State private var recommendedChargeLimit: Int? = nil
    @State private var showApplyRecommendation = false

    private let availableModels = [
        "claude-opus-4-5",
        "claude-sonnet-4-5",
        "claude-haiku-4-5"
    ]

    var body: some View {
        Form {
            Section("API 서버") {
                Toggle("API 서버 활성화", isOn: $apiEnabled)
                    .onChange(of: apiEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.apiEnabled)
                        NotificationCenter.default.post(name: .apiServerToggled, object: newValue)
                    }

                HStack {
                    Text("포트")
                    Spacer()
                    TextField("18080", text: $apiPort)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .onSubmit {
                            if let port = Int(apiPort), (1024...65535).contains(port) {
                                UserDefaults.standard.set(port, forKey: Constants.UserDefaultsKey.apiPort)
                            }
                        }
                }

                HStack {
                    Text("상태")
                    Spacer()
                    Circle()
                        .fill(apiEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(apiEnabled ? "실행 중 (localhost:\(apiPort))" : "중지됨")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section("Claude API 설정") {
                HStack {
                    Text("API Key")
                    Spacer()
                    SecureField("sk-ant-...", text: $claudeAPIKey)
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveClaudeAPIKey() }
                }

                HStack {
                    Text("Base URL")
                    Spacer()
                    TextField("https://api.anthropic.com", text: $claudeAPIBase)
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            UserDefaults.standard.set(claudeAPIBase, forKey: Constants.UserDefaultsKey.claudeAPIBase)
                        }
                }
                .help("기본값: https://api.anthropic.com (비워두면 기본값 사용)")

                HStack {
                    Text("모델")
                    Spacer()
                    Picker("", selection: $claudeModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .frame(width: 200)
                    .onChange(of: claudeModel) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.claudeModel)
                    }
                }

                Button("API Key 저장") {
                    saveClaudeAPIKey()
                }
                .controlSize(.small)
                .disabled(claudeAPIKey.isEmpty)
            }

            Section("Claude Code 연결") {
                HStack {
                    Text("MCP 서버")
                    Spacer()
                    Text(connectionStatus)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("설정 방법")
                        .font(.caption.bold())
                    Text("프로젝트 루트에 .mcp.json 추가:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("""
                    {
                      "mcpServers": {
                        "battery-agent": {
                          "command": "node",
                          "args": ["mcp-server/index.js"]
                        }
                      }
                    }
                    """)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(8)
                    .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))

                    Button("설정 복사") {
                        let config = """
                        {"mcpServers":{"battery-agent":{"command":"node","args":["mcp-server/index.js"]}}}
                        """
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(config, forType: .string)
                    }
                    .controlSize(.small)
                }
            }

            Section("AI 배터리 분석") {
                Button {
                    requestAIAnalysis()
                } label: {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                                .controlSize(.small)
                            Text("분석 중...")
                        } else {
                            Image(systemName: "brain")
                            Text("배터리 분석 요청")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(isAnalyzing || claudeAPIKey.isEmpty)
                .help(claudeAPIKey.isEmpty ? "Claude API Key를 먼저 입력하세요" : "AI로 배터리 상태를 분석합니다")

                if !analysisResult.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView {
                            Text(analysisResult)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                        .padding(8)
                        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                        HStack {
                            Button {
                                copyAnalysisResult()
                            } label: {
                                Label(isCopied ? "복사됨" : "결과 복사", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            }
                            .controlSize(.small)

                            Spacer()

                            if showApplyRecommendation, let limit = recommendedChargeLimit {
                                Button {
                                    applyRecommendedLimit(limit)
                                } label: {
                                    Label("충전 제한 \(limit)% 적용", systemImage: "checkmark.circle")
                                        .foregroundStyle(.green)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { checkConnection() }
    }

    // MARK: - Private

    private func saveClaudeAPIKey() {
        KeychainHelper.save(key: Constants.UserDefaultsKey.claudeAPIKey, value: claudeAPIKey)
    }

    private func copyAnalysisResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(analysisResult, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }

    private func applyRecommendedLimit(_ limit: Int) {
        viewModel.chargeLimit = limit
        showApplyRecommendation = false
    }

    private func checkConnection() {
        guard apiEnabled else {
            connectionStatus = "API 서버 비활성화"
            return
        }
        let mcpPath = Bundle.main.bundlePath
            .components(separatedBy: "/").dropLast(3).joined(separator: "/")
            + "/mcp-server/node_modules"
        if FileManager.default.fileExists(atPath: mcpPath) {
            connectionStatus = "준비됨"
        } else {
            connectionStatus = "npm install 필요 (mcp-server/)"
        }
    }

    private func requestAIAnalysis() {
        guard !claudeAPIKey.isEmpty else { return }
        isAnalyzing = true
        analysisResult = ""
        recommendedChargeLimit = nil
        showApplyRecommendation = false

        let port = apiPort
        let apiKey = claudeAPIKey
        let model = claudeModel.isEmpty ? "claude-opus-4-5" : claudeModel
        let baseURL = claudeAPIBase.isEmpty ? "https://api.anthropic.com" : claudeAPIBase

        DispatchQueue.global().async {
            // 로컬 API에서 데이터 수집
            let statusData = apiEnabled ? httpGet("http://localhost:\(port)/api/status") : nil
            let healthData = apiEnabled ? httpGet("http://localhost:\(port)/api/health") : nil

            // 배터리 데이터 구성
            let batteryInfo: String
            if let status = statusData, let health = healthData {
                let statusJSON = (try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                let healthJSON = (try? JSONSerialization.data(withJSONObject: health, options: [.prettyPrinted])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                batteryInfo = "## 현재 배터리 상태\n```json\n\(statusJSON)\n```\n\n## 배터리 건강도\n```json\n\(healthJSON)\n```"
            } else {
                // API 서버 없이 viewModel 데이터 사용
                DispatchQueue.main.async {
                    let s = viewModel.batteryState
                    let loss = max(0, s.designCapacity - s.maxCapacity)
                    let info = """
                    현재 충전량: \(s.currentCharge)%
                    충전 중: \(s.isCharging)
                    건강도: \(s.healthPercentage)%
                    사이클: \(s.cycleCount)회
                    설계 용량: \(s.designCapacity) mAh
                    현재 최대: \(s.maxCapacity) mAh
                    용량 손실: \(loss) mAh
                    온도: \(String(format: "%.1f", s.temperature))°C
                    충전 제한: \(viewModel.chargeLimit)%
                    관리 활성화: \(viewModel.isManaging)
                    """
                    sendToClaudeAPI(batteryInfo: info, apiKey: apiKey, model: model, baseURL: baseURL)
                }
                return
            }

            sendToClaudeAPI(batteryInfo: batteryInfo, apiKey: apiKey, model: model, baseURL: baseURL)
        }
    }

    private func sendToClaudeAPI(batteryInfo: String, apiKey: String, model: String, baseURL: String) {
        let prompt = """
        다음은 내 맥북 배터리 상태입니다. 배터리 건강도를 분석하고 최적 충전 설정을 추천해주세요.

        \(batteryInfo)

        다음 사항을 포함해 분석해주세요:
        1. 현재 배터리 건강도 평가
        2. 사용 패턴 분석 (가능한 경우)
        3. 권장 충전 제한값 (숫자만: "권장 충전 제한: XX%" 형식으로 반드시 포함)
        4. 배터리 수명 연장 팁
        """

        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            DispatchQueue.main.async {
                analysisResult = "잘못된 API URL입니다."
                isAnalyzing = false
            }
            return
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isAnalyzing = false

                if let error = error {
                    analysisResult = "오류: \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    analysisResult = "응답 파싱 실패"
                    return
                }

                if let errorMsg = json["error"] as? [String: Any],
                   let msg = errorMsg["message"] as? String {
                    analysisResult = "API 오류: \(msg)"
                    return
                }

                if let content = json["content"] as? [[String: Any]],
                   let firstBlock = content.first,
                   let text = firstBlock["text"] as? String {
                    analysisResult = text
                    parseRecommendedLimit(from: text)
                } else {
                    analysisResult = "응답에서 텍스트를 찾을 수 없습니다."
                }
            }
        }.resume()
    }

    private func parseRecommendedLimit(from text: String) {
        // "권장 충전 제한: 80%" 같은 패턴 파싱
        let patterns = [
            "권장 충전 제한: (\\d+)%",
            "충전 제한.*?(\\d+)%",
            "recommended.*?(\\d+)%"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text),
               let limit = Int(text[range]),
               (20...100).contains(limit) {
                recommendedChargeLimit = limit
                showApplyRecommendation = (limit != viewModel.chargeLimit)
                return
            }
        }
    }
}

// MARK: - HTTP Helpers

private func httpGet(_ urlString: String) -> [String: Any]? {
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
    request.timeoutInterval = 3

    var result: [String: Any]?
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, _, _ in
        if let data {
            result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        sem.signal()
    }.resume()
    sem.wait()
    return result
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int {
        self != 0 ? self : fallback
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Constants.appBundleIdentifier
        ]
        SecItemDelete(query as CFDictionary)
        if !value.isEmpty {
            var attrs = query
            attrs[kSecValueData as String] = data
            SecItemAdd(attrs as CFDictionary, nil)
        }
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Constants.appBundleIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}
