import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let robotView = RobotIconView()
    private var journalWindow: NSWindow?
    private var warehouseWindow: NSWindow?
    private var menuPulse: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        Critters.shared.start()
        refresh()
        Task { @MainActor in
            await CritterTalk.shared.refreshStatus()
            refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Critters.shared.stop()
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let visible = Critters.shared.crawlOn
        button.title = ""
        button.image = nil
        button.toolTip = visible ? Critters.shared.summaryLine : "桌面机器人 · 已隐藏"
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
        let summary = NSMenuItem(title: Critters.shared.summaryLine, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        summary.tag = 98
        menu.addItem(summary)
        menu.addItem(.separator())

        let show = NSMenuItem(title: "显示机器人", action: #selector(toggleCrawl), keyEquivalent: "h")
        show.target = self
        show.state = visible ? .on : .off
        menu.addItem(show)
        menu.addItem(countMenu())
        let yard = NSMenuItem(title: "仓库…", action: #selector(openWarehouse), keyEquivalent: "y")
        yard.target = self
        menu.addItem(yard)
        let journal = NSMenuItem(title: "成长记录…", action: #selector(openJournal), keyEquivalent: "j")
        journal.target = self
        menu.addItem(journal)
        menu.addItem(.separator())
        addTalkItems(to: menu)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTag: 98)?.title = Critters.shared.summaryLine
        menuPulse?.invalidate()
        menuPulse = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.statusItem.menu?.item(withTag: 98)?.title = Critters.shared.summaryLine
                self.statusItem.menu?.item(withTag: 99)?.title = CritterTalk.shared.statusLine
            }
        }
        RunLoop.main.add(menuPulse!, forMode: .common)
        Task { @MainActor in
            await CritterTalk.shared.refreshStatus()
            menu.item(withTag: 99)?.title = CritterTalk.shared.statusLine
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuPulse?.invalidate()
        menuPulse = nil
    }

    private func countMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "桌上最多：\(Critters.shared.count) 只", action: nil, keyEquivalent: "")
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

    private func addTalkItems(to menu: NSMenu) {
        let talk = CritterTalk.shared
        let status = NSMenuItem(title: talk.statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.tag = 99
        menu.addItem(status)
        let local = NSMenuItem(title: "使用本地 Ollama", action: #selector(pickProvider(_:)), keyEquivalent: "")
        local.target = self
        local.tag = 0
        local.state = talk.provider == .ollama ? .on : .off
        menu.addItem(local)
        let cloud = NSMenuItem(title: "使用云端 DeepSeek", action: #selector(pickProvider(_:)), keyEquivalent: "")
        cloud.target = self
        cloud.tag = 1
        cloud.state = talk.provider == .deepseek ? .on : .off
        menu.addItem(cloud)
        let edit = NSMenuItem(title: "填入 DeepSeek Key…", action: #selector(editTalk), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
    }

    @objc private func pickProvider(_ sender: NSMenuItem) {
        let talk = CritterTalk.shared
        if sender.tag == 1, talk.apiKey.isEmpty {
            editTalk()
            return
        }
        talk.provider = sender.tag == 1 ? .deepseek : .ollama
        Task { @MainActor in
            await talk.refreshStatus()
            refresh()
        }
    }

    @objc private func pickCount(_ sender: NSMenuItem) {
        Critters.shared.count = sender.tag
        refresh()
    }

    @objc private func toggleCrawl() {
        Critters.shared.crawlOn.toggle()
        refresh()
    }

    @objc private func editTalk() {
        let talk = CritterTalk.shared
        let alert = NSAlert()
        alert.messageText = "对话来源"
        alert.informativeText = "本地走 Ollama。云端填 DeepSeek API Key 即可，默认 deepseek-chat。没连上就沉默。云端会把台词提示发到 DeepSeek。"
        let source = NSPopUpButton(frame: NSRect(x: 0, y: 84, width: 320, height: 24), pullsDown: false)
        source.addItems(withTitles: ["本地 Ollama", "云端 DeepSeek"])
        source.selectItem(at: talk.provider == .deepseek ? 1 : 0)
        let modelField = NSTextField(string: talk.model)
        modelField.placeholderString = talk.provider == .deepseek ? CritterTalk.defaultCloudModel : CritterTalk.defaultModel
        modelField.frame = NSRect(x: 0, y: 56, width: 320, height: 24)
        let endpointField = NSTextField(string: talk.endpoint)
        endpointField.placeholderString = "Ollama 地址"
        endpointField.frame = NSRect(x: 0, y: 28, width: 320, height: 24)
        let keyField = NSSecureTextField(string: talk.apiKey)
        keyField.placeholderString = "DeepSeek API Key"
        keyField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 108))
        box.addSubview(keyField)
        box.addSubview(endpointField)
        box.addSubview(modelField)
        box.addSubview(source)
        alert.accessoryView = box
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let selected: CritterTalk.Provider = source.indexOfSelectedItem == 1 ? .deepseek : .ollama
        let typed = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        talk.provider = selected
        if selected == .deepseek {
            if !typed.isEmpty, typed != CritterTalk.defaultModel { talk.model = typed }
        } else if !typed.isEmpty, typed != CritterTalk.defaultCloudModel {
            talk.model = typed
        }
        talk.endpoint = endpointField.stringValue
        talk.apiKey = keyField.stringValue
        Task { @MainActor in
            await talk.refreshStatus()
            refresh()
        }
    }

    @objc private func quit() {
        menuPulse?.invalidate()
        Critters.shared.stop()
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

    @objc func openWarehouse() {
        if warehouseWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "仓库"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WarehouseView())
            window.center()
            warehouseWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        warehouseWindow?.makeKeyAndOrderFront(nil)
    }
}
