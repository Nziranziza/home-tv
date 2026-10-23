import SwiftUI

/// The in-app player: video full screen over black, with the system-style transport bar. Click and
/// Play/Pause toggle playback, Left/Right skip, a swipe scrubs while paused, and Menu hides the bar before
/// closing.
struct PlayerScreen: View {
    @State private var model: PlayerModel
    @State private var swipes = RemoteSwipeTracker()
    @FocusState private var focus: PlayerFocus?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(request: PlayerRequest) {
        _model = State(initialValue: PlayerModel(request: request))
    }

    var body: some View {
        ZStack {
            Color.black
            PlayerVideoSurface(videoView: model.videoView)
            if model.errorMessage == nil, model.state == .loading || model.state == .buffering {
                PlayerLoadingView(title: model.request.title, logoURL: model.request.logoURL)
                    .transition(.opacity)
            }
            if let message = model.errorMessage {
                Text(message)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            // Only one focus layer is mounted at a time: overlapping full-screen focusables break
            // directional navigation. Keeping the bar mounted at zero opacity drops far more frames.
            if model.subtitlesMenu == .style, let appearance = model.subtitles.appearance {
                SubtitleStylePreview(appearance: appearance)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 182)
                    .transition(.opacity)
            }
            if model.bar.isVisible {
                PlayerTransportBar(model: model, focus: $focus, onSelect: select, onMove: move)
                    .padding(.horizontal, 80)
                    .padding(.bottom, 46)
                    .transition(.opacity)
            } else {
                // The hidden bar's stand-in, so the focus engine always has a control and Select works.
                Button(action: model.togglePlayPause) { Color.clear }
                    .buttonStyle(PlayerSurfaceButtonStyle())
                    .focused($focus, equals: .surface)
                    .onMoveCommand(perform: move)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: model.state)
        .animation(.easeInOut(duration: 0.3), value: model.bar.isVisible)
        .animation(.easeInOut(duration: 0.2), value: model.subtitlesMenu == nil)
        // The app is light; over black video the loader, text and glass need the dark appearance.
        .environment(\.colorScheme, .dark)
        .onExitCommand {
            if !model.handleExit() { dismiss() }
        }
        .onPlayPauseCommand { model.togglePlayPause() }
        .onAppear {
            model.start()
            swipes.onSwipe = { fraction in
                guard focus == .scrubber else { return }
                model.scrub(byPadFraction: fraction)
            }
            swipes.start()
        }
        .onDisappear {
            swipes.stop()
            model.stop()
        }
        .onChange(of: model.didFinish) { _, finished in
            if finished { dismiss() }
        }
        .onChange(of: model.state) {
            model.playbackDidChange()
        }
        .onChange(of: model.bar.isVisible) { _, visible in
            focus = visible ? .scrubber : .surface
        }
        .onChange(of: model.subtitlesMenu == nil) { _, isClosed in
            if isClosed, model.bar.isVisible { focus = .subtitles }
        }
        .onChange(of: focus) {
            model.noteActivity()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.saveProgress() }
        }
        .task(id: model.isPlaying) {
            // Keeps Control Center's clock in step; it extrapolates between updates.
            while !Task.isCancelled {
                model.publishNowPlaying()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: PlayerModel.saveInterval)
                model.saveProgress()
            }
        }
    }

    private func move(_ direction: MoveCommandDirection) {
        switch direction {
        case .left, .right:
            // A swipe while paused scrubs; only a press on the pad's edge skips.
            if model.state == .paused, swipes.isSwiping { return }
            model.skip(by: direction == .left ? -PlayerModel.skipInterval : PlayerModel.skipInterval)
        default:
            model.bar.show(isPlaying: model.isPlaying)
        }
    }

    /// The other buttons' menus and the tabs' panels arrive in #98–#108.
    private func select(_ target: PlayerFocus) {
        switch target {
        case .subtitles: model.openSubtitlesMenu()
        default: model.noteActivity()
        }
    }
}
