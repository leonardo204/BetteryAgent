import AppKit
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

/// Sparkle 프레임워크를 통한 자동 업데이트 관리
///
/// Sparkle 미설치 환경에서도 컴파일되도록 #if canImport(Sparkle) 로 감싼다.
/// Xcode에서 Sparkle SPM 패키지를 추가한 후 전체 기능이 활성화된다.
@MainActor
final class UpdateChecker: ObservableObject {

#if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    /// 자동 업데이트 확인 주기 활성화 여부
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }
#else
    // Sparkle 미설치 — 스텁 구현
    init() {}

    func checkForUpdates() {
        // Sparkle 미설치 상태에서는 GitHub 릴리스 페이지를 브라우저로 열어 안내
        if let url = URL(string: "https://github.com/leonardo204/BetteryAgent/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    var canCheckForUpdates: Bool { true }

    var automaticallyChecksForUpdates: Bool {
        get { false }
        set { _ = newValue }
    }
#endif
}
