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

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    headerCell("Plan", width: 120, alignment: .leading)
                    headerCell("Price", width: 70)
                    headerCell("Avg 5h", width: 65)
                    headerCell("Avg Wk", width: 65)
                    headerCell("At 5h Limit", width: 80)
                    headerCell("At Wk Limit", width: 80)
                    headerCell("Headroom", width: 75)
                }
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))

                Divider()

                // Rows
                ForEach(projections) { proj in
                    PlanProjectionRow(projection: proj, isCurrent: proj.plan.id == currentPlanId)
                    Divider()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment = .center) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundColor(.secondary)
            .frame(width: width, alignment: alignment)
    }
}

struct PlanProjectionRow: View {
    let projection: PlanProjection
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Plan name
            HStack(spacing: 4) {
                Text(projection.plan.name)
                    .font(.callout)
                    .fontWeight(isCurrent ? .bold : .regular)
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
            .frame(width: 120, alignment: .leading)

            // Price
            Text(projection.plan.monthlyPrice == 0 ? "Free" : "$\(Int(projection.plan.monthlyPrice))")
                .font(.callout.monospacedDigit())
                .frame(width: 70)

            // Avg 5h utilization
            utilizationCell(projection.projectedAvg5h, width: 65)

            // Avg weekly utilization
            utilizationCell(projection.projectedAvgWeekly, width: 65)

            // Time at 5h limit
            limitCell(projection.pctTimeAt5hLimit, width: 80)

            // Time at weekly limit
            limitCell(projection.pctTimeAtWeeklyLimit, width: 80)

            // Headroom
            headroomCell(projection.headroom, width: 75)
        }
        .padding(.vertical, 8)
        .background(isCurrent ? Color.accentColor.opacity(0.04) : Color.clear)
    }

    private func utilizationCell(_ pct: Double, width: CGFloat) -> some View {
        Text("\(Int(pct))%")
            .font(.callout.monospacedDigit())
            .foregroundColor(utilizationColor(pct))
            .frame(width: width)
    }

    private func limitCell(_ pct: Double, width: CGFloat) -> some View {
        Group {
            if pct < 1 {
                Text("\u{2014}")
                    .foregroundColor(.secondary)
            } else {
                Text("\(Int(pct))%")
                    .foregroundColor(limitColor(pct))
            }
        }
        .font(.callout.monospacedDigit())
        .frame(width: width)
    }

    private func headroomCell(_ headroom: Double, width: CGFloat) -> some View {
        Text(headroom > 0 ? "+\(Int(headroom))%" : "\(Int(headroom))%")
            .font(.callout.monospacedDigit())
            .foregroundColor(headroom > 20 ? .green : headroom > 5 ? .orange : .red)
            .frame(width: width)
    }

    private func utilizationColor(_ pct: Double) -> Color {
        if pct < 50 { return .green }
        if pct < 75 { return .primary }
        if pct < 90 { return .orange }
        return .red
    }

    private func limitColor(_ pct: Double) -> Color {
        if pct < 5 { return .orange }
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
