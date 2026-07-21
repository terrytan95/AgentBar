import AppKit
import SwiftUI

enum CodexCredentialExpiryState: Equatable {
    case valid(Date)
    case expired(Date)
}

struct CodexSidebarQuotaCardState: Equatable {
    var account: UsageAccount?

    var windows: [UsageWindow] {
        guard let account else { return [] }
        return [account.fiveHourWindow, account.weeklyWindow].compactMap { $0 }
    }

    init(account: UsageAccount?) {
        self.account = account
    }

    func credentialState(at date: Date) -> CodexCredentialExpiryState? {
        guard let expiresAt = account?.accessTokenExpiresAt else { return nil }
        return expiresAt <= date ? .expired(expiresAt) : .valid(expiresAt)
    }
}

struct CodexSidebarQuotaCard: View {
    @ObservedObject var store: UsageStore
    var onContentSizeChange: () -> Void = {}

    @State private var isResetCreditsExpanded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let state = CodexSidebarQuotaCardState(account: activeCodexAccount)
            VStack(alignment: .leading, spacing: 10) {
                if state.windows.isEmpty {
                    Text(L.text("quota_unavailable", store.language))
                        .font(.agentBar(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.windows) { window in
                        quotaWindow(window)
                    }
                }

                if let resetCredits = state.account?.resetCredits, resetCredits.hasAvailableCredits {
                    resetCreditsSection(resetCredits)
                }

                if let credentialState = state.credentialState(at: timeline.date) {
                    credentialLine(credentialState)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CodexSidebarGlassSurface())
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var activeCodexAccount: UsageAccount? {
        store.accounts.first { $0.service == .codex && $0.isActive }
            ?? store.accounts.first { $0.service == .codex }
    }

    private func quotaWindow(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(window.kind == .fiveHour ? L.text("five_hour", store.language) : L.text("weekly", store.language))
                Spacer(minLength: 8)
                Text("\(DisplayFormatters.percentString(window.remainingPercent)) \(L.text("remaining", store.language))")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.agentBar(size: 11, weight: .medium))

            GeometryReader { geometry in
                let progress = min(max(window.remainingPercent / 100, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(progressColor(window.remainingPercent))
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 8)

            Text(window.resetLine(language: store.language))
                .font(.agentBar(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
    }

    private func credentialLine(_ state: CodexCredentialExpiryState) -> some View {
        let expiresAt: Date
        let title: String
        let color: Color
        switch state {
        case .valid(let date):
            expiresAt = date
            title = L.text("credential_expires", store.language)
            color = .secondary
        case .expired(let date):
            expiresAt = date
            title = L.text("credential_expired", store.language)
            color = .red
        }
        let timestamp = DisplayFormatters.shortDateTimeString(for: expiresAt, language: store.language)
        let relative = state == .expired(expiresAt)
            ? L.text("expired", store.language)
            : DisplayFormatters.relativeString(for: expiresAt, language: store.language)
        return metadataLine("\(title): \(timestamp) (\(relative))", systemImage: "key.horizontal", color: color)
    }

    private func resetCreditsSection(_ resetCredits: UsageResetCredits) -> some View {
        let lines = resetCredits.expirationLines(language: store.language)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                isResetCreditsExpanded.toggle()
                onContentSizeChange()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isResetCreditsExpanded ? "chevron.down" : "chevron.right")
                        .font(.agentBar(size: 9, weight: .semibold))
                        .frame(width: 10)
                        .accessibilityHidden(true)
                    Label(L.text("reset_credits", store.language), systemImage: "arrow.counterclockwise.circle")
                    Spacer(minLength: 8)
                    Text("\(resetCredits.visibleCount)")
                        .monospacedDigit()
                }
                .font(.agentBar(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(L.text("reset_credits", store.language)), \(resetCredits.visibleCount)")

            if isResetCreditsExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        metadataLine(line, systemImage: "arrow.counterclockwise.circle")
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 16)
            }
        }
    }

    private func metadataLine(_ text: String, systemImage: String, color: Color = .secondary) -> some View {
        Label(text, systemImage: systemImage)
            .font(.agentBar(size: 9, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
    }

    private func progressColor(_ remaining: Double) -> Color {
        if remaining < 15 { return .red }
        if remaining < 35 { return .orange }
        return Color(red: 0.36, green: 0.60, blue: 0.98)
    }
}

private struct CodexSidebarGlassSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
                .background { CodexSidebarMaterialView() }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct CodexSidebarMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
