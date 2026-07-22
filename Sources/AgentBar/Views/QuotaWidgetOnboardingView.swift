import SwiftUI

struct QuotaWidgetOnboardingView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var overlay: CodexSidebarQuotaOverlayController
    var language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.installation

    private enum Step: Int, CaseIterable {
        case installation
        case placement
        case permission
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)
            Divider()
            footer
        }
        .frame(width: 620, height: 500)
        .background(AgentBarDesign.appBackground)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: AppLogo.image())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(L.text("quota_onboarding_title", language))
                    .font(.agentBarDisplay(size: 21, weight: .bold))
                Text(L.text("quota_onboarding_subtitle", language))
                    .font(.agentBar(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            progress
        }
        .padding(22)
        .background(.thinMaterial)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Circle()
                    .fill(item.rawValue <= step.rawValue ? AgentBarPalette.primary : Color.secondary.opacity(0.22))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel("\(step.rawValue + 1) / \(Step.allCases.count)")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .installation:
            installationStep
        case .placement:
            placementStep
        case .permission:
            permissionStep
        }
    }

    private var installationStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeading(
                titleKey: "quota_onboarding_install_title",
                subtitleKey: "quota_onboarding_install_subtitle"
            )

            statusCard(
                systemImage: isInstalledInApplications ? "checkmark.circle.fill" : "arrow.down.app.fill",
                tint: isInstalledInApplications ? .green : .orange,
                title: L.text(
                    isInstalledInApplications ? "quota_onboarding_installed" : "quota_onboarding_move_to_applications",
                    language
                )
            )

            Label {
                Text(L.text("quota_onboarding_gatekeeper", language))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(AgentBarPalette.primary)
            }
            .font(.agentBar(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var placementStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeading(
                titleKey: "quota_onboarding_mode_title",
                subtitleKey: "quota_onboarding_mode_subtitle"
            )

            HStack(spacing: 14) {
                placementCard(
                    titleKey: "quota_onboarding_attached",
                    subtitleKey: "quota_onboarding_attached_subtitle",
                    systemImage: "sidebar.left",
                    selected: !settings.codexSidebarQuotaOverlayIndependent
                ) {
                    settings.codexSidebarQuotaOverlayIndependent = false
                }

                placementCard(
                    titleKey: "codex_sidebar_independent",
                    subtitleKey: "codex_sidebar_independent_subtitle",
                    systemImage: "macwindow.on.rectangle",
                    selected: settings.codexSidebarQuotaOverlayIndependent
                ) {
                    settings.codexSidebarQuotaOverlayIndependent = true
                }
            }
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeading(
                titleKey: "quota_onboarding_permission_title",
                subtitleKey: "quota_onboarding_permission_subtitle"
            )

            if settings.codexSidebarQuotaOverlayIndependent {
                statusCard(
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    title: L.text("quota_onboarding_independent_ready", language)
                )
            } else {
                statusCard(
                    systemImage: overlay.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: overlay.hasAccessibilityPermission ? .green : .orange,
                    title: L.text(
                        overlay.hasAccessibilityPermission
                            ? "quota_onboarding_permission_ready"
                            : "quota_onboarding_permission_needed",
                        language
                    )
                )

                if !overlay.hasAccessibilityPermission {
                    HStack(spacing: 10) {
                        Button(L.text("quota_onboarding_grant_access", language)) {
                            overlay.requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(L.text("open_system_settings", language)) {
                            overlay.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                    .pointingHandCursor()
                }
            }
        }
    }

    private func stepHeading(titleKey: String, subtitleKey: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.text(titleKey, language))
                .font(.agentBar(size: 19, weight: .bold))
            Text(L.text(subtitleKey, language))
                .font(.agentBar(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func statusCard(systemImage: String, tint: Color, title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.agentBar(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30)
            Text(title)
                .font(.agentBar(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentBarPanel(cornerRadius: 14)
    }

    private func placementCard(
        titleKey: String,
        subtitleKey: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.agentBar(size: 22, weight: .semibold))
                        .foregroundStyle(AgentBarPalette.primary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AgentBarPalette.primary : Color.secondary)
                }
                Text(L.text(titleKey, language))
                    .font(.agentBar(size: 14, weight: .bold))
                Text(L.text(subtitleKey, language))
                    .font(.agentBar(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(
                selected ? AgentBarPalette.primary.opacity(0.12) : AgentBarDesign.cardBackground,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? AgentBarPalette.primary : Color.secondary.opacity(0.18), lineWidth: selected ? 2 : 1)
            }
        }
        .tactilePlainButton()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(L.text("quota_onboarding_later", language)) {
                settings.didCompleteQuotaWidgetOnboarding = true
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            if step != .installation {
                Button(L.text("quota_onboarding_back", language)) {
                    step = Step(rawValue: step.rawValue - 1) ?? .installation
                }
                .buttonStyle(.bordered)
            }

            if step == .permission {
                Button(L.text("quota_onboarding_finish", language)) {
                    settings.showCodexSidebarQuotaOverlay = true
                    settings.didCompleteQuotaWidgetOnboarding = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.codexSidebarQuotaOverlayIndependent && !overlay.hasAccessibilityPermission)
            } else {
                Button(L.text("quota_onboarding_continue", language)) {
                    step = Step(rawValue: step.rawValue + 1) ?? .permission
                }
                .buttonStyle(.borderedProminent)
                .disabled(step == .installation && !isInstalledInApplications)
            }
        }
        .padding(18)
        .background(.thinMaterial)
    }

    private var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path == "/Applications"
    }
}
