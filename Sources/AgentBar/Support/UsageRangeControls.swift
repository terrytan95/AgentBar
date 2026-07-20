import SwiftUI

struct UsageRangeControls: View {
    @Binding var range: UsageRange
    @Binding var customStart: Date
    @Binding var customEnd: Date
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Text(L.text("interval", language))
                .font(.agentBar(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { range },
                set: { newRange in
                    DispatchQueue.main.async { range = newRange }
                }
            )) {
                ForEach(UsageRange.allCases) { range in
                    Text(range.dashboardLabel(language)).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if range == .custom {
                Divider()
                    .frame(height: 18)
                compactDatePicker(
                    label: L.text("start_date", language),
                    selection: customStartBinding
                )
                Text("–")
                    .foregroundStyle(.secondary)
                compactDatePicker(
                    label: L.text("end_date", language),
                    selection: customEndBinding
                )
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .agentBarPanel(cornerRadius: 12)
    }

    private var customStartBinding: Binding<Date> {
        Binding(
            get: { customStart },
            set: { value in
                customStart = value
                if value > customEnd {
                    customEnd = value
                }
            }
        )
    }

    private var customEndBinding: Binding<Date> {
        Binding(
            get: { customEnd },
            set: { value in
                customEnd = value
                if value < customStart {
                    customStart = value
                }
            }
        )
    }

    private func compactDatePicker(label: String, selection: Binding<Date>) -> some View {
        DatePicker(label, selection: selection, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(width: 112)
            .accessibilityLabel(Text(label))
    }
}
