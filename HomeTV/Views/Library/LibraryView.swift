import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 24) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 80))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Library")
                        .font(.system(size: 56, weight: .bold))
                    Text("Continue Watching and saved titles will appear here.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .navigationTitle("Library")
        }
    }
}
