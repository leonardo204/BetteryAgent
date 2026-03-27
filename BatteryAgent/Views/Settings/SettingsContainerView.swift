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
                    Label("AI", systemImage: "brain")
                }
                .tag(0)

            ChargeControlTab(viewModel: viewModel)
                .tabItem {
                    Label("충전", systemImage: "bolt.fill")
                }
                .tag(1)

            BatteryInfoTab(viewModel: viewModel)
                .tabItem {
                    Label("배터리", systemImage: "battery.100percent")
                }
                .tag(2)

            HistoryTab()
                .tabItem {
                    Label("이력", systemImage: "chart.xyaxis.line")
                }
                .tag(3)

            CalibrationTab(viewModel: viewModel)
                .tabItem {
                    Label("캘리브레이션", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(4)

            GeneralTab(viewModel: viewModel)
                .tabItem {
                    Label("일반", systemImage: "gearshape")
                }
                .tag(5)
        }
        .frame(width: 480, height: 420)
        .padding(.top, 8)
        .onReceive(NotificationCenter.default.publisher(for: .settingsTabSelected)) { note in
            if let tab = note.object as? Int {
                selectedTab = tab
            }
        }
    }
}
