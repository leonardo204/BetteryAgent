import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @Bindable var viewModel: BatteryViewModel
    var updateChecker: UpdateChecker
    @State private var launchAtLogin = false
    @State private var autoCheckUpdates = true

    var body: some View {
        Form {
            Section("표시") {
                Toggle("메뉴바에 % 표시", isOn: $viewModel.showPercentage)
            }

            Section("시작") {
                Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("업데이트") {
                Toggle("자동 업데이트 확인", isOn: $autoCheckUpdates)
                    .onChange(of: autoCheckUpdates) { _, newValue in
                        updateChecker.automaticallyChecksForUpdates = newValue
                    }

                Button("지금 업데이트 확인") {
                    updateChecker.checkForUpdates()
                }
                .disabled(!updateChecker.canCheckForUpdates)
                .frame(maxWidth: .infinity)
            }

            Section("정보") {
                HStack {
                    Text("버전")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("종료") {
                    NSApplication.shared.terminate(nil)
                }
                .frame(maxWidth: .infinity)
                .controlSize(.large)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            autoCheckUpdates = updateChecker.automaticallyChecksForUpdates
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enabled
        }
    }
}
