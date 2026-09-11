import SwiftUI

struct WarehouseView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { _ in
            let yard = Critters.shared
            let rows = yard.roster()
            let desk = rows.filter { $0.post != .warehouse }
            let rest = rows.filter { $0.post == .warehouse }.sorted { $0.charge > $1.charge }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(yard)
                    stats(yard)
                    bay(title: "桌上", caption: "点卡片叫回来。它们会爬向菜单栏，进仓库后消失。", rows: desk, empty: "桌上现在没人。")
                    bay(title: "仓库", caption: "在里面充电。满了且桌上有空位，会自己爬出来。", rows: rest, empty: "仓库空了。")
                }
                .padding(24)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private func header(_ yard: Critters) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("仓库")
                .font(.title2.bold())
            Text("编制 \(ChargeLaw.roster) 只。桌上最多 \(yard.count) 只，剩下的在这儿充电。")
                .foregroundStyle(.secondary)
            Picker("桌上最多", selection: capBinding) {
                ForEach(Critters.countChoices, id: \.self) { n in
                    Text("\(n) 只").tag(n)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
        }
    }

    private func stats(_ yard: Critters) -> some View {
        HStack(spacing: 8) {
            chip("桌上 \(yard.yardCount)/\(yard.count)")
            chip("回家路上 \(yard.homingCount)")
            chip("仓库充电 \(yard.chargingCount)")
            chip("仓库 \(yard.warehouseCount)")
            Spacer()
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.fill.tertiary, in: Capsule())
    }

    private func bay(title: String, caption: String, rows: [YardRow], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text(empty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(rows) { row in
                        WarehouseCard(row: row)
                    }
                }
            }
        }
    }

    private var capBinding: Binding<Int> {
        Binding(get: { Critters.shared.count }, set: { Critters.shared.count = $0 })
    }
}

private struct WarehouseCard: View {
    let row: YardRow

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RobotPortrait(size: max(18, row.bodySize), tired: row.tired, glow: row.post == .warehouse && row.charge < ChargeLaw.emergeAbove)
                        .frame(height: 56)
                    Text(String(format: "%02d", row.id))
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(row.name)
                    .font(.callout.weight(.medium))
                Text("\(row.code) · \(row.stage)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ChargeMeter(level: row.charge)
                Text(row.action)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(row.canToggle ? Color.accentColor : Color.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(border, lineWidth: 1)
            )
        }
        .buttonStyle(PressCardStyle())
        .disabled(!row.canToggle)
        .help(row.hint)
    }

    private var border: Color {
        switch row.post {
        case .yard: .accentColor.opacity(0.35)
        case .homing, .emerging: .orange.opacity(0.35)
        case .warehouse: .clear
        }
    }

    private func pick() {
        Critters.shared.toggle(row.id)
    }
}

private struct ChargeMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geo.size.width * CGFloat(min(1, max(0, level)))))
            }
        }
        .frame(height: 4)
    }

    private var tint: Color {
        if level <= ChargeLaw.goHomeBelow { return .red.opacity(0.85) }
        if level <= ChargeLaw.talkBelow { return .orange.opacity(0.9) }
        if level >= ChargeLaw.emergeAbove { return .green.opacity(0.85) }
        return .yellow.opacity(0.85)
    }
}

private struct PressCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
