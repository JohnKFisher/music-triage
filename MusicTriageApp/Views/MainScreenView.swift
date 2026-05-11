import SwiftUI

struct MainScreenView: View {
    @ObservedObject var model: AppModel
    @State private var showAbout = false

    var body: some View {
        ZStack {
            NightDriveBackground()
                .ignoresSafeArea()

            if let displayTrack = model.displayTrackInfo {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                    header
                    artworkCard
                        metadata(displayTrack)
                    membershipRow
                    actionArea
                    utilityArea(displayTrack)
                }
                .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
            } else {
                EmptyStateCard()
                    .padding(24)
            }

            if let toast = model.toast {
                VStack {
                    ToastBanner(toast: toast)
                    Spacer()
                }
                .padding(.top, 18)
                .padding(.horizontal, 18)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.showDebugOverlay {
                DebugOverlay(lines: model.debugLines)
                    .padding()
                    .transition(.opacity)
            }

            if model.isSplashVisible {
                SplashOverlayView()
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingSheet {
                model.dismissOnboarding()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .animation(.easeInOut(duration: 0.24), value: model.toast)
        .animation(.easeInOut(duration: 0.2), value: model.showDebugOverlay)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Music Triage")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .foregroundStyle(Color.neonText)
                    .shadow(color: Color.neonBlue.opacity(0.38), radius: 16)
                Text("Never act on the wrong song.")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.neonText.opacity(0.64))
            }

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

    private var artworkCard: some View {
        ZStack(alignment: .bottomTrailing) {
            ArtworkView(image: model.displayedArtwork, isDimmed: model.displayTrackInfo?.isDimmed ?? false)

            if let displayTrack = model.displayTrackInfo {
                PlaybackStamp(isPlaying: displayTrack.isPlaying)
                    .padding(14)
            }
        }
    }

    private func metadata(_ displayTrack: DisplayTrackInfo) -> some View {
        NeonPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(displayTrack.title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(Color.neonText)
                    .lineLimit(2)

                Text(displayTrack.artist)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.neonText.opacity(0.86))
                    .lineLimit(1)

                if let albumTitle = displayTrack.albumTitle, !albumTitle.isEmpty {
                    Text(albumTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.neonBlue.opacity(0.84))
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ProgressStrip(progress: displayTrack.progress)

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
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.neonText.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
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

    private var actionArea: some View {
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
                        isDisabled: !model.canTrigger(.keep),
                        isEmphasized: model.emphasizedAction == .keep,
                        tapAction: { model.handlePrimaryAction(.keep) }
                    )

                    ActionPad(
                        title: "DELETE",
                        subtitle: "Send to triage",
                        symbolName: "minus.circle.fill",
                        tint: Color.neonRed,
                        isDisabled: !model.canTrigger(.delete),
                        isEmphasized: model.emphasizedAction == .delete,
                        tapAction: { model.handlePrimaryAction(.delete) }
                    )
                }
            }
        }
    }

    private func utilityArea(_ displayTrack: DisplayTrackInfo) -> some View {
        NeonPanel {
            VStack(spacing: 16) {
                ClickwheelTransportCluster(
                    centerSymbolName: displayTrack.isPlaying ? "pause.fill" : "play.fill",
                    previousAction: model.skipPrevious,
                    centerAction: model.playPause,
                    nextAction: model.skipNext
                )

                AutoSkipToggle(
                    isOn: model.autoSkipEnabled,
                    setOn: model.setAutoSkipEnabled(_:),
                    disabled: model.activeActionCount > 0
                )
            }
        }
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
