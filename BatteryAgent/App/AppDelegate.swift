import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var viewModel: BatteryViewModel?
    private var settingsWindow: NSWindow?
    private var iconUpdateTimer: Timer?
    private var eventMonitor: Any?
    private var localKeyMonitor: Any?
    private var updateChecker: UpdateChecker?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let vm = BatteryViewModel()
        self.viewModel = vm
        updateChecker = UpdateChecker()
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

        NotificationCenter.default.addObserver(
            forName: .settingsWindowNeedsFront, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if let window = self?.settingsWindow {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    NSApp.activate(ignoringOtherApps: true)
                }
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
            button.imagePosition = .imageLeading
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
            closePopover()
        } else {
            viewModel?.updateBatteryState()
            updateStatusBar()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
            startEventMonitor()
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        updateStatusBar()
        stopEventMonitor()
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
                self?.openSettings(tab: 0)
                return nil
            }
            return event
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    func openSettings(tab: Int = 0) {
        popover?.performClose(nil)

        guard let vm = viewModel else { return }

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
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
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.level = .normal
        NSApp.activate(ignoringOtherApps: true)

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
        let plugged = vm.batteryState.isPluggedIn || vm.batteryState.adapterWatts > 0
        let displayState: BatteryDisplayState
        if !plugged && !vm.batteryState.isCharging {
            displayState = .onBattery
        } else if vm.isManaging && vm.batteryState.currentCharge > vm.chargeLimit {
            displayState = .pluggedIn  // 충전 차단만, AC 모드 유지
        } else if vm.smartChargingStatus.isSmartCharging && vm.batteryState.isCharging {
            displayState = .smartCharging
        } else if vm.batteryState.isCharging {
            displayState = .charging
        } else if plugged {
            displayState = .pluggedIn
        } else {
            displayState = .onBattery
        }
        statusItem?.button?.image = MenuBarIconProvider.statusBarImage(
            for: vm.batteryState.currentCharge,
            state: displayState
        )
        if displayState == .smartCharging {
            statusItem?.button?.contentTintColor = .orange
        } else {
            statusItem?.button?.contentTintColor = nil
        }
        if vm.showPercentage {
            statusItem?.button?.title = " \(vm.batteryState.currentCharge)%"
        } else {
            statusItem?.button?.title = ""
        }
    }
}
