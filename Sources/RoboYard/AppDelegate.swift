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
        maybeOnboard()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Critters.shared.stop()
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let visible = Critters.shared.crawlOn
        button.title = ""
        button.image = nil
        let copy = Copy.ui
        button.toolTip = visible ? Critters.shared.summaryLine : copy.hidden
        robotView.isActive = visible
        robotView.frame = button.bounds
        robotView.autoresizingMask = [.width, .height]
        if robotView.superview !== button {
            button.addSubview(robotView)
        }

        let menu = NSMenu()
        let title = NSMenuItem(title: copy.appName, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let summary = NSMenuItem(title: Critters.shared.summaryLine, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        summary.tag = 98
        menu.addItem(summary)
        menu.addItem(.separator())

        let show = NSMenuItem(title: copy.showRobots, action: #selector(toggleCrawl), keyEquivalent: "h")
        show.target = self
        show.state = visible ? .on : .off
        menu.addItem(show)
        let saver = NSMenuItem(title: copy.powerSaver, action: #selector(toggleSaver), keyEquivalent: "")
        saver.target = self
        saver.state = Critters.shared.powerSaver ? .on : .off
        saver.toolTip = copy.powerHint
        menu.addItem(saver)
        let shareApp = NSMenuItem(title: copy.shareAppName, action: #selector(toggleShareApp), keyEquivalent: "")
        shareApp.target = self
        shareApp.state = CritterTalk.shared.shareAppName ? .on : .off
        shareApp.toolTip = copy.shareAppHint
        menu.addItem(shareApp)
        let pet = NSMenuItem(title: copy.petClick, action: #selector(togglePetClick), keyEquivalent: "")
        pet.target = self
        pet.state = Critters.shared.petClick ? .on : .off
        pet.toolTip = copy.petHint
        menu.addItem(pet)
        let left = Critters.shared.feedCooldownLeft()
        let feed = NSMenuItem(title: left == 0 ? copy.feedDesk : copy.feedWait(left),
                              action: #selector(feedDesk), keyEquivalent: "f")
        feed.target = self
        feed.isEnabled = left == 0
        menu.addItem(feed)
        let quiet = NSMenuItem(title: copy.quietNights, action: #selector(toggleQuiet), keyEquivalent: "")
        quiet.target = self
        quiet.state = Critters.shared.quietNights ? .on : .off
        quiet.toolTip = copy.quietHint
        menu.addItem(quiet)
        menu.addItem(countMenu())
        let yard = NSMenuItem(title: copy.warehouseMenu, action: #selector(openWarehouse), keyEquivalent: "y")
        yard.target = self
        menu.addItem(yard)
        let journal = NSMenuItem(title: copy.journalMenu, action: #selector(openJournal), keyEquivalent: "j")
        journal.target = self
        menu.addItem(journal)
        menu.addItem(.separator())
        addTalkItems(to: menu)
        menu.addItem(languageMenu())
        menu.addItem(.separator())

        let quit = NSMenuItem(title: copy.quit, action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
        journalWindow?.title = copy.journalTitle
        warehouseWindow?.title = copy.warehouseTitle
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
        let copy = Copy.ui
        let item = NSMenuItem(title: copy.deskCap(Critters.shared.count), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for n in Critters.countChoices {
            let row = NSMenuItem(title: copy.countLabel(n), action: #selector(pickCount(_:)), keyEquivalent: "")
            row.target = self
            row.tag = n
            row.state = n == Critters.shared.count ? .on : .off
            sub.addItem(row)
        }
        item.submenu = sub
        return item
    }

    private func languageMenu() -> NSMenuItem {
        let copy = Copy.ui
        let item = NSMenuItem(title: copy.language, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for lang in AppLang.allCases {
            let row = NSMenuItem(title: lang.label, action: #selector(pickLang(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = lang.rawValue
            row.state = lang == AppLang.current ? .on : .off
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
        let copy = Copy.ui
        let local = NSMenuItem(title: copy.useOllama, action: #selector(pickProvider(_:)), keyEquivalent: "")
        local.target = self
        local.tag = 0
        local.state = talk.provider == .ollama ? .on : .off
        menu.addItem(local)
        let cloud = NSMenuItem(title: copy.useDeepSeek, action: #selector(pickProvider(_:)), keyEquivalent: "")
        cloud.target = self
        cloud.tag = 1
        cloud.state = talk.provider == .deepseek ? .on : .off
        menu.addItem(cloud)
        let edit = NSMenuItem(title: copy.editKey, action: #selector(editTalk), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
    }

    @objc private func pickProvider(_ sender: NSMenuItem) {
        let talk = CritterTalk.shared
        if sender.tag == 1 {
            if talk.apiKey.isEmpty {
                editTalk()
                return
            }
            guard confirmCloud() else { return }
            talk.provider = .deepseek
        } else {
            talk.provider = .ollama
        }
        Task { @MainActor in
            await talk.refreshStatus()
            refresh()
        }
    }

    @objc private func pickLang(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let lang = AppLang(rawValue: raw) else { return }
        Voice.shared.set(lang)
        refresh()
    }

    @objc private func pickCount(_ sender: NSMenuItem) {
        Critters.shared.count = sender.tag
        refresh()
    }

    @objc private func toggleCrawl() {
        Critters.shared.crawlOn.toggle()
        refresh()
    }

    @objc private func toggleSaver() {
        Critters.shared.powerSaver.toggle()
        refresh()
    }

    @objc private func toggleShareApp() {
        CritterTalk.shared.shareAppName.toggle()
        refresh()
    }

    @objc private func togglePetClick() {
        Critters.shared.petClick.toggle()
        refresh()
    }

    @objc private func feedDesk() {
        Critters.shared.feedDesk()
        refresh()
    }

    @objc private func toggleQuiet() {
        Critters.shared.quietNights.toggle()
        refresh()
    }

    private func maybeOnboard() {
        guard UserDefaults.standard.object(forKey: Rhythm.onboardKey) == nil else { return }
        UserDefaults.standard.set(true, forKey: Rhythm.onboardKey)
        let copy = Copy.ui
        let alert = NSAlert()
        alert.messageText = copy.onboardTitle
        alert.informativeText = copy.onboardBody
        alert.addButton(withTitle: copy.ok)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func confirmCloud() -> Bool {
        let copy = Copy.ui
        let alert = NSAlert()
        alert.messageText = copy.cloudTitle
        alert.informativeText = copy.cloudBody
        alert.addButton(withTitle: copy.continueCloud)
        alert.addButton(withTitle: copy.cancel)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func editTalk() {
        let copy = Copy.ui
        let talk = CritterTalk.shared
        let alert = NSAlert()
        alert.messageText = copy.talkSource
        alert.informativeText = copy.talkInfo
        let source = NSPopUpButton(frame: NSRect(x: 0, y: 84, width: 320, height: 24), pullsDown: false)
        source.addItems(withTitles: [copy.localOllama, copy.cloudDeepSeek])
        source.selectItem(at: talk.provider == .deepseek ? 1 : 0)
        let modelField = NSTextField(string: talk.model)
        modelField.placeholderString = talk.provider == .deepseek ? CritterTalk.defaultCloudModel : CritterTalk.defaultModel
        modelField.frame = NSRect(x: 0, y: 56, width: 320, height: 24)
        let endpointField = NSTextField(string: talk.endpoint)
        endpointField.placeholderString = copy.ollamaAddr
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
        alert.addButton(withTitle: copy.ok)
        alert.addButton(withTitle: copy.cancel)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let selected: CritterTalk.Provider = source.indexOfSelectedItem == 1 ? .deepseek : .ollama
        if selected == .deepseek, talk.provider != .deepseek {
            guard confirmCloud() else { return }
        }
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
            window.title = Copy.ui.journalTitle
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
            window.title = Copy.ui.warehouseTitle
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WarehouseView())
            window.center()
            warehouseWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        warehouseWindow?.makeKeyAndOrderFront(nil)
    }
}
