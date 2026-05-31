import SwiftUI

/// Inline Trakt control for the Settings list: the Trakt mark, a state label, and a single action
/// pill ("Authenticate" when signed out, "Sign Out" when connected). Activating opens a modal that
/// shows the device code; it dismisses itself once `TraktService` finishes signing in.
///
/// Only shown when the build has API credentials (Settings gates on `TraktConfig.isConfigured`), so
/// a user never sees setup instructions — credentials are a build-time concern (see TraktConfig).
struct TraktSettingsRow: View {
    @State private var trakt = TraktService.shared

    var body: some View {
        HStack(spacing: 28) {
            TraktMark()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Trakt")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(subtitleColor)
            }

            Spacer(minLength: 24)

            // Only the pill is focusable — the label is static, matching the reference pattern.
            Button(action: primaryAction) {
                Text(trakt.isSignedIn ? "Sign Out" : "Authenticate")
                    .font(.headline.weight(.semibold))
                    .frame(minWidth: 220)
            }
            .buttonStyle(TraktPillStyle())
        }
        .padding(.horizontal, Theme.Spacing.rowHorizontal)
        .padding(.vertical, Theme.Spacing.rowVertical)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Color.cardRest)
        )
        .fullScreenCover(isPresented: authenticatingBinding) {
            TraktActivationView()
        }
    }

    private var subtitle: String {
        if trakt.isSignedIn { return "Signed in as \(trakt.username ?? "your account")" }
        if let error = trakt.lastError { return error }
        return "Sync watched history, watchlist, and progress"
    }

    private var subtitleColor: Color {
        (!trakt.isSignedIn && trakt.lastError != nil) ? Theme.Color.destructive : Theme.Color.secondaryText
    }

    private func primaryAction() {
        if trakt.isSignedIn {
            trakt.signOut()
        } else {
            trakt.startDeviceAuth()
        }
    }

    /// Drives the activation modal: open while connecting/awaiting, dismiss when that ends (success
    /// flips to signed-in; system-dismissal cancels the in-flight poll).
    private var authenticatingBinding: Binding<Bool> {
        Binding(
            get: { trakt.isAuthenticating },
            set: { if !$0 { trakt.cancelDeviceAuth() } }
        )
    }
}

/// Full-screen activation step shown while signing in: the device code to enter at trakt.tv/activate.
private struct TraktActivationView: View {
    @State private var trakt = TraktService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            VStack(spacing: 28) {
                TraktMark()
                    .frame(width: 88, height: 88)

                switch trakt.authState {
                case .awaitingActivation(let code, let url):
                    Text("Connect Trakt")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.Color.primaryText)
                    VStack(spacing: 6) {
                        Text("On your phone or computer, go to")
                            .foregroundStyle(Theme.Color.secondaryText)
                        Text(url)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.Color.primaryText)
                        Text("and enter this code:")
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                    .font(.title3)
                    .multilineTextAlignment(.center)

                    Text(code)
                        .font(.system(size: 76, weight: .heavy, design: .monospaced))
                        .tracking(10)
                        .foregroundStyle(Theme.Color.primaryText)

                    HStack(spacing: 14) {
                        ProgressView()
                        Text("Waiting for activation…")
                            .font(.callout)
                            .foregroundStyle(Theme.Color.secondaryText)
                    }

                default:
                    ProgressView().scaleEffect(1.5)
                    Text("Starting…")
                        .font(.title3)
                        .foregroundStyle(Theme.Color.secondaryText)
                }

                Button("Cancel") { dismiss() }
                    .buttonStyle(TraktPillStyle())
                    .padding(.top, 12)
            }
            .padding(60)
        }
    }
}

// MARK: - Trakt mark

/// Trakt brand mark — a ring with a layered checkmark. Drawn rather than bundled so there's no asset
/// dependency; drop a `TraktLogo` image into Assets and swap this for `Image("TraktLogo")` if you
/// want the exact official logo.
struct TraktMark: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let lw = max(2, w * 0.09)

            // Outer ring.
            let ring = Path(ellipseIn: CGRect(x: lw / 2, y: lw / 2, width: w - lw, height: h - lw))
            ctx.stroke(ring, with: .color(.white), lineWidth: lw)

            // Two layered checks (the doubled stroke reads as the Trakt mark).
            func check(dx: CGFloat, dy: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: w * (0.28 + dx), y: h * (0.54 + dy)))
                p.addLine(to: CGPoint(x: w * (0.44 + dx), y: h * (0.70 + dy)))
                p.addLine(to: CGPoint(x: w * (0.75 + dx), y: h * (0.33 + dy)))
                return p
            }
            let style = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
            ctx.stroke(check(dx: 0, dy: -0.10), with: .color(.white), style: style)
            ctx.stroke(check(dx: 0, dy: 0.06), with: .color(.white), style: style)
        }
    }
}

// MARK: - Pill button style

/// Capsule action used for the Trakt row + activation buttons: subtle fill at rest, solid white when
/// focused (tvOS), matching the hero buttons' focus language.
private struct TraktPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration)
    }

    private struct PillBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .foregroundStyle(isFocused ? .black : Theme.Color.primaryText)
                .background(
                    Capsule(style: .continuous)
                        .fill(isFocused ? Color.white : Color.white.opacity(0.16))
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.05 : 1.0))
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }
}
