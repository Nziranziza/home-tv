import SwiftUI

/// The title hero's Starring / Director lines, floated bottom-right. Shared by the detail hero and the
/// row preview.
struct DetailHeroCredits: View {
    let model: MetaDetailModel

    var body: some View {
        let cast = model.vm.displayCastNames
        let directors = model.vm.displayDirectors
        if !cast.isEmpty || !directors.isEmpty {
            // Tight gap so Director sits just under the wrapped cast block.
            VStack(alignment: .leading, spacing: 4) {
                if !cast.isEmpty {
                    HeroCreditLine(label: "Starring", names: Array(cast.prefix(3)))
                }
                if !directors.isEmpty {
                    HeroCreditLine(label: "Director", names: directors)
                }
            }
            .frame(maxWidth: 440, alignment: .leading)
        }
    }
}
