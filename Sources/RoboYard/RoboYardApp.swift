import SwiftUI

@main
struct RoboYardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(after: .appInfo) {
                    Button(Copy.ui.journalMenu) { appDelegate.openJournal() }
                        .keyboardShortcut("j")
                }
            }
    }
}
