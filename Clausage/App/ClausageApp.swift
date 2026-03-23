import SwiftUI
import SwiftData

@main
struct ClausageApp: App {
    @State private var appState = AppState()
    @State private var usageService = UsageService()
    @State private var updateService = UpdateService()
    @State private var pricingService = PlanPricingService()

    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: UsageSnapshot.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(
                appState: appState,
                usageService: usageService,
                updateService: updateService
            )
            .task {
                usageService.setModelContainer(modelContainer)
                appState.bindUsage(usageService)
            }
        } label: {
            Image(nsImage: appState.menuBarImage)
        }
        .menuBarExtraStyle(.window)

        Window("Clausage", id: "main") {
            MainWindowView(
                usageService: usageService,
                updateService: updateService,
                pricingService: pricingService,
                appState: appState
            )
            .modelContainer(modelContainer)
            .onAppear {
                // Defer to avoid tearing down MenuBarExtra panel mid-gesture
                DispatchQueue.main.async {
                    NSApp.setActivationPolicy(.regular)
                }
            }
            .onDisappear {
                // Small delay to avoid flicker if reopening immediately
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !NSApp.windows.contains(where: { $0.isVisible && $0.title == "Clausage" }) {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }
        .defaultSize(width: 800, height: 560)
    }
}
