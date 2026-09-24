import SwiftUI

/// A streaming service as a channel: its wordmark over a paging hero, a Top 10 row, and its shelves.
struct ChannelView: View {
    let channel: StreamingChannel
    /// False while something covers this screen, so the hero trailer stands down.
    let isActive: Bool
    var onPlay: (MetaPreview) -> Void
    var onSelect: (MetaPreview) -> Void

    @State private var model: ChannelViewModel
    @State private var heroModel = HeroCarouselModel()
    /// One lookup at a time, so a second Select mid-lookup can't push two details.
    @State private var isSelecting = false

    init(
        channel: StreamingChannel,
        isActive: Bool,
        onPlay: @escaping (MetaPreview) -> Void,
        onSelect: @escaping (MetaPreview) -> Void
    ) {
        self.channel = channel
        self.isActive = isActive
        self.onPlay = onPlay
        self.onSelect = onSelect
        _model = State(initialValue: ChannelViewModel(channel: channel))
    }

    var body: some View {
        HeroSheetPage(heroModel: heroModel, onPlay: onPlay, onInfo: onSelect) {
            ChannelWordmark(
                channel: channel,
                logoURL: model.wordmarkURL,
                maxSize: Theme.Channel.heroLogoMaxSize,
                font: .title2.bold(),
                alignment: .leading
            )
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            .padding(.top, Theme.Channel.heroLogoTopPadding)
            .padding(.leading, Theme.Hero.horizontalPadding)
        } rows: {
            if model.isLoaded {
                TopTenRow(metas: model.topTen) { select($0) }
                ForEach(model.shelves) { shelf in
                    ChannelShelfRow(channel: channel, shelf: shelf) { select($0) }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task {
            await model.load()
            heroModel.items = model.heroItems
        }
        .onChange(of: isActive, initial: true) { _, active in
            heroModel.isActive = active
        }
    }

    private func select(_ meta: MetaPreview) {
        guard !isSelecting else { return }
        isSelecting = true
        Task {
            let resolved = await model.resolved(meta)
            isSelecting = false
            if let resolved { onSelect(resolved) }
        }
    }
}
