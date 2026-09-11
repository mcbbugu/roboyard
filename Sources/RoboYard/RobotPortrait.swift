import AppKit
import SwiftUI

struct RobotPortrait: NSViewRepresentable {
    var size: CGFloat
    var tired: CGFloat = 0
    var glow: Bool = false

    func makeNSView(context: Context) -> PortraitView { PortraitView() }

    func updateNSView(_ view: PortraitView, context: Context) {
        view.bodySize = size
        view.tired = tired
        view.glow = glow
        view.needsDisplay = true
    }

    final class PortraitView: NSView {
        var bodySize: CGFloat = 16
        var tired: CGFloat = 0
        var glow = false

        override func draw(_ dirtyRect: NSRect) {
            let side = min(bounds.width, bounds.height) * 0.78
            let box = CGRect(x: (bounds.width - side) / 2,
                             y: (bounds.height - side) / 2,
                             width: side, height: side)
            RobotMark.drawBot(in: box, lid: 0, gait: 0, speed: 0, sit: tired * 0.4,
                              tired: tired, glow: glow)
        }
    }
}
