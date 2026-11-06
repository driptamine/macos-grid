import Cocoa

class AppItem {
    let name: String
    let path: String
    let icon: NSImage
    var order: Int = 0

    init(name: String, path: String, icon: NSImage) {
        self.name = name
        self.path = path
        self.icon = icon
    }
}
