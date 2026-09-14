import AppKit
import SwiftUI

struct RobotPortrait: NSViewRepresentable {
    var size: CGFloat
    var tired: CGFloat = 0
    var glow: Bool = false
    var accent: NSColor? = nil
    var stage: Int = 0
    var energy: Double = 1

    func makeNSView(context: Context) -> PortraitView { PortraitView() }

    func updateNSView(_ view: PortraitView, context: Context) {
        view.bodySize = size
        view.tired = tired
        view.glow = glow
        view.accent = accent
        view.stage = stage
        view.energy = energy
        view.needsDisplay = true
    }

    final class PortraitView: NSView {
        var bodySize: CGFloat = 16
        var tired: CGFloat = 0
        var glow = false
        var accent: NSColor?
        var stage = 0
        var energy = 1.0

        override func draw(_ dirtyRect: NSRect) {
            let side = min(bounds.width, bounds.height) * 0.78
            let box = CGRect(x: (bounds.width - side) / 2,
                             y: (bounds.height - side) / 2,
                             width: side, height: side)
            RobotMark.drawBot(in: box, lid: 0, gait: 0, speed: 0, sit: tired * 0.4,
                              tired: tired, glow: glow,
                              accent: accent, stage: stage, energy: energy)
        }
    }
}
