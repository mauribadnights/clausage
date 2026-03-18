import SwiftUI
import SwiftData

struct PlanOptimizerView: View {
    let pricingService: PlanPricingService
    @Query(sort: \UsageSnapshot.timestamp, order: .forward) private var snapshots: [UsageSnapshot]
    @State private var selectedPlanId: String = AppSettings.shared.currentPlanId

    private var recommendation: PlanRecommendation? {
        pricingService.analyzeUsage(snapshots: snapshots, currentPlanId: selectedPlanId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current plan selector
                if let pricing = pricingService.pricing {
                    CurrentPlanSection(
                        plans: pricing.plans,
                        selectedPlanId: $selectedPlanId
                    )
                    .onChange(of: selectedPlanId) { _, newValue in
                        AppSettings.shared.currentPlanId = newValue
                    }
                }

                // Recommendation
                if let rec = recommendation {
                    RecommendationCard(recommendation: rec)
                }

                // Plan comparison table
                if let pricing = pricingService.pricing {
                    PlanComparisonTable(plans: pricing.plans, currentPlanId: selectedPlanId)

                    Divider()

                    // Token pricing reference
                    TokenPricingTable(pricing: pricing.tokenPricing)
                }

                // Pricing data info
                HStack {
                    if let lastUpdated = pricingService.pricing?.lastUpdated {
                        Text("Pricing data: \(lastUpdated)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Refresh Pricing") {
                        pricingService.fetchRemote()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(24)
        }
        .navigationTitle("Plan Optimizer")
    }
}

struct CurrentPlanSection: View {
    let plans: [PlanTier]
    @Binding var selectedPlanId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Current Plan")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(plans) { plan in
                    Button(action: { selectedPlanId = plan.id }) {
                        VStack(spacing: 4) {
                            Text(plan.name)
                                .font(.subheadline.bold())
                            Text("$\(Int(plan.monthlyPrice))/mo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedPlanId == plan.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedPlanId == plan.id ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct RecommendationCard: View {
    let recommendation: PlanRecommendation

    private var icon: String {
        switch recommendation.recommendation {
        case .upgrade: return "arrow.up.circle.fill"
        case .downgrade: return "arrow.down.circle.fill"
        case .stayPut: return "checkmark.circle.fill"
        case .insufficientData: return "hourglass.circle"
        }
    }

    private var iconColor: Color {
        switch recommendation.recommendation {
        case .upgrade: return .orange
        case .downgrade: return .green
        case .stayPut: return .blue
        case .insufficientData: return .secondary
        }
    }

    private var title: String {
        switch recommendation.recommendation {
        case .upgrade: return "Consider Upgrading"
        case .downgrade: return "You Could Save Money"
        case .stayPut: return "Your Plan Fits Well"
        case .insufficientData: return "Collecting Data..."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                    if let suggested = recommendation.suggestedPlan {
                        Text("\(recommendation.currentPlan.name) -> \(suggested.name)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            Text(recommendation.reasoning)
                .font(.callout)
                .foregroundColor(.secondary)

            if let avg5h = recommendation.avgFiveHourUsage,
               let avgWeekly = recommendation.avgWeeklyUsage {
                HStack(spacing: 20) {
                    Label("Avg 5h: \(Int(avg5h))%", systemImage: "clock")
                        .font(.caption)
                    Label("Avg weekly: \(Int(avgWeekly))%", systemImage: "calendar")
                        .font(.caption)
                    Label("Hit limit: \(recommendation.timesHitLimit)x", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(iconColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PlanComparisonTable: View {
    let plans: [PlanTier]
    let currentPlanId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan Comparison")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Plan").font(.caption.bold()).foregroundColor(.secondary)
                    Text("Price").font(.caption.bold()).foregroundColor(.secondary)
                    Text("Usage").font(.caption.bold()).foregroundColor(.secondary)
                    Text("$/unit").font(.caption.bold()).foregroundColor(.secondary)
                }

                Divider().gridCellColumns(4)

                ForEach(plans) { plan in
                    GridRow {
                        HStack(spacing: 4) {
                            Text(plan.name)
                                .font(.callout)
                            if plan.id == currentPlanId {
                                Text("(current)")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        Text(plan.monthlyPrice == 0 ? "Free" : "$\(Int(plan.monthlyPrice))/mo")
                            .font(.callout.monospacedDigit())
                        Text("\(plan.usageMultiplier, specifier: "%.0f")x")
                            .font(.callout.monospacedDigit())
                        if plan.monthlyPrice > 0 {
                            Text("$\(plan.monthlyPrice / plan.usageMultiplier, specifier: "%.2f")")
                                .font(.callout.monospacedDigit())
                                .foregroundColor(.secondary)
                        } else {
                            Text("\u{2014}")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                    .fontWeight(plan.id == currentPlanId ? .semibold : .regular)
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct TokenPricingTable: View {
    let pricing: [TokenPricing]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Token Pricing (per 1M tokens)")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Model").font(.caption.bold()).foregroundColor(.secondary)
                    Text("Input").font(.caption.bold()).foregroundColor(.secondary)
                    Text("Output").font(.caption.bold()).foregroundColor(.secondary)
                }

                Divider().gridCellColumns(3)

                ForEach(pricing) { token in
                    GridRow {
                        Text(token.displayName)
                            .font(.callout)
                        Text("$\(token.inputPerMillion, specifier: "%.2f")")
                            .font(.callout.monospacedDigit())
                        Text("$\(token.outputPerMillion, specifier: "%.2f")")
                            .font(.callout.monospacedDigit())
                    }
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
