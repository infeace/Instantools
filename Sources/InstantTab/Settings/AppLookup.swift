import AppKit

@MainActor
final class AppLookup {
    struct Info {
        var name: String
        var icon: NSImage?
        var isInstalled: Bool
    }

    private var cache: [String: Info] = [:]

    func info(for bundleId: String) -> Info {
        let key = bundleId.lowercased()
        if let cached = cache[key] { return cached }
        let info = resolve(bundleId)
        cache[key] = info
        return info
    }

    private func resolve(_ bundleId: String) -> Info {
        if bundleId.hasSuffix("*") {
            return Info(name: "Apps starting with \(bundleId.dropLast())", icon: nil, isInstalled: true)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return Info(name: Self.name(of: url), icon: NSWorkspace.shared.icon(forFile: url.path), isInstalled: true)
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            return Info(name: app.localizedName ?? bundleId, icon: app.icon, isInstalled: true)
        }
        return Info(name: bundleId, icon: nil, isInstalled: false)
    }

    static func name(of url: URL) -> String {
        let bundle = Bundle(url: url)
        return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    static func menuIcon(_ image: NSImage?) -> NSImage? {
        guard let copy = image?.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}
