extension StremioManifest {
    /// Whether the add-on answers `resource` for this type and id. The short form, a bare name, takes the
    /// manifest's types and id prefixes; the full form uses only its own, any id when it lists none.
    func provides(_ resource: String, type: String, id: String) -> Bool {
        (resources ?? []).contains { entry in
            guard entry.name == resource else { return false }
            // Saved manifests store the short form as an entry with neither list.
            let isShortForm = entry.types == nil && entry.idPrefixes == nil
            let types = isShortForm ? types : entry.types
            let prefixes = isShortForm ? idPrefixes : entry.idPrefixes
            guard let types, types.contains(type) else { return false }
            guard let prefixes, !prefixes.isEmpty else { return true }
            return prefixes.contains { id.hasPrefix($0) }
        }
    }
}
