import SwiftUI

extension Color {
    static let horizonTop = Color(red: 0.02, green: 0.04, blue: 0.09)
    static let horizonBottom = Color(red: 0.07, green: 0.02, blue: 0.13)
    static let neonBlue = Color(red: 0.19, green: 0.84, blue: 1.0)
    static let neonBlueSoft = Color(red: 0.37, green: 0.62, blue: 1.0)
    static let neonPink = Color(red: 1.0, green: 0.27, blue: 0.63)
    static let neonGreen = Color(red: 0.26, green: 0.94, blue: 0.55)
    static let neonRed = Color(red: 1.0, green: 0.32, blue: 0.36)
    static let neonAmber = Color(red: 1.0, green: 0.76, blue: 0.28)
    static let neonText = Color(red: 0.96, green: 0.98, blue: 1.0)
    static let clickwheelMetal = Color(red: 0.80, green: 0.79, blue: 0.75)
}

struct NightDriveBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .horizonTop,
                    Color(red: 0.04, green: 0.07, blue: 0.14),
                    .horizonBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.neonBlue.opacity(0.16))
                .frame(width: 310, height: 310)
                .blur(radius: 60)
                .offset(x: -120, y: -280)

            Circle()
                .fill(Color.neonPink.opacity(0.18))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: 140, y: 260)

            VStack(spacing: 52) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.neonBlue.opacity(0), Color.neonBlue.opacity(0.45), Color.neonPink.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.neonPink.opacity(0), Color.neonPink.opacity(0.4), Color.neonBlue.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }
            .padding(.horizontal, 18)
            .blendMode(.screen)
            .opacity(0.55)

            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 44, bottomLeading: 14, bottomTrailing: 44, topTrailing: 14))
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                .padding(18)
        }
    }
}

struct ArtworkView: View {
    let image: UIImage?
    let isDimmed: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.neonBlue.opacity(0.08),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(isDimmed ? 0 : 1)
                    .opacity(isDimmed ? 0.58 : 1)
                    .overlay {
                        if isDimmed {
                            Color.black.opacity(0.25)
                        }
                    }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 54, weight: .light))
                    Text("Waiting for artwork")
                        .font(.system(.headline, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.6))
            }

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.neonBlue.opacity(0.62),
                            Color.white.opacity(0.14),
                            Color.neonPink.opacity(0.56)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.4
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 4)
                .padding(10)
        }
        .shadow(color: Color.neonBlue.opacity(0.18), radius: 36, y: 16)
        .shadow(color: .black.opacity(0.34), radius: 24, y: 20)
    }
}

struct PlaybackStamp: View {
    let isPlaying: Bool

    var body: some View {
        Text(isPlaying ? "LIVE" : "PAUSED")
            .font(.system(.caption, design: .rounded, weight: .black))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.42), in: Capsule())
            .overlay {
                Capsule().strokeBorder((isPlaying ? Color.neonGreen : Color.neonAmber).opacity(0.7), lineWidth: 1)
            }
            .foregroundStyle(.white.opacity(0.92))
    }
}

struct ProgressStrip: View {
    let progress: Double
    var onScrub: ((Double) -> Void)? = nil

    @State private var dragProgress: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.12))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .neonBlue,
                                .neonPink
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(proxy.size.width * displayProgress, 6))

                Circle()
                    .fill(Color.neonText)
                    .frame(width: 12, height: 12)
                    .shadow(color: Color.neonBlue.opacity(0.35), radius: 6)
                    .offset(x: knobOffset(for: proxy.size.width) - 6)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard onScrub != nil else { return }
                        dragProgress = clampedProgress(for: value.location.x, width: proxy.size.width)
                    }
                    .onEnded { value in
                        guard let onScrub else { return }
                        let newProgress = clampedProgress(for: value.location.x, width: proxy.size.width)
                        dragProgress = nil
                        onScrub(newProgress)
                    }
            )
        }
        .frame(height: 6)
    }

    private var displayProgress: Double {
        dragProgress ?? progress
    }

    private func clampedProgress(for x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return progress }
        return min(max(Double(x / width), 0), 1)
    }

    private func knobOffset(for width: CGFloat) -> CGFloat {
        CGFloat(displayProgress) * width
    }
}

struct StatusPill: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .rounded, weight: .black))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.94), tint.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
            .foregroundStyle(.black.opacity(0.84))
            .shadow(color: tint.opacity(0.28), radius: 14, y: 6)
    }
}

struct ActionPad: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
    let minHeight: CGFloat
    let isDisabled: Bool
    let isEmphasized: Bool
    let tapAction: () -> Void

    @GestureState private var isPressing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .bold))
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.black.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(isDisabled ? 0.34 : 0.98),
                            tint.opacity(isDisabled ? 0.24 : 0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(isEmphasized || isPressing ? 0.78 : 0.16), lineWidth: isEmphasized || isPressing ? 2.2 : 1)
        }
        .scaleEffect(isEmphasized ? 1.03 : (isPressing ? 0.985 : 1))
        .shadow(color: tint.opacity(isDisabled ? 0 : 0.34), radius: isEmphasized ? 28 : 16, y: 10)
        .foregroundStyle(.black.opacity(0.9))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .gesture(
            LongPressGesture(minimumDuration: 0.25, maximumDistance: 26)
                .updating($isPressing) { value, state, _ in
                    state = value
                }
                .onEnded { _ in
                    guard !isDisabled else { return }
                    tapAction()
                }
        )
        .opacity(isDisabled ? 0.94 : 1)
    }
}

struct TransportButtonRow: View {
    let centerSymbolName: String
    let previousAction: () -> Void
    let centerAction: () -> Void
    let nextAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TransportGlyphButton(symbolName: "backward.fill", action: previousAction)
            TransportGlyphButton(symbolName: centerSymbolName, isPrimary: true, action: centerAction)
            TransportGlyphButton(symbolName: "forward.fill", action: nextAction)
        }
    }
}

private struct TransportGlyphButton: View {
    let symbolName: String
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: isPrimary ? 18 : 15, weight: .bold))
                .foregroundStyle(Color.neonText)
                .frame(width: isPrimary ? 44 : 38, height: isPrimary ? 44 : 38)
                .background(
                    LinearGradient(
                        colors: isPrimary
                            ? [Color.neonBlue.opacity(0.34), Color.neonPink.opacity(0.24)]
                            : [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: isPrimary ? 16 : 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: isPrimary ? 16 : 14, style: .continuous)
                        .strokeBorder(
                            isPrimary ? Color.neonBlue.opacity(0.42) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                }
        }
    }
}

struct CompactAutoSkipToggle: View {
    let isOn: Bool
    let setOn: (Bool) -> Void
    let disabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-skip")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.neonText)
                Text(isOn ? "On after tag" : "Off")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.neonText.opacity(0.6))
            }

            Toggle("", isOn: Binding(get: { isOn }, set: setOn))
                .labelsHidden()
                .disabled(disabled)
                .tint(Color.neonBlue)
                .scaleEffect(0.9)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.neonBlue.opacity(0.15), lineWidth: 1)
        }
    }
}

struct PermissionRecoveryCard: View {
    let message: String
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Apple Music access is needed for tagging")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.neonText)
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.neonText.opacity(0.76))
            Button("Open Settings", action: openSettings)
                .buttonStyle(.borderedProminent)
                .tint(Color.neonBlue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.neonPink.opacity(0.18), lineWidth: 1)
        }
    }
}

struct EmptyStateCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 44, weight: .light))
            Text("Open Apple Music and start something playing.")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text("Music Triage will stay calm until it can identify the song safely.")
                .font(.system(.body, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.68))
        }
        .foregroundStyle(Color.neonText)
        .padding(28)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.neonBlue.opacity(0.12), lineWidth: 1)
        }
    }
}

struct ToastBanner: View {
    let toast: ToastMessage

    var tint: Color {
        switch toast.style {
        case .keepSuccess:
            .neonGreen
        case .deleteSuccess:
            .neonRed
        case .failure:
            .neonRed
        case .neutral:
            Color.white.opacity(0.2)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(toast.title)
                .font(.system(.headline, design: .rounded, weight: .bold))
            if let subtitle = toast.subtitle {
                Text(subtitle)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .foregroundStyle(.black.opacity(0.9))
        .shadow(color: tint.opacity(0.3), radius: 18, y: 8)
    }
}

struct DebugOverlay: View {
    let lines: [String]
    let closeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug")
                .font(.system(.headline, design: .monospaced, weight: .bold))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Button(action: closeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                }

                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(14)
        }
    }
}

struct NeonPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.neonBlue.opacity(0.20),
                                Color.white.opacity(0.08),
                                Color.neonPink.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
    }
}

struct StatusOrb: View {
    let isVerifying: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 42, height: 42)
            Circle()
                .strokeBorder((isVerifying ? Color.neonAmber : Color.neonBlue).opacity(0.7), lineWidth: 1.2)
                .frame(width: 42, height: 42)
            if isVerifying {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.neonAmber)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.neonBlue)
            }
        }
        .shadow(color: (isVerifying ? Color.neonAmber : Color.neonBlue).opacity(0.18), radius: 16)
    }
}

struct SplashOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                if let image = splashImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 170, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        }
                }

                Text("a John K. Fisher joint")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(.white)
            }
        }
    }

    private var splashImage: UIImage? {
        guard let url = Bundle.main.url(forResource: "John", withExtension: "heic") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

struct OnboardingSheet: View {
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("KEEP sends the current song to **Keepers**. If needed, it also tries to add that song to your library.")
                Text("DELETE sends the current song to **Music Triage**. In V1, it does **not** remove anything from your Apple Music library.")
                Text("The app waits to ask for Apple Music access until you actually try to tag a song.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.system(.body, design: .rounded))
            .padding(24)
            .navigationTitle("How Music Triage Works")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: dismiss)
                }
            }
        }
    }
}

struct AboutSheet: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Music Triage is a narrow little Apple Music companion for making quick keep-or-delete decisions without tagging the wrong song.")
                    .font(.system(.body, design: .rounded))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Copyright John Kenneth Fisher")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Link("github.com/JohnKFisher/music-triage", destination: URL(string: "https://github.com/JohnKFisher/music-triage")!)
                        .font(.system(.subheadline, design: .rounded))
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("About Music Triage")
        }
    }
}
