import AppKit
import SwiftUI

struct RobotJournalView: View {
    @ObservedObject private var voice = Voice.shared
    private let store: RobotMemoryStore

    init(store: RobotMemoryStore = .shared) {
        self.store = store
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            let copy = Copy.ui
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(copy.journalLead)
                            .font(.title2.bold())
                        Text(copy.journalBlurb)
                            .foregroundStyle(.secondary)
                        Text(copy.journalLadder)
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
                                    Text(copy.journalMeta(code: profile.mbti.code, chars: profile.textCount.formatted(), events: profile.experienceCount.formatted()))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    if let colonist = Critters.shared.colonists.first(where: { $0.id == profile.id }) {
                                        HStack(spacing: 8) {
                                            ProgressView(value: colonist.charge)
                                                .progressViewStyle(.linear)
                                                .frame(width: 88)
                                            Text(copy.chargeLine(Int(colonist.charge * 100), post: colonist.post.title))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
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
                                Text(copy.noMemories)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    }
                    Text(copy.journalFoot)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 520, minHeight: 400)
        .id(voice.stamp)
    }
}
