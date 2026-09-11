import AppKit
import SwiftUI

struct RobotJournalView: View {
    private let store: RobotMemoryStore

    init(store: RobotMemoryStore = .shared) { self.store = store }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("它们正在成为自己")
                            .font(.title2.bold())
                        Text("经历写成文字，文字成为身体。成长由累计文本量决定。")
                            .foregroundStyle(.secondary)
                        Text("初生 → 2 千字·好奇 → 2 万字·沉思 → 10 万字·觉醒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = store.errorMessage {
                        Text(error).font(.callout).foregroundStyle(.orange)
                    }

                    ForEach(store.profiles) { profile in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                RobotPortrait(size: profile.bodySize())
                                    .frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(profile.name) · \(profile.stage().title)")
                                        .font(.headline)
                                    Text("\(profile.mbti.code) · \(profile.textCount.formatted()) 字 · \(profile.experienceCount.formatted()) 段经历")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            if let thought = profile.lastThought {
                                Text("“\(thought)”")
                                    .font(.callout)
                            }
                            ForEach(profile.experiences.suffix(3).reversed()) { memory in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(memory.date, style: .time)
                                        .monospacedDigit()
                                        .foregroundStyle(.tertiary)
                                    Text(memory.detail)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                            if profile.experiences.isEmpty {
                                Text("还没有写下第一段经历。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    }
                    Text("减少显示数量不会抹掉记忆。原始经历保存在本机，模型每次只读取少量相关片段。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}

private struct RobotPortrait: NSViewRepresentable {
    let size: CGFloat

    func makeNSView(context: Context) -> PortraitView { PortraitView() }

    func updateNSView(_ view: PortraitView, context: Context) {
        view.bodySize = size
        view.needsDisplay = true
    }

    final class PortraitView: NSView {
        var bodySize: CGFloat = 16

        override func draw(_ dirtyRect: NSRect) {
            let box = CGRect(x: (bounds.width - bodySize) / 2,
                             y: (bounds.height - bodySize) / 2,
                             width: bodySize, height: bodySize)
            RobotMark.drawBot(in: box, lid: 0, gait: 0, speed: 0)
        }
    }
}
