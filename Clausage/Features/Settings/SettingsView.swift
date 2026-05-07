import SwiftUI
import SwiftData

struct SettingsView: View {
    let usageService: UsageService
    let codexUsageService: CodexUsageService
    let updateService: UpdateService
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AccountSection(usageService: usageService)
                CodexAccountSection(settings: settings, codexUsageService: codexUsageService)
                MenuBarSettingsSection(settings: settings)
                ColorSettingsSection(settings: settings)
                DataSettingsSection(settings: settings, usageService: usageService)
                RemoteHistorySection(settings: settings, usageService: usageService)
                #if DEBUG
                DebugSection()
                #endif
                AboutSection(updateService: updateService)
            }
            .padding(24)
        }
        .navigationTitle("Settings")
    }
}

private struct CodexAccountSection: View {
    @Bindable var settings: AppSettings
    let codexUsageService: CodexUsageService
    @State private var probeStatus: String?

    var body: some View {
        GroupBox("OpenAI Codex") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("Show Codex usage on Dashboard", isOn: $settings.showCodexUsage)
                        .toggleStyle(.switch)
                    Spacer()
                }
                Text("Reads `~/.codex/auth.json` (managed by the Codex CLI). Clausage does not log you in to OpenAI itself — run `codex login` in a terminal if you haven't already.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                statusRow

                HStack {
                    Spacer()
                    Button("Refresh") {
                        codexUsageService.fetch()
                    }
                    .disabled(codexUsageService.isLoading)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch CodexAuthService.load() {
        case .success(let creds):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex credentials found")
                        .font(.subheadline.bold())
                    Text("Plan: \(creds.planType ?? "unknown") • Account \(creds.accountId.prefix(8))…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        case .failure(let err):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex unavailable")
                        .font(.subheadline.bold())
                    Text(err.errorDescription ?? "Unknown error")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }
}

private struct AccountSection: View {
    let usageService: UsageService
    @Bindable private var auth = AuthService.shared
    @State private var inFlight = false
    @State private var lastError: String?

    var body: some View {
        GroupBox("Account") {
            VStack(alignment: .leading, spacing: 12) {
                statusRow
                Divider()
                Text("Clausage stores its own OAuth tokens in `~/Library/Application Support/Clausage/oauth.json` and refreshes them on its own — no keychain prompts, no dependency on Claude Code being signed in.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                actionRow
                if let err = lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 10) {
            switch auth.state {
            case .signedIn(let source):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signed in to Anthropic")
                        .font(.subheadline.bold())
                    Text(sourceCaption(source))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .signedOut:
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundColor(.orange)
                Text("Not signed in")
                    .font(.subheadline.bold())
            case .signingIn:
                ProgressView().controlSize(.small)
                Text("Signing in… check your browser")
                    .font(.subheadline)
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign-in error")
                        .font(.subheadline.bold())
                    Text(msg).font(.caption).foregroundColor(.secondary)
                }
            case .unknown:
                ProgressView().controlSize(.small)
                Text("Checking credentials…")
                    .font(.subheadline)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            switch auth.state {
            case .signedIn:
                Button("Sign out", role: .destructive) {
                    auth.signOut()
                    usageService.fetch()
                }
                Spacer()
                Button("Re-sign in (browser)") {
                    Task { await runSignIn() }
                }
                .disabled(inFlight)
            case .signedOut, .error:
                Button {
                    Task { await runSignIn() }
                } label: {
                    Label("Sign in with Anthropic", systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
                .disabled(inFlight)

                Spacer()

                Button("Import from Claude Code") {
                    if auth.bootstrapFromClaudeCodeIfPossible() != nil {
                        lastError = nil
                        usageService.fetch()
                    } else {
                        lastError = "No Claude Code credentials found in your keychain."
                    }
                }
            case .signingIn:
                Button("Cancel") { /* no-op; closing browser tab effectively cancels */ }
                    .disabled(true)
                Spacer()
            case .unknown:
                Spacer()
            }
        }
    }

    private func runSignIn() async {
        inFlight = true
        lastError = nil
        do {
            try await auth.signInWithBrowser()
            usageService.fetch()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        inFlight = false
    }

    private func sourceCaption(_ source: StoredCredentials.Source) -> String {
        switch source {
        case .browser: return "Authenticated via Clausage's own OAuth flow."
        case .claudeCodeImport: return "Bootstrapped from Claude Code's keychain. Re-sign in via browser anytime to make Clausage fully independent."
        }
    }
}

#if DEBUG
private struct DebugSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var seedStatus: String?
    @State private var showConfirm = false
    @State private var pendingAction: (() -> Void)?

    var body: some View {
        GroupBox("Debug (dev only)") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Seed mock data to test History and Plan Optimizer. This replaces all existing data.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Usage Patterns")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Button("Heavy User") { confirmSeed { seedPattern(.heavyUser) } }
                        .buttonStyle(.bordered)
                    Button("Light User") { confirmSeed { seedPattern(.lightUser) } }
                        .buttonStyle(.bordered)
                    Button("Moderate") { confirmSeed { seedPattern(.moderate) } }
                        .buttonStyle(.bordered)
                    Button("Limit Hitter") { confirmSeed { seedPattern(.limitHitter) } }
                        .buttonStyle(.bordered)
                }

                Text("Duration")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Button("7 Days") { confirmSeed { seedDuration(7) } }
                        .buttonStyle(.bordered)
                    Button("30 Days") { confirmSeed { seedDuration(30) } }
                        .buttonStyle(.bordered)
                    Button("Clear History") { confirmSeed { clearData() } }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }

                if let status = seedStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
        .alert("Replace existing data?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) { pendingAction = nil }
            Button("Replace", role: .destructive) {
                pendingAction?()
                pendingAction = nil
            }
        } message: {
            Text("This will delete all existing usage history and replace it with mock data.")
        }
    }

    private func confirmSeed(_ action: @escaping () -> Void) {
        pendingAction = action
        showConfirm = true
    }

    private func seedPattern(_ pattern: MockDataSeeder.UsagePattern) {
        do {
            try MockDataSeeder.seedHistory(context: modelContext, days: 14, pattern: pattern)
            seedStatus = "Seeded 14 days of \(pattern.description) data."
        } catch {
            seedStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func seedDuration(_ days: Int) {
        do {
            try MockDataSeeder.seedHistory(context: modelContext, days: days, pattern: .moderate)
            seedStatus = "Seeded \(days) days of moderate usage data."
        } catch {
            seedStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func clearData() {
        do {
            try MockDataSeeder.clearHistory(context: modelContext)
            seedStatus = "History cleared."
        } catch {
            seedStatus = "Error: \(error.localizedDescription)"
        }
    }
}
#endif

private struct MenuBarSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        GroupBox("Menu Bar") {
            VStack(alignment: .leading, spacing: 12) {
                TimerFormatPicker(settings: settings)

                Grid(alignment: .leading, verticalSpacing: 10) {
                    GridRow {
                        Text("Show usage bars")
                        Spacer()
                        Toggle("", isOn: $settings.showUsageBars)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    GridRow {
                        Text("Text shadow")
                        Spacer()
                        Toggle("", isOn: $settings.showTextShadow)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    GridRow {
                        Text("Show promo timer")
                        Spacer()
                        Toggle("", isOn: $settings.showPromoTimer)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    GridRow {
                        Text("Show usage %")
                        Spacer()
                        Toggle("", isOn: $settings.showMenuBarPercent)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    if settings.showMenuBarPercent {
                        GridRow {
                            Text("Usage % source")
                            Spacer()
                            Picker("", selection: $settings.menuBarPercentSource) {
                                Text("5-hour").tag("5hour")
                                Text("Weekly").tag("weekly")
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                    }
                }

                Divider()

                MenuBarSizeControls(settings: settings)
            }
            .padding(8)
        }
    }
}

private struct MenuBarSizeControls: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sizes")
                .font(.subheadline.bold())

            Grid(alignment: .leading, verticalSpacing: 8) {
                GridRow {
                    Text("Text size")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $settings.menuBarFontSize, in: 8...14, step: 1)
                    Text("\(Int(settings.menuBarFontSize))pt")
                        .font(.caption.monospacedDigit())
                        .frame(width: 30)
                }
                GridRow {
                    Text("Bar width")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $settings.menuBarBarWidth, in: 20...60, step: 2)
                    Text("\(Int(settings.menuBarBarWidth))px")
                        .font(.caption.monospacedDigit())
                        .frame(width: 30)
                }
                GridRow {
                    Text("Bar height")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $settings.menuBarBarHeight, in: 1...5, step: 0.5)
                    Text("\(String(format: "%.1f", settings.menuBarBarHeight))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 30)
                }
            }
        }
    }
}

private struct TimerFormatPicker: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Timer format")
                .font(.subheadline.bold())

            HStack(spacing: 8) {
                ForEach(TimerFormat.allCases) { format in
                    FormatButton(format: format, isSelected: settings.timerFormat == format) {
                        settings.timerFormat = format
                    }
                }
            }
        }
    }
}

private struct FormatButton: View {
    let format: TimerFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(format.displayName)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ColorSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        GroupBox("Timer Colors") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Off-peak (2x)")
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: activeColorBinding(settings), supportsOpacity: false)
                        .labelsHidden()
                }
                HStack {
                    Text("Peak (1x)")
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: peakColorBinding(settings), supportsOpacity: false)
                        .labelsHidden()
                }
            }
            .padding(8)
        }
    }

    private func activeColorBinding(_ settings: AppSettings) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.activeColor.nsColor) },
            set: { newColor in
                if let c = NSColor(newColor).usingColorSpace(.sRGB) {
                    settings.activeColor = TimerColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
                }
            }
        )
    }

    private func peakColorBinding(_ settings: AppSettings) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.peakColor.nsColor) },
            set: { newColor in
                if let c = NSColor(newColor).usingColorSpace(.sRGB) {
                    settings.peakColor = TimerColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
                }
            }
        )
    }
}

private struct DataSettingsSection: View {
    @Bindable var settings: AppSettings
    let usageService: UsageService

    var body: some View {
        GroupBox("Data & Refresh") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Refresh interval")
                        .font(.subheadline.bold())
                    Spacer()
                    Picker("", selection: $settings.refreshInterval) {
                        Text("1 min").tag(TimeInterval(60))
                        Text("2 min").tag(TimeInterval(120))
                        Text("5 min").tag(TimeInterval(300))
                        Text("10 min").tag(TimeInterval(600))
                        Text("15 min").tag(TimeInterval(900))
                    }
                    .frame(width: 120)
                    .onChange(of: settings.refreshInterval) { _, _ in
                        usageService.updateRefreshInterval()
                    }
                }
            }
            .padding(8)
        }
    }
}

private struct RemoteHistorySection: View {
    @Bindable var settings: AppSettings
    let usageService: UsageService

    var body: some View {
        GroupBox("History Sync") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fill gaps in your history chart when your Mac was asleep, using snapshots from an always-on remote source (e.g. ThinkPad).")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Grid(alignment: .leading, verticalSpacing: 10) {
                    GridRow {
                        Text("Enable sync")
                        Spacer()
                        Toggle("", isOn: $settings.remoteHistoryEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                if settings.remoteHistoryEnabled {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Source URL")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextField("http://100.76.199.15:8199", text: $settings.remoteHistoryURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    HStack {
                        if let status = usageService.remoteHistorySyncStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundColor(status.hasPrefix("Error") ? .red : .secondary)
                        } else {
                            Text("Never synced this session")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            usageService.syncRemoteHistory()
                        } label: {
                            if usageService.isSyncingRemoteHistory {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.small)
                                    Text("Syncing…")
                                }
                            } else {
                                Text("Sync Now")
                            }
                        }
                        .disabled(usageService.isSyncingRemoteHistory || settings.remoteHistoryURL.isEmpty)
                    }
                }
            }
            .padding(8)
        }
    }
}

private struct AboutSection: View {
    let updateService: UpdateService

    var body: some View {
        GroupBox("About") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Clausage")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("v\(UpdateService.currentVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text("Track your Claude usage, get plan recommendations, and never miss a promo.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                HStack {
                    if let newVersion = updateService.updateAvailable {
                        Label("\(newVersion) available", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Spacer()
                        Button {
                            updateService.performUpdate()
                        } label: {
                            if updateService.isUpdating {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Updating...")
                            } else {
                                Text("Update Now")
                            }
                        }
                        .disabled(updateService.isUpdating)
                    } else {
                        if updateService.isChecking {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Label("Up to date", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Check for Updates") {
                            updateService.checkForUpdate()
                        }
                        .disabled(updateService.isChecking)
                    }
                }

                if let error = updateService.updateError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(8)
        }
    }
}
