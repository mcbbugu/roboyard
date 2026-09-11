import SwiftUI

@main
struct RoboYardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("成长记录…") { appDelegate.openJournal() }
                        .keyboardShortcut("j")
                }
            }
    }
}
