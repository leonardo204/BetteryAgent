import AppKit
import Foundation
import Sparkle
import os.log

/// Sparkle 프레임워크를 통한 자동 업데이트 관리
@MainActor
final class UpdateChecker: ObservableObject {

    private let logger = Logger(subsystem: "com.zerolive.BatteryAgent", category: "UpdateChecker")
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        logger.info("Sparkle initialized — feedURL: \(self.updaterController.updater.feedURL?.absoluteString ?? "nil")")
    }

    func checkForUpdates() {
        logger.info("checkForUpdates() — Sparkle UI")
        updaterController.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }
}
