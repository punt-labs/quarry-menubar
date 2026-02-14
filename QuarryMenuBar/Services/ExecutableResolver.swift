import Foundation

/// Resolves the absolute path to the `quarry` CLI binary.
///
/// GUI apps don't inherit the shell's PATH, so `/usr/bin/env quarry` fails.
/// This searches well-known install locations in priority order.
enum ExecutableResolver {

    /// Well-known paths where `quarry` may be installed, checked in order.
    static let searchPaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        return [
            "\(home)/.local/bin/quarry",
            "/usr/local/bin/quarry",
            "/opt/homebrew/bin/quarry"
        ]
    }()

    /// Returns the absolute path to the quarry binary, or `nil` if not found.
    static func resolve() -> String? {
        searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
