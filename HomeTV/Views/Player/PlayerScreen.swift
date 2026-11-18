import SwiftUI

/// The in-app player: video full screen over black, with the system-style transport bar. Click and
/// Play/Pause toggle playback, Left/Right skip or, held, scan, a swipe scrubs while paused, and Menu hides
/// the bar before closing.
struct PlayerScreen: View {
    @State private var model: PlayerModel
    @State private var swipes = RemoteSwipeTracker()
    @FocusState private var focus: PlayerFocus?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(request: PlayerRequest) {
        // The stream picker may have opened this stream already, on focus.
        _model = State(initialValue: PlayerPrewarmer.shared.take(for: request) ?? PlayerModel(request: request))
    }

    var body: some View {
        // Up Next waits while the bar is up, so it never takes the screen from under the viewer.
        let showsUpNext = model.isShowingUpNext && !model.bar.isVisible
        ZStack {
            Color.black
            if showsUpNext, let upNext = model.upNext {
                UpNextBackdrop(url: upNext.thumbnailURL)
                    .transition(.opacity)
            }
            PlayerVideoSurface(videoView: model.videoView)
                .upNextVideoFrame(isCornered: showsUpNext, isFocused: showsUpNext && focus == .upNextVideo)
            if model.errorMessage == nil, !showsUpNext, model.showsLoadingScreen {
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
            } else if showsUpNext, let upNext = model.upNext {
                UpNextDetails(model: model, episode: upNext, focus: $focus)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 80)
                    .padding(.bottom, 68)
                    .transition(.opacity)
                UpNextVideoButton(model: model, focus: $focus)
            } else {
                // The hidden bar's stand-in, so the focus engine always has a control and Select works.
                Button(action: model.togglePlayPause) { Color.clear }
                    .buttonStyle(PlayerSurfaceButtonStyle())
                    .focused($focus, equals: .surface)
                    .onMoveCommand(perform: move)
            }
        }
        .background {
            RemoteArrowObserver(onPress: arrowPressed, onClick: model.arrowClicked, onHold: model.arrowHeld)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: model.state)
        .animation(.easeInOut(duration: 0.3), value: model.bar.isVisible)
        .animation(.easeInOut(duration: 0.2), value: model.subtitlesMenu == nil)
        .animation(.easeInOut(duration: 0.2), value: model.isAudioMenuOpen)
        .animation(.easeInOut(duration: 0.3), value: model.panel)
        .animation(.easeInOut(duration: 0.5), value: showsUpNext)
        .animation(.easeOut(duration: 0.2), value: focus == .upNextVideo)
        // The app is light; over black video the loader, text and glass need the dark appearance.
        .environment(\.colorScheme, .dark)
        .onExitCommand {
            if !model.handleExit() { dismiss() }
        }
        .onPlayPauseCommand { model.playPauseCommand() }
        .onAppear {
            model.start()
            swipes.onSwipe = { fraction, speed in
                guard focus == .scrubber else { return }
                model.scrub(byPadFraction: fraction, speed: speed)
            }
            swipes.start()
        }
        .onDisappear {
            swipes.stop()
            model.stop()
        }
        .onChange(of: model.didFinish) { _, finished in
            guard finished else { return }
            // Up Next swaps the next episode in place; its stream is already open.
            if let next = model.nextRequest {
                PlayerPresenter.shared.present(next)
            } else {
                dismiss()
            }
        }
        .onChange(of: model.state) {
            model.playbackDidChange()
        }
        .onChange(of: model.bar.isVisible) { _, visible in
            focus = visible ? .scrubber : model.isShowingUpNext ? .upNextNextEpisode : .surface
        }
        .onChange(of: model.isShowingUpNext) { _, visible in
            guard !model.bar.isVisible else { return }
            focus = visible ? .upNextNextEpisode : .surface
        }
        .onChange(of: model.subtitlesMenu == nil) { _, isClosed in
            if isClosed, model.bar.isVisible { focus = .subtitles }
        }
        .onChange(of: model.isAudioMenuOpen) { _, isOpen in
            if !isOpen, model.bar.isVisible { focus = .audio }
        }
        .onChange(of: model.panel) { _, panel in
            // Menu or Up closed the panel from inside it.
            if panel == nil, model.bar.isVisible, focus?.panel != nil { focus = .scrubber }
        }
        .onChange(of: focus) { _, target in
            model.focusDidChange(to: target)
        }
        .onChange(of: scenePhase) { _, phase in
            model.sceneDidChange(isActive: phase == .active)
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                model.tickUpNext()
            }
        }
    }

    /// Left/Right clicks and holds come from `RemoteArrowObserver`; a swipe's moves only show the bar.
    private func move(_ direction: MoveCommandDirection) {
        model.bar.show(isPlaying: model.isPlaying)
    }

    /// Left/Right skip and scan on the track, or on the hidden bar; elsewhere they only move focus.
    private func arrowPressed(_ side: PlayerScan.Direction) -> Bool {
        guard focus == .scrubber || focus == .surface else { return true }
        return model.arrowPressed(side)
    }

    private func select(_ target: PlayerFocus) {
        switch target {
        case .subtitles: model.openSubtitlesMenu()
        case .audio: model.openAudioMenu()
        case .fromBeginning: model.playFromBeginning()
        case .goToDetail:
            guard let detail = model.detail else { return }
            model.goToDetail(detail)
        default: model.noteActivity()
        }
    }
}
