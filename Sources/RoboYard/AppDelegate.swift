import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let robotView = RobotIconView()
    private var journalWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        Critters.shared.start()
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Critters.shared.stop()
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let visible = Critters.shared.crawlOn
        button.title = ""
        button.image = nil
        button.toolTip = visible ? "桌面机器人 · \(Critters.shared.count) 只" : "桌面机器人 · 已隐藏"
        robotView.isActive = visible
        robotView.frame = button.bounds
        robotView.autoresizingMask = [.width, .height]
        if robotView.superview !== button {
            button.addSubview(robotView)
        }

        let menu = NSMenu()
        let title = NSMenuItem(title: "桌面机器人", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let show = NSMenuItem(title: "显示机器人", action: #selector(toggleCrawl), keyEquivalent: "h")
        show.target = self
        show.state = visible ? .on : .off
        menu.addItem(show)
        menu.addItem(countMenu())
        let journal = NSMenuItem(title: "成长记录…", action: #selector(openJournal), keyEquivalent: "j")
        journal.target = self
        menu.addItem(journal)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func countMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "数量：\(Critters.shared.count)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for n in Critters.countChoices {
            let row = NSMenuItem(title: "\(n) 只", action: #selector(pickCount(_:)), keyEquivalent: "")
            row.target = self
            row.tag = n
            row.state = n == Critters.shared.count ? .on : .off
            sub.addItem(row)
        }
        item.submenu = sub
        return item
    }

    @objc private func pickCount(_ sender: NSMenuItem) {
        Critters.shared.count = sender.tag
        refresh()
    }

    @objc private func toggleCrawl() {
        Critters.shared.crawlOn.toggle()
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc func openJournal() {
        if journalWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "机器人的成长记录"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: RobotJournalView())
            window.center()
            journalWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        journalWindow?.makeKeyAndOrderFront(nil)
    }
}
