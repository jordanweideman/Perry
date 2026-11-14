import AppKit
import PerryCore

enum SpriteLoader {
    /// Loads Sprites/<Config.character>/<role>/*.png. `PERRY_SPRITES=/path/to/character` overrides.
    static func load() -> [String: [NSImage]] {
        let env = ProcessInfo.processInfo.environment["PERRY_SPRITES"].map { URL(fileURLWithPath: $0) }
        let candidates = [env,
                          Bundle.main.resourceURL?.appendingPathComponent("Sprites/\(Config.character)"),
                          URL(fileURLWithPath: "Sprites/\(Config.character)")].compactMap { $0 }
        guard let root = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            dlog("no Sprites folder found in \(candidates.map(\.path))")
            return [:]
        }
        var out: [String: [NSImage]] = [:]
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { !$0.hasPrefix(".") }
        for name in names {
            let dir = root.appendingPathComponent(name)
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { $0.hasSuffix(".png") }.sorted()
            out[name] = files.compactMap { NSImage(contentsOf: dir.appendingPathComponent($0)) }
        }
        dlog("sprites from \(root.path): \(out.mapValues { $0.count })")
        return out
    }
}
