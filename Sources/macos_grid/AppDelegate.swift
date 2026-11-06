import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: SearchPanelController?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyID = EventHotKeyID()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        panelController = SearchPanelController()
        setupStatusBar()
        registerHotKey()
        panelController?.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return true
    }

    private func setupMainMenu() {
        let appMenu = NSMenuItem()
        appMenu.submenu = NSMenu(title: "GridOS")

        let hideItem = NSMenuItem(title: "Hide GridOS", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.submenu?.addItem(hideItem)

        appMenu.submenu?.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit GridOS", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.submenu?.addItem(quitItem)

        let menu = NSMenu(title: "GridOS")
        menu.addItem(appMenu)
        NSApp.mainMenu = menu
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: 24)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Grid Search")
            button.image?.isTemplate = true
            button.action = #selector(togglePanel)
            button.target = self
        }
        statusItem = item
    }

    @objc private func togglePanel() {
        guard let event = NSApp.currentEvent, event.type == .leftMouseUp else {
            showContextMenu()
            return
        }
        panelController?.toggle()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Grid", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.button?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.button?.menu = nil
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func registerHotKey() {
        let keyCode: UInt32 = 49
        let modifiers: UInt32 = UInt32(optionKey) | UInt32(cmdKey)

        hotKeyID.id = 1
        hotKeyID.signature = fourCharCode("GRID")

        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                (NSApplication.shared.delegate as? AppDelegate)?.panelController?.toggle()
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }
}

private func fourCharCode(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for char in string.utf8 {
        result = (result << 8) + UInt32(char)
    }
    return result
}
