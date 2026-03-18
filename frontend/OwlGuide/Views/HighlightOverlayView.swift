import SwiftUI

struct HighlightOverlayView: View {
    let reminderCard: HighlightOverlayReminderCardLayout?
    let anchor: CGRect?
    let highlights: [HighlightOverlayItemLayout]
    let overlaySize: CGSize

    @State private var isBreathing = false
    @State private var isPulsing = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .allowsHitTesting(false)

            if let reminderCard {
                HighlightOverlayReminderCardView(card: reminderCard)
                    .frame(width: reminderCard.frame.width, height: reminderCard.frame.height)
                    .position(x: reminderCard.frame.midX, y: reminderCard.frame.midY)
            }

            if let anchor {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.orange, lineWidth: 6)
                    .opacity(isPulsing ? 1.0 : 0.6)
                    .frame(width: anchor.width, height: anchor.height)
                    .position(x: anchor.midX, y: anchor.midY)
                    .allowsHitTesting(false)
            }

            ForEach(highlights) { highlight in
                BreathingHighlightView(
                    highlight: highlight,
                    isBreathing: isBreathing
                )
                .frame(
                    width: highlight.localRect.width,
                    height: highlight.localRect.height,
                    alignment: .topLeading
                )
                .position(
                    x: highlight.localRect.midX,
                    y: highlight.localRect.midY
                )
                .allowsHitTesting(false)
            }

            ForEach(highlights) { highlight in
                if let captionRect = highlight.captionRect {
                    Text(highlight.caption)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.94))
                        )
                        .frame(width: captionRect.width, height: captionRect.height)
                        .position(x: captionRect.midX, y: captionRect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: overlaySize.width, height: overlaySize.height, alignment: .topLeading)
        .background(Color.clear)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct BreathingHighlightView: View {
    let highlight: HighlightOverlayItemLayout
    let isBreathing: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange, lineWidth: 5)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.orange.opacity(isBreathing ? 0.08 : 0.16))
                )
                .shadow(color: Color.orange.opacity(isBreathing ? 0.72 : 0.36), radius: isBreathing ? 22 : 12)
                .scaleEffect(isBreathing ? 1.05 : 1.0)
                .opacity(isBreathing ? 0.82 : 1.0)

            Text("\(highlight.rank)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.86))
                )
                .offset(x: 10, y: 10)
        }
    }
}

private struct HighlightOverlayReminderCardView: View {
    let card: HighlightOverlayReminderCardLayout

    @State private var isButtonHovered = false

    private enum CardTypography {
        static let status = Font.system(size: 15, weight: .semibold, design: .rounded)
        static let version = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let progress = Font.system(size: 13, weight: .medium, design: .rounded)
        static let title = Font.system(size: 21, weight: .semibold)
        static let body = Font.system(size: 17, weight: .regular)
        static let detail = Font.system(size: 16, weight: .regular)
        static let previewIcon = Font.system(size: 15, weight: .medium)
        static let previewText = Font.system(size: 15, weight: .regular)
        static let buttonIcon = Font.system(size: 18, weight: .semibold)
        static let buttonLabel = Font.system(size: 18, weight: .bold, design: .rounded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(card.statusLabel)
                    .font(CardTypography.status)
                    .foregroundStyle(statusForegroundColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(statusBackgroundColor)
                    )

                Spacer(minLength: 0)

                Text(AppBuildInfo.version)
                    .font(CardTypography.version)
                    .foregroundStyle(Color.black.opacity(0.35))
                    .padding(.top, 4)
            }

            if let progressCurrentStep = card.progressCurrentStep,
               let progressTotalSteps = card.progressTotalSteps,
               progressTotalSteps > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(0..<progressTotalSteps, id: \.self) { index in
                            Capsule(style: .continuous)
                                .fill(index < progressCurrentStep ? progressFillColor : Color.black.opacity(0.08))
                                .frame(maxWidth: .infinity)
                                .frame(height: 6)
                        }
                    }

                    Text("Step \(progressCurrentStep) of \(progressTotalSteps)")
                        .font(CardTypography.progress)
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }

            Text(normalizedTitle(card.title))
                .font(CardTypography.title)
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text(card.message)
                .font(CardTypography.body)
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = card.detail {
                Text(detail)
                    .font(CardTypography.detail)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let inputPreview = card.actionInputPreview {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "text.cursor")
                        .foregroundStyle(Color.black.opacity(0.4))
                        .font(CardTypography.previewIcon)
                        .padding(.top, 2)
                    Text(inputPreview)
                        .font(CardTypography.previewText)
                        .foregroundStyle(Color.black.opacity(0.85))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
                .padding(.top, 4)
            }
            if let actionLabel = card.actionLabel,
               let onExecute = card.onExecuteAction {
                Button(action: onExecute) {
                    HStack(spacing: 8) {
                        Image(systemName: card.actionInputPreview != nil ? "keyboard.fill" : "hand.tap.fill")
                            .font(CardTypography.buttonIcon)
                        Text(actionLabel)
                            .font(CardTypography.buttonLabel)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.22, green: 0.65, blue: 0.30),
                                        Color(red: 0.16, green: 0.55, blue: 0.24)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: Color(red: 0.16, green: 0.55, blue: 0.24).opacity(isButtonHovered ? 0.5 : 0.3), radius: isButtonHovered ? 12 : 6, y: isButtonHovered ? 5 : 3)
                    .scaleEffect(isButtonHovered ? 1.03 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isButtonHovered)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isButtonHovered = hovering
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.975))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
    }

    private var statusForegroundColor: Color {
        switch card.emphasis {
        case .loading:
            return Color(red: 0.11, green: 0.31, blue: 0.52)
        case .normal:
            return Color(red: 0.26, green: 0.36, blue: 0.09)
        case .caution:
            return Color(red: 0.47, green: 0.29, blue: 0.04)
        }
    }

    private var statusBackgroundColor: Color {
        switch card.emphasis {
        case .loading:
            return Color(red: 0.86, green: 0.92, blue: 0.99)
        case .normal:
            return Color(red: 0.90, green: 0.96, blue: 0.86)
        case .caution:
            return Color(red: 0.97, green: 0.91, blue: 0.74)
        }
    }

    private var progressFillColor: Color {
        switch card.emphasis {
        case .loading:
            return Color(red: 0.28, green: 0.56, blue: 0.84)
        case .normal:
            return Color(red: 0.43, green: 0.68, blue: 0.28)
        case .caution:
            return Color(red: 0.88, green: 0.67, blue: 0.18)
        }
    }

    private func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "[。.!?！？:：;；]+$",
                with: "",
                options: .regularExpression
            )
    }
}
