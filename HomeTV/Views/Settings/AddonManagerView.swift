import SwiftUI

struct CommunityAddon: Identifiable, Hashable {
    let manifestURL: URL
    let name: String
    let blurb: String
    var id: String { manifestURL.absoluteString }

    static let curated: [CommunityAddon] = [
        CommunityAddon(
            manifestURL: URL(string: "https://v3-cinemeta.strem.io/manifest.json")!,
            name: "Cinemeta",
            blurb: "Default movie + series metadata catalog. Seeded by default."
        ),
        CommunityAddon(
            manifestURL: URL(string: "https://opensubtitles-v3.strem.io/manifest.json")!,
            name: "OpenSubtitles v3",
            blurb: "Subtitle provider. Pairs with any stream source."
        ),
        CommunityAddon(
            manifestURL: URL(string: "https://watchhub.strem.io/manifest.json")!,
            name: "WatchHub",
            blurb: "Surfaces direct links to legal streaming services per title."
        )
    ]
}

struct AddonManagerView: View {
    @State private var registry = AddonRegistry.shared
    @State private var newAddonURL: String = ""
    @State private var isAdding: Bool = false
    @State private var addingCommunityID: String?
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var pendingRemovalID: String?
    @State private var showManualInput: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    ScreenTitle(title: "Addons", subtitle: "Stremio addons that supply catalogs and streams")
                    communitySection
                    manualSection
                    installedSection
                }
                .padding(.horizontal, Theme.Layout.horizontalMargin)
                .padding(.vertical, 60)
            }
            .pageHorizontalInsets()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var communitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.stack) {
            SectionHeader(
                title: "Community Addons",
                subtitle: "One-tap install for well-known public Stremio addons."
            )

            VStack(spacing: 12) {
                ForEach(CommunityAddon.curated) { addon in
                    Button {
                        Task { await installCommunity(addon) }
                    } label: {
                        communityRow(addon)
                    }
                    .buttonStyle(SettingsCardStyle())
                    .disabled(isAdding)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, Theme.Spacing.rowHorizontal)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(theme.destructive)
                    .lineLimit(2)
                    .padding(.horizontal, Theme.Spacing.rowHorizontal)
            }
        }
    }

    private func communityRow(_ addon: CommunityAddon) -> some View {
        let installed = registry.addons.contains { $0.manifestURL == addon.manifestURL }
        let inFlight = addingCommunityID == addon.id

        return HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(addon.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Text(addon.blurb)
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else if inFlight {
                ProgressView()
            } else {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(theme.primaryText)
            }
        }
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.stack) {
            Button {
                showManualInput.toggle()
            } label: {
                HStack {
                    Image(systemName: showManualInput ? "chevron.down" : "chevron.right")
                        .font(.callout.weight(.bold))
                    Text("Add by manifest URL")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.rowHorizontal)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(theme.cardRest)
                )
            }
            .buttonStyle(SettingsCardStyle())

            if showManualInput {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Type the URL with a hardware keyboard (⇧⌘K). Programmatic clipboard access is blocked on tvOS — there's no Paste button I can offer.")
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)

                    TextField("Manifest URL", text: $newAddonURL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.title3)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .fill(theme.cardRest)
                        )
                        .foregroundStyle(theme.primaryText)

                    Button {
                        Task { await addAddon() }
                    } label: {
                        HStack(spacing: 12) {
                            if isAdding && addingCommunityID == nil {
                                ProgressView()
                            } else {
                                Image(systemName: "plus.circle.fill")
                            }
                            Text(isAdding && addingCommunityID == nil ? "Installing…" : "Install Typed URL")
                                .font(.title3.weight(.semibold))
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 4)
                    }
                    .disabled(isAdding || newAddonURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.stack) {
            SectionHeader(title: "Installed", subtitle: "\(registry.addons.count) addon\(registry.addons.count == 1 ? "" : "s")")

            if registry.addons.isEmpty {
                Text("No addons installed yet.")
                    .font(.title3)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, Theme.Spacing.rowHorizontal)
            } else {
                VStack(spacing: 12) {
                    ForEach(registry.addons) { addon in
                        AddonRow(
                            addon: addon,
                            isPendingRemoval: pendingRemovalID == addon.id,
                            onToggle: { registry.setEnabled(id: addon.id, enabled: $0) },
                            onRemoveTapped: { pendingRemovalID = addon.id },
                            onRemoveConfirmed: {
                                registry.remove(id: addon.id)
                                pendingRemovalID = nil
                            },
                            onRemoveCancelled: { pendingRemovalID = nil }
                        )
                    }
                }
            }
        }
    }

    private func installCommunity(_ community: CommunityAddon) async {
        errorMessage = nil
        statusMessage = nil
        addingCommunityID = community.id
        isAdding = true
        defer {
            isAdding = false
            addingCommunityID = nil
        }
        do {
            let addon = try await registry.install(manifestURL: community.manifestURL)
            statusMessage = "Installed \(addon.manifest.name)"
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func addAddon() async {
        errorMessage = nil
        statusMessage = nil
        let trimmed = newAddonURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            errorMessage = "Enter a full https:// URL"
            return
        }
        isAdding = true
        defer { isAdding = false }
        do {
            let addon = try await registry.install(manifestURL: url)
            statusMessage = "Installed \(addon.manifest.name)"
            newAddonURL = ""
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct AddonRow: View {
    let addon: InstalledAddon
    let isPendingRemoval: Bool
    let onToggle: (Bool) -> Void
    let onRemoveTapped: () -> Void
    let onRemoveConfirmed: () -> Void
    let onRemoveCancelled: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(addon.manifest.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                if let description = addon.manifest.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
                Text(addon.manifestURL.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if isPendingRemoval {
                HStack(spacing: 12) {
                    Button("Cancel", action: onRemoveCancelled)
                    Button(role: .destructive, action: onRemoveConfirmed) {
                        Text("Confirm")
                    }
                }
                .font(.callout.weight(.semibold))
            } else {
                Toggle("Enabled", isOn: Binding(get: { addon.enabled }, set: onToggle))
                    .labelsHidden()
                Button(action: onRemoveTapped) {
                    Image(systemName: "trash")
                        .foregroundStyle(theme.destructive)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.rowHorizontal)
        .padding(.vertical, Theme.Spacing.rowVertical)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(theme.cardRest)
        )
    }
}
