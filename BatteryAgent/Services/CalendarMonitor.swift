import AppKit
import EventKit
import os.log

@MainActor
final class CalendarMonitor {
    private let eventStore = EKEventStore()
    private let logger = Logger(subsystem: Constants.appBundleIdentifier, category: "CalendarMonitor")

    private(set) var isAuthorized = false
    private(set) var upcomingEvents: [UpcomingEvent] = []

    // AI 분류 결과 캐시 — key: "title|durationMinutes"
    private var classificationCache: [String: Bool] = [:]

    struct UpcomingEvent {
        let title: String
        let startDate: Date
        let endDate: Date
        let durationMinutes: Int
        let needsLaptop: Bool
    }

    // MARK: - 노트북 필요 여부 판단 키워드

    private static let laptopKeywords: [String] = [
        // 한국어
        "회의", "미팅", "스크럼", "스탠드업", "데모", "리뷰", "발표",
        "세미나", "워크숍", "교육", "강의", "면접", "인터뷰",
        "주간", "월간", "정기", "위클리", "데일리", "스프린트",
        "코드", "개발", "디자인", "기획", "브레인스토밍",
        "온라인", "화상", "줌", "팀즈", "슬랙",
        // English
        "meeting", "standup", "stand-up", "scrum", "demo", "review",
        "presentation", "seminar", "workshop", "training", "interview",
        "weekly", "daily", "monthly", "sprint", "retro", "retrospective",
        "sync", "1:1", "one-on-one", "kickoff", "brainstorm",
        "zoom", "teams", "slack", "webinar", "conference",
        "coding", "hackathon", "code review", "design review"
    ]

    // MARK: - Access

    func requestAccess() async -> Bool {
        let status = authorizationStatus
        logger.info("Calendar authorization status: \(String(describing: status))")

        switch status {
        case .fullAccess:
            isAuthorized = true
            return true
        case .denied, .restricted:
            isAuthorized = false
            return false
        case .notDetermined:
            return await requestWithActivation()
        @unknown default:
            isAuthorized = false
            return false
        }
    }

    private func requestWithActivation() async -> Bool {
        let previousPolicy = NSApp.activationPolicy()
        let needsPolicySwitch = previousPolicy == .accessory

        if needsPolicySwitch {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    continuation.resume()
                }
            }
        }

        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            isAuthorized = granted
            logger.info("Calendar access result: \(granted)")
            if needsPolicySwitch { restoreAccessoryPolicy() }
            return granted
        } catch {
            logger.error("Calendar access error: \(error.localizedDescription)")
            isAuthorized = false
            if needsPolicySwitch { restoreAccessoryPolicy() }
            return false
        }
    }

    private func restoreAccessoryPolicy() {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .settingsWindowNeedsFront, object: nil)
        }
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Fetch & Classify Events

    func fetchUpcomingEvents(leadMinutes: Int = 60) -> [UpcomingEvent] {
        guard isAuthorized || authorizationStatus == .fullAccess else { return [] }

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: 24, to: now)!

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endDate,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)
        logger.info("Calendar: found \(events.count) raw events in next 24h")

        let filtered = events
            .filter { !$0.isAllDay }
            .filter { event in
                let duration = event.endDate.timeIntervalSince(event.startDate) / 60
                return duration >= 30
            }

        // 분류: 캐시 → 키워드 필터링
        let classified = filtered.map { event -> UpcomingEvent in
            let title = event.title ?? ""
            let duration = Int(event.endDate.timeIntervalSince(event.startDate) / 60)
            let needsLaptop = classifyEvent(title: title, durationMinutes: duration)

            logger.info("  - \(title) | \(duration)min | needsLaptop=\(needsLaptop)")

            return UpcomingEvent(
                title: title,
                startDate: event.startDate,
                endDate: event.endDate,
                durationMinutes: duration,
                needsLaptop: needsLaptop
            )
        }

        // 노트북 필요 이벤트만 반환
        let laptopEvents = classified.filter { $0.needsLaptop }
        logger.info("Calendar: \(laptopEvents.count)/\(classified.count) events need laptop")

        // AI 미분류 이벤트: Claude 있으면 AI 요청, 없으면 키워드 결과를 캐싱
        let unclassified = classified.filter { classificationCache[$0.cacheKey] == nil }
        if !unclassified.isEmpty {
            if findClaudePath() != nil {
                requestAIClassification(events: unclassified)
            } else {
                // Claude 미설치 → 키워드 결과를 캐싱하여 매 폴링마다 재분류 방지
                for event in unclassified {
                    classificationCache[event.cacheKey] = event.needsLaptop
                }
            }
        }

        return laptopEvents
    }

    // MARK: - Event Classification

    /// 키워드 기반 분류 (폴백) — 캐시에 AI 결과 있으면 우선 사용
    private func classifyEvent(title: String, durationMinutes: Int) -> Bool {
        let cacheKey = "\(title)|\(durationMinutes)"

        // 1. AI 분류 캐시 확인
        if let cached = classificationCache[cacheKey] {
            return cached
        }

        // 2. 키워드 기반 분류 (폴백)
        return keywordClassify(title: title, durationMinutes: durationMinutes)
    }

    /// 키워드 기반: 제목에 노트북 관련 키워드 포함 OR 1시간 이상 이벤트
    private func keywordClassify(title: String, durationMinutes: Int) -> Bool {
        let lower = title.lowercased()

        // 키워드 매칭
        for keyword in Self.laptopKeywords {
            if lower.contains(keyword) {
                return true
            }
        }

        // 1시간 이상 이벤트는 노트북 필요로 간주
        if durationMinutes >= 60 {
            return true
        }

        return false
    }

    // MARK: - AI Classification (Async, Non-blocking)

    private var isClassifying = false

    /// Claude CLI로 이벤트 분류 요청 — 결과는 캐시에 저장, 다음 폴링에 반영
    private func requestAIClassification(events: [UpcomingEvent]) {
        guard !isClassifying else { return }
        guard let claudePath = findClaudePath() else { return }

        isClassifying = true

        let eventList = events.map { "- \"\($0.title)\" (\($0.durationMinutes)분)" }.joined(separator: "\n")

        let prompt = """
        다음 캘린더 이벤트 목록에서 노트북(맥북)을 사용해야 하는 이벤트를 분류해주세요.
        회의, 발표, 코드리뷰, 온라인 미팅 등은 노트북 필요.
        식사, 운동, 병원, 외출, 개인 일정 등은 노트북 불필요.

        이벤트 목록:
        \(eventList)

        반드시 JSON 배열로만 응답하세요 (설명 없이):
        [{"title": "이벤트 제목", "needsLaptop": true}, ...]
        """

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: claudePath)
            process.arguments = ["--print", "-p", prompt]

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe()

            // 30초 타임아웃
            var timedOut = false
            let timer = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                    timedOut = true
                }
            }

            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timer)
                process.waitUntilExit()
                timer.cancel()

                guard !timedOut, process.terminationStatus == 0 else {
                    DispatchQueue.main.async { self?.isClassifying = false }
                    return
                }

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outData, encoding: .utf8) ?? ""

                // JSON 파싱
                if let results = Self.parseClassificationResponse(output) {
                    DispatchQueue.main.async {
                        guard let self else { return }
                        for result in results {
                            // 매칭되는 이벤트 찾아서 캐시 업데이트
                            for event in events {
                                if event.title == result.title {
                                    self.classificationCache[event.cacheKey] = result.needsLaptop
                                    self.logger.info("AI classified: \"\(result.title)\" → needsLaptop=\(result.needsLaptop)")
                                }
                            }
                        }
                        self.isClassifying = false
                    }
                } else {
                    DispatchQueue.main.async { self?.isClassifying = false }
                }
            } catch {
                DispatchQueue.main.async { self?.isClassifying = false }
            }
        }
    }

    private struct ClassificationResult {
        let title: String
        let needsLaptop: Bool
    }

    private static func parseClassificationResponse(_ text: String) -> [ClassificationResult]? {
        // JSON 배열 추출
        let patterns = ["```json\\s*([\\s\\S]*?)```", "```\\s*([\\s\\S]*?)```", "(\\[[\\s\\S]*\\])"]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }

            let jsonStr = String(text[range])
            guard let data = jsonStr.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }

            return array.compactMap { dict in
                guard let title = dict["title"] as? String,
                      let needsLaptop = dict["needsLaptop"] as? Bool else { return nil }
                return ClassificationResult(title: title, needsLaptop: needsLaptop)
            }
        }
        return nil
    }

    // MARK: - Claude Path

    private func findClaudePath() -> String? {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let candidates = [
            home + "/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home + "/.claude/bin/claude"
        ]
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let full = "\(dir)/claude"
                if FileManager.default.isExecutableFile(atPath: full) { return full }
            }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Pre-charge Decision

    func shouldPreCharge(leadMinutes: Int) -> Date? {
        let events = fetchUpcomingEvents(leadMinutes: leadMinutes)
        let now = Date()

        for event in events {
            let chargeStartTime = event.startDate.addingTimeInterval(-Double(leadMinutes) * 60)
            if now >= chargeStartTime && now < event.startDate {
                return event.startDate
            }
        }
        return nil
    }
}

// MARK: - UpcomingEvent Cache Key

extension CalendarMonitor.UpcomingEvent {
    var cacheKey: String { "\(title)|\(durationMinutes)" }
}
