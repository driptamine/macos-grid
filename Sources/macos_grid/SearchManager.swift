import Cocoa

class SearchManager {
    private var allApps: [AppItem] = []

    var onResults: (([AppItem]) -> Void)?

    func loadApps() {
        DispatchQueue.global().async { [weak self] in
            var apps: [AppItem] = []
            let dirs = [
                "/Applications",
                "/System/Applications",
                "/System/Library/CoreServices",
                NSHomeDirectory() + "/Applications",
            ]

            for dir in dirs {
                let url = URL(fileURLWithPath: dir)
                guard let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isApplicationKey, .localizedNameKey],
                    options: [.skipsPackageDescendants, .skipsHiddenFiles]
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    guard fileURL.pathExtension == "app" else { continue }
                    let name = fileURL.deletingPathExtension().lastPathComponent
                    let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
                    apps.append(AppItem(name: name, path: fileURL.path, icon: icon))
                }
            }

            apps.sort { $0.name.lowercased() < $1.name.lowercased() }
            for (i, app) in apps.enumerated() { app.order = i }

            DispatchQueue.main.async {
                self?.allApps = apps
                self?.onResults?(apps)
            }
        }
    }

    func search(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            onResults?(allApps)
            return
        }

        let filtered = allApps.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
        }
        onResults?(filtered)
    }
}
