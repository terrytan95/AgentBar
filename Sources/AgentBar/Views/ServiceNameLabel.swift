import SwiftUI

struct OpenAILogoMark: View {
    var size: CGFloat = 10

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(.foreground)
                    .frame(width: size * 0.46, height: size * 0.19)
                    .offset(x: size * 0.19)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
            Circle()
                .fill(.foreground)
                .frame(width: size * 0.18, height: size * 0.18)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ServiceNameLabel: View {
    var service: UsageService
    var title: String
    var logoSize: CGFloat = 10
    var spacing: CGFloat = 5

    var body: some View {
        HStack(spacing: spacing) {
            if service == .codex {
                OpenAILogoMark(size: logoSize)
            }
            Text(title)
        }
        .lineLimit(1)
    }
}
