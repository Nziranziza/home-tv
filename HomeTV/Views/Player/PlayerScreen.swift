import SwiftUI

/// The in-app player: video full screen over black. Clicking the remote or pressing Play/Pause toggles
/// playback; Back closes it.
struct PlayerScreen: View {
    @State private var model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    init(request: PlayerRequest) {
        _model = State(initialValue: PlayerModel(request: request))
    }

    var body: some View {
        // One full-screen button, so the focus engine always has a control to hold and Select pauses.
        Button(action: model.togglePlayPause) {
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
            }
        }
        .buttonStyle(PlayerSurfaceButtonStyle())
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: model.state)
        // The app is light; over black video the loader and text need the dark appearance.
        .environment(\.colorScheme, .dark)
        .onExitCommand { dismiss() }
        .onPlayPauseCommand { model.togglePlayPause() }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.didFinish) { _, finished in
            if finished { dismiss() }
        }
    }
}
