import SwiftUI

struct MainScreenView: View {
    @ObservedObject var model: AppModel
    @State private var showAbout = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                NightDriveBackground()
                    .ignoresSafeArea()

                if let displayTrack = model.displayTrackInfo {
                    let screenMetrics = metrics(for: proxy.size)

                    VStack(spacing: screenMetrics.verticalSpacing) {
                        header
                        artworkCard(sideLength: screenMetrics.artworkSize)
                        metadata(displayTrack, compact: screenMetrics.isCompact)
                        Spacer(minLength: screenMetrics.flexSpacer)
                        bottomControls(displayTrack, metrics: screenMetrics)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 20)
                    .padding(.top, max(proxy.safeAreaInsets.top - 18, 8))
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 18))
                } else {
                    EmptyStateCard()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                }

                if let toast = model.toast {
                    VStack {
                        ToastBanner(toast: toast)
                        Spacer()
                    }
                    .padding(.top, max(proxy.safeAreaInsets.top, 18))
                    .padding(.horizontal, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let flashAction = model.flashAction {
                    flashOverlay(for: flashAction)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                if model.showDebugOverlay {
                    DebugOverlay(lines: model.debugLines, closeAction: model.closeDebugOverlay)
                        .padding()
                        .transition(.opacity)
                }

                if model.isSplashVisible {
                    SplashOverlayView()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingSheet {
                model.dismissOnboarding()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .animation(.easeInOut(duration: 0.24), value: model.toast)
        .animation(.easeOut(duration: 0.26), value: model.flashAction)
        .animation(.easeInOut(duration: 0.2), value: model.showDebugOverlay)
    }

    private func flashOverlay(for action: TrackActionKind) -> some View {
        let tint = action == .keep ? Color.neonGreen : Color.neonRed

        return Rectangle()
            .fill(tint.opacity(0.1))
            .overlay {
                LinearGradient(
                    colors: [
                        tint.opacity(0.03),
                        tint.opacity(0.085),
                        tint.opacity(0.03)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .blendMode(.screen)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Music Triage")
                .font(.system(size: 29, weight: .black, design: .rounded))
                .foregroundStyle(Color.neonText)
                .shadow(color: Color.neonBlue.opacity(0.38), radius: 16)

            Spacer()

            StatusOrb(isVerifying: isVerifying)

            Button {
                showAbout = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.neonText.opacity(0.84))
            }
            .padding(.leading, 8)
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.8) {
            model.toggleDebugOverlay()
        }
        .sheet(isPresented: $showAbout) {
            AboutSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func artworkCard(sideLength: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ArtworkView(image: model.displayedArtwork, isDimmed: model.displayTrackInfo?.isDimmed ?? false)
                .frame(width: sideLength, height: sideLength)

            if let displayTrack = model.displayTrackInfo {
                PlaybackStamp(isPlaying: displayTrack.isPlaying)
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func metadata(_ displayTrack: DisplayTrackInfo, compact: Bool) -> some View {
        NeonPanel {
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                Text(displayTrack.title)
                    .font(.system(size: compact ? 26 : 32, weight: .black, design: .rounded))
                    .foregroundStyle(Color.neonText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(displayTrack.artist)
                    .font(.system(size: compact ? 15 : 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.neonText.opacity(0.86))
                    .lineLimit(1)

                if let albumTitle = displayTrack.albumTitle, !albumTitle.isEmpty {
                    Text(albumTitle)
                        .font(.system(size: compact ? 11 : 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.neonBlue.opacity(0.84))
                        .textCase(.uppercase)
                        .tracking(compact ? 0.8 : 1.1)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                    ProgressStrip(
                        progress: displayTrack.progress,
                        onScrub: { progress in
                            model.seek(to: progress)
                        }
                    )

                    HStack {
                        Text(formatTime(displayTrack.elapsedTime))
                        Spacer()
                        Text(formatTime(displayTrack.duration))
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.neonText.opacity(0.56))
                }
                .padding(.top, 2)

                Text(displayTrack.helperText)
                    .font(.system(compact ? .footnote : .subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.neonText.opacity(0.72))
                    .lineLimit(compact ? 2 : 3)
            }
        }
    }

    private var membershipRow: some View {
        HStack(spacing: 10) {
            let membership = model.currentMembership
            if membership.isKeeper {
                StatusPill(label: "KEEPER", tint: .green)
            }
            if membership.isTriaged {
                StatusPill(label: "TRIAGED", tint: .red)
            }
            if !membership.isKeeper && !membership.isTriaged {
                StatusPill(label: "UNSORTED", tint: .white.opacity(0.24))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bottomControls(_ displayTrack: DisplayTrackInfo, metrics: ScreenMetrics) -> some View {
        VStack(spacing: metrics.bottomGroupSpacing) {
            utilityArea(displayTrack, compact: metrics.isCompact)
            membershipRow
            actionArea(cardHeight: metrics.actionPadHeight)
        }
    }

    private func actionArea(cardHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            if model.canShowPermissionRecovery {
                PermissionRecoveryCard(
                    message: model.permissionRecoveryMessage,
                    openSettings: model.openSettings
                )
            } else {
                HStack(spacing: 14) {
                    ActionPad(
                        title: "KEEP",
                        subtitle: "Keepers + library",
                        symbolName: "checkmark.circle.fill",
                        tint: Color.neonGreen,
                        minHeight: cardHeight,
                        isDisabled: !model.canTrigger(.keep),
                        isEmphasized: model.emphasizedAction == .keep,
                        tapAction: { model.handlePrimaryAction(.keep) }
                    )

                    ActionPad(
                        title: "DELETE",
                        subtitle: "Send to triage",
                        symbolName: "minus.circle.fill",
                        tint: Color.neonRed,
                        minHeight: cardHeight,
                        isDisabled: !model.canTrigger(.delete),
                        isEmphasized: model.emphasizedAction == .delete,
                        tapAction: { model.handlePrimaryAction(.delete) }
                    )
                }
            }
        }
    }

    private func utilityArea(_ displayTrack: DisplayTrackInfo, compact: Bool) -> some View {
        NeonPanel {
            HStack(spacing: compact ? 10 : 14) {
                TransportButtonRow(
                    centerSymbolName: displayTrack.isPlaying ? "pause.fill" : "play.fill",
                    previousAction: model.skipPrevious,
                    centerAction: model.playPause,
                    nextAction: model.skipNext
                )

                Spacer(minLength: compact ? 4 : 10)

                CompactAutoSkipToggle(
                    isOn: model.autoSkipEnabled,
                    setOn: model.setAutoSkipEnabled(_:),
                    disabled: model.activeActionCount > 0
                )
            }
        }
    }

    private func metrics(for size: CGSize) -> ScreenMetrics {
        let compactHeight = size.height < 900
        return ScreenMetrics(
            isCompact: compactHeight,
            artworkSize: min(size.width - 96, compactHeight ? 188 : 228),
            actionPadHeight: compactHeight ? 134 : 146,
            verticalSpacing: compactHeight ? 10 : 14,
            bottomGroupSpacing: compactHeight ? 10 : 14,
            flexSpacer: compactHeight ? 0 : 6
        )
    }

    private var isVerifying: Bool {
        if case .verifying = model.verificationSurface {
            return true
        }
        return false
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "--:--" }
        let minutes = Int(value) / 60
        let seconds = Int(value) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ScreenMetrics {
    let isCompact: Bool
    let artworkSize: CGFloat
    let actionPadHeight: CGFloat
    let verticalSpacing: CGFloat
    let bottomGroupSpacing: CGFloat
    let flexSpacer: CGFloat
}
