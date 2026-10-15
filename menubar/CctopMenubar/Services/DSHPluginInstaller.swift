import Foundation

/// cctop's DeepSeek Harness integration: the plugin file lives in cctop's own folder, and one
/// marked `insert` row in DSH's home patch (`~/.dsh/cordis.patch.yml`) names it. Install adds
/// that row after whatever the user already has; remove takes out exactly that row.
enum DSHPluginInstaller {
    static let beginMarker = "# cctop: begin (added by cctop; remove it in cctop's Settings)"
    static let endMarker = "# cctop: end"

    static func block(pluginPath: String) -> String {
        """
        \(beginMarker)
        - insert:
            - id: cctop
              name: \(pluginPath)
        \(endMarker)

        """
    }

    static func isInstalled(patch: String?) -> Bool {
        patch?.contains(beginMarker) == true
    }

    /// The patch with cctop's row added once, after the user's own rows. A missing, empty, or
    /// `[]` patch becomes just the row.
    static func patchAdding(pluginPath: String, to existing: String?) -> String {
        let kept = existing.map(patchRemoving) ?? ""
        guard hasRows(kept) else { return block(pluginPath: pluginPath) }
        let separated = kept.hasSuffix("\n") ? kept : kept + "\n"
        return separated + block(pluginPath: pluginPath)
    }

    /// The patch without cctop's row. A patch left with no rows becomes `[]`: DSH refuses to
    /// start on an empty or comments-only patch.
    static func patchRemoving(from existing: String) -> String {
        var lines: [Substring] = []
        var inBlock = false
        for line in existing.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == beginMarker { inBlock = true; continue }
            if inBlock {
                if line == endMarker { inBlock = false }
                continue
            }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        let kept = lines.joined(separator: "\n")
        return hasRows(kept) ? kept + "\n" : "[]\n"
    }

    /// Whether a patch has anything besides blank lines, comments, and an empty `[]` list.
    private static func hasRows(_ patch: String) -> Bool {
        patch.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#") && trimmed != "[]"
        }
    }
}
