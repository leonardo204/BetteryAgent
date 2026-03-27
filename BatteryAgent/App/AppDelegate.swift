import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var viewModel: BatteryViewModel?
    private var settingsWindow: NSWindow?
    private var iconUpdateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let vm = BatteryViewModel()
        self.viewModel = vm
        setupStatusItem()
        setupPopover(viewModel: vm)
        startIconUpdates()
        updateStatusBar()

        NotificationCenter.default.addObserver(
            forName: .statusBarNeedsUpdate, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusBar()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "battery.75percent",
                accessibilityDescription: "BatteryAgent"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover(viewModel: BatteryViewModel) {
        let p = NSPopover()
        let contentView = PopoverView(
            viewModel: viewModel,
            onOpenSettings: { [weak self] in
                self?.openSettings(tab: 0)
            },
            onOpenAISettings: { [weak self] in
                self?.openSettings(tab: 0)
            }
        )
        p.contentSize = NSSize(width: 320, height: 220)
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: contentView)
        self.popover = p
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
            updateStatusBar()
        } else {
            viewModel?.updateBatteryState()
            updateStatusBar()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
        }
    }

    func openSettings(tab: Int = 0) {
        popover?.performClose(nil)

        guard let vm = viewModel else { return }

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            // 탭 전환을 위해 뷰 모델을 통해 알림 전달
            NotificationCenter.default.post(
                name: .settingsTabSelected,
                object: tab
            )
            return
        }

        let settingsView = SettingsContainerView(viewModel: vm, initialTab: tab)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "BatteryAgent 설정"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        self.settingsWindow = window
    }

    private func startIconUpdates() {
        iconUpdateTimer?.invalidate()
        iconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusBar()
            }
        }
    }

    private func updateStatusBar() {
        guard let vm = viewModel else { return }
        let displayState: BatteryDisplayState
        if vm.isManaging && vm.batteryState.currentCharge > vm.chargeLimit {
            displayState = .forceDischarging
        } else if vm.batteryState.isCharging {
            displayState = .charging
        } else if vm.batteryState.isPluggedIn || vm.batteryState.adapterWatts > 0 {
            displayState = .pluggedIn
        } else {
            displayState = .onBattery
        }
        let iconName = MenuBarIconProvider.iconName(
            for: vm.batteryState.currentCharge,
            state: displayState
        )
        statusItem?.button?.image = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: "BatteryAgent"
        )
        if vm.showPercentage {
            statusItem?.button?.title = " \(vm.batteryState.currentCharge)%"
        } else {
            statusItem?.button?.title = ""
        }
    }
}
