import SwiftUI
import SwiftData

struct PlanOptimizerView: View {
    let pricingService: PlanPricingService
    @Query(sort: \UsageSnapshot.timestamp, order: .forward) private var snapshots: [UsageSnapshot]
    @State private var selectedPlanId: String = AppSettings.shared.currentPlanId

    private var analysis: PlanAnalysis? {
        pricingService.analyzePlans(snapshots: snapshots, currentPlanId: selectedPlanId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current plan selector
                if let pricing = pricingService.pricing {
                    CurrentPlanSelector(
                        plans: pricing.plans,
                        selectedPlanId: $selectedPlanId
                    )
                    .onChange(of: selectedPlanId) { _, newValue in
                        AppSettings.shared.currentPlanId = newValue
                    }
                }

                if let analysis = analysis {
                    // Insight card
                    if !analysis.insight.isEmpty {
                        InsightCard(
                            insight: analysis.insight,
                            dataPoints: analysis.dataPoints,
                            dataDays: analysis.dataDays
                        )
                    }

                    // Plan projection table
                    if !analysis.projections.isEmpty {
                        PlanProjectionTable(
                            projections: analysis.projections,
                            currentPlanId: selectedPlanId
                        )
                    }
                }

                // Token pricing reference
                if let pricing = pricingService.pricing {
                    TokenPricingTable(pricing: pricing.tokenPricing)
                }

                // Disclaimer
                DisclaimerSection()

                // Pricing data info
                HStack {
                    if let lastUpdated = pricingService.pricing?.lastUpdated {
                        Text("Pricing data: \(lastUpdated)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if pricingService.pricing == nil {
                        Text("Loading pricing data...")
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

// MARK: - Current Plan Selector

struct CurrentPlanSelector: View {
    let plans: [PlanTier]
    @Binding var selectedPlanId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Current Plan")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(plans) { plan in
                    PlanButton(plan: plan, isSelected: selectedPlanId == plan.id) {
                        selectedPlanId = plan.id
                    }
                }
            }
        }
    }
}

private struct PlanButton: View {
    let plan: PlanTier
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Insight Card

struct InsightCard: View {
    let insight: String
    let dataPoints: Int
    let dataDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Analysis")
                    .font(.headline)
                Spacer()
                Text("\(dataPoints) samples over \(dataDays)d")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(insight)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(.yellow.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Plan Projection Table

struct PlanProjectionTable: View {
    let projections: [PlanProjection]
    let currentPlanId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan Comparison")
                .font(.headline)

            Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header
                GridRow {
                    Text("Plan").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Price").frame(maxWidth: .infinity)
                    Text("Avg 5h").frame(maxWidth: .infinity)
                    Text("Avg Wk").frame(maxWidth: .infinity)
                    Text("At 5h Limit").frame(maxWidth: .infinity)
                    Text("At Wk Limit").frame(maxWidth: .infinity)
                    Text("Headroom").frame(maxWidth: .infinity)
                }
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)

                Divider().gridCellColumns(7)

                // Rows
                ForEach(projections) { proj in
                    let isCurrent = proj.plan.id == currentPlanId

                    GridRow {
                        // Plan name
                        HStack(spacing: 4) {
                            Text(proj.plan.name)
                                .fontWeight(isCurrent ? .bold : .regular)
                            if isCurrent {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Price
                        Text(proj.plan.monthlyPrice == 0 ? "Free" : "$\(Int(proj.plan.monthlyPrice))")
                            .frame(maxWidth: .infinity)

                        // Avg 5h
                        Text("\(Int(proj.projectedAvg5h))%")
                            .foregroundColor(utilizationColor(proj.projectedAvg5h))
                            .frame(maxWidth: .infinity)

                        // Avg weekly
                        Text("\(Int(proj.projectedAvgWeekly))%")
                            .foregroundColor(utilizationColor(proj.projectedAvgWeekly))
                            .frame(maxWidth: .infinity)

                        // At 5h limit
                        Group {
                            if proj.pctTimeAt5hLimit < 1 {
                                Text("\u{2014}").foregroundColor(.secondary)
                            } else {
                                Text("\(Int(proj.pctTimeAt5hLimit))%").foregroundColor(limitColor(proj.pctTimeAt5hLimit))
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // At weekly limit
                        Group {
                            if proj.pctTimeAtWeeklyLimit < 1 {
                                Text("\u{2014}").foregroundColor(.secondary)
                            } else {
                                Text("\(Int(proj.pctTimeAtWeeklyLimit))%").foregroundColor(limitColor(proj.pctTimeAtWeeklyLimit))
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Headroom
                        Text(proj.headroom > 0 ? "+\(Int(proj.headroom))%" : "\(Int(proj.headroom))%")
                            .foregroundColor(proj.headroom > 20 ? .green : proj.headroom > 5 ? .orange : .red)
                            .frame(maxWidth: .infinity)
                    }
                    .font(.callout.monospacedDigit())
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(isCurrent ? Color.accentColor.opacity(0.04) : Color.clear)

                    Divider().gridCellColumns(7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func utilizationColor(_ pct: Double) -> Color {
        if pct < 50 { return .green }
        if pct < 75 { return .primary }
        if pct < 90 { return .orange }
        return .red
    }

    private func limitColor(_ pct: Double) -> Color {
        if pct < 15 { return .orange }
        return .red
    }
}

// MARK: - Token Pricing

struct TokenPricingTable: View {
    let pricing: [TokenPricing]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Token Pricing (per 1M tokens)")
                .font(.headline)

            Text("If supplementing rate-limited periods with API tokens, here's what each model costs:")
                .font(.caption)
                .foregroundColor(.secondary)

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

// MARK: - Disclaimer

struct DisclaimerSection: View {
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("About these projections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text("""
                Projections are based solely on the usage data Clausage has collected while running. \
                There may be gaps in the data — for instance, if the app wasn't running or the API was \
                temporarily unavailable — which can affect accuracy. Additionally, Anthropic may change \
                plan pricing, usage limits, or introduce new plans at any time, and there can be a delay \
                before Clausage reflects those changes.

                Plan projections estimate what your utilization would look like on each plan by scaling \
                your current usage relative to each plan's capacity multiplier. This is an approximation \
                — actual usage patterns may differ when limits change.

                These projections are meant as a helpful starting point, not a guarantee of the \
                cheapest or best option. Your actual workflow needs and how you value features like \
                higher rate limits are factors only you can weigh. We're constantly working to improve \
                our analysis, but the final decision is always yours.
                """)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(12)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
