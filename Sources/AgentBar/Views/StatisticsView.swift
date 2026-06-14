import SwiftUI

struct StatisticsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    kpis
                    chartSection
                    mixAndModels
                    notes
                }
                .padding(20)
            }
        }
        .background(.regularMaterial)
    }

    private var toolbar: some View {
        HStack {
            Text("AgentBar")
                .font(.title3.weight(.semibold))
            Spacer()
            Picker(L.text("range", store.language), selection: $store.selectedRange) {
                ForEach(UsageRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 620)
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L.text("refresh", store.language))
        }
        .padding(16)
    }

    private var kpis: some View {
        HStack(spacing: 12) {
            KPIPill(title: L.text("total_tokens", store.language), value: DisplayFormatters.tokenString(store.summary.totalTokens), tint: .blue)
            KPIPill(title: "Input", value: DisplayFormatters.tokenString(store.summary.inputTokens), tint: .cyan)
            KPIPill(title: "Output", value: DisplayFormatters.tokenString(store.summary.outputTokens), tint: .indigo)
            KPIPill(title: L.text("cost", store.language), value: DisplayFormatters.costString(store.summary.estimatedCostUSD), tint: .green)
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.text("statistics", store.language))
                .font(.headline)
            MiniStackedBars(bars: store.summary.dailyBars)
                .frame(height: 180)
            HStack {
                Label("Codex", systemImage: "square.fill").foregroundStyle(.blue)
                Label("Claude Code", systemImage: "square.fill").foregroundStyle(.purple)
                Spacer()
            }
            .font(.caption)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var mixAndModels: some View {
        HStack(alignment: .top, spacing: 12) {
            breakdown(title: L.text("service_mix", store.language), rows: store.summary.serviceBreakdown.map { ($0.key.rawValue, $0.value) })
            breakdown(title: L.text("model_detail", store.language), rows: store.summary.modelBreakdown.map { ($0.key, $0.value) })
        }
    }

    private func breakdown(title: String, rows: [(String, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(rows.sorted(by: { $0.1 > $1.1 }), id: \.0) { row in
                HStack {
                    Text(row.0)
                        .lineLimit(1)
                    Spacer()
                    Text(DisplayFormatters.tokenString(row.1))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if rows.isEmpty {
                Text("No rows")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.text("security", store.language))
                .font(.headline)
            ForEach(store.securityNotes, id: \.self) { note in
                Text(note.redactedForCredentialWords)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(L.text("empty_cost", store.language))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
