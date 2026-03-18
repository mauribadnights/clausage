import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case history = "History"
    case planOptimizer = "Plan Optimizer"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .history: return "chart.line.uptrend.xyaxis"
        case .planOptimizer: return "dollarsign.circle"
        case .settings: return "gear"
        }
    }
}

struct MainWindowView: View {
    let usageService: UsageService
    let updateService: UpdateService
    let pricingService: PlanPricingService
    let appState: AppState

    @State private var selectedItem: SidebarItem = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch selectedItem {
            case .dashboard:
                DashboardView(usageService: usageService, appState: appState)
            case .history:
                HistoryView()
            case .planOptimizer:
                PlanOptimizerView(pricingService: pricingService)
            case .settings:
                SettingsView(usageService: usageService)
            }
        }
    }
}
