import SwiftUI

struct SettingsContainerView: View {
    @Bindable var viewModel: BatteryViewModel
    @State private var selectedTab: Int

    init(viewModel: BatteryViewModel, initialTab: Int = 0) {
        self.viewModel = viewModel
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AITab(viewModel: viewModel)
                .tabItem {
                    Label("AI 분석 정보", systemImage: "brain")
                }
                .tag(0)

            SmartChargingTab(viewModel: viewModel)
                .tabItem {
                    Label("스마트 충전", systemImage: "brain.head.profile")
                }
                .tag(1)

            ChargeControlTab(viewModel: viewModel)
                .tabItem {
                    Label("일반 충전", systemImage: "bolt.fill")
                }
                .tag(2)

            HistoryTab()
                .tabItem {
                    Label("충전 이력", systemImage: "chart.xyaxis.line")
                }
                .tag(3)

            BatteryInfoTab(viewModel: viewModel)
                .tabItem {
                    Label("배터리 정보", systemImage: "battery.100percent")
                }
                .tag(4)

            CalibrationTab(viewModel: viewModel)
                .tabItem {
                    Label("캘리브레이션", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(5)

            GeneralTab(viewModel: viewModel)
                .tabItem {
                    Label("정보", systemImage: "gearshape")
                }
                .tag(6)
        }
        .frame(width: 560, height: 420)
        .padding(.top, 8)
        .onReceive(NotificationCenter.default.publisher(for: .settingsTabSelected)) { note in
            if let tab = note.object as? Int {
                selectedTab = tab
            }
        }
    }
}
