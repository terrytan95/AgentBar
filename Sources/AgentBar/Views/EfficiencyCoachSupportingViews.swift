import SwiftUI

struct EfficiencySmartNudgeCard: View {
    var nudge: TokenEfficiencyNudge
    var language: AppLanguage
    var onDismiss: () -> Void
    var onOpen: () -> Void

    init(
        nudge: TokenEfficiencyNudge,
        language: AppLanguage,
        onDismiss: @escaping () -> Void,
        onOpen: @escaping () -> Void
    ) {
        self.nudge = nudge
        self.language = language
        self.onDismiss = onDismiss
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(AgentBarPalette.primary.opacity(0.14), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(1, nudge.contextOccupancyRatio))
                        .stroke(AgentBarPalette.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(nudge.contextOccupancyRatio * 100))%")
                        .font(.agentBarMono(size: 12, weight: .bold))
                        .foregroundStyle(AgentBarPalette.primary)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(
                        format: efficiencySupportingText("context_at", language),
                        Int(nudge.contextOccupancyRatio * 100)
                    ))
                    .font(.agentBar(size: 14, weight: .bold))
                    Text(efficiencySupportingText("fresh_task_suggestion", language))
                        .font(.agentBar(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.agentBar(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .tactilePlainButton()
                .accessibilityLabel(efficiencySupportingText("dismiss", language))
            }

            Button(action: onOpen) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                    Text(efficiencySupportingText("open_efficiency_coach", language))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.agentBar(size: 11, weight: .bold))
                .foregroundStyle(AgentBarPalette.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(AgentBarPalette.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }
            .tactilePlainButton()
        }
        .padding(14)
        .agentBarPanel(cornerRadius: 12)
    }
}

private func efficiencySupportingText(_ key: String, _ language: AppLanguage) -> String {
    let english = [
        "context_at": "Context at %d%%",
        "dismiss": "Dismiss",
        "fresh_task_suggestion": "Consider a fresh task after this checkpoint.",
        "open_efficiency_coach": "Open Efficiency Guide"
    ]
    let chinese = [
        "context_at": "上下文占用 %d%%",
        "dismiss": "关闭",
        "fresh_task_suggestion": "建议在此检查点之后新建任务。",
        "open_efficiency_coach": "打开效率指南"
    ]
    return language == .chinese ? chinese[key] ?? english[key] ?? key : english[key] ?? key
}
