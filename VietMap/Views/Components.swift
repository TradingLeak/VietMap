import SwiftUI
import VietMapCore

enum Palette {
    static let accent = Color(red: 1, green: 0.30, blue: 0.30)
    static let mint = Color(red: 0.64, green: 0.91, blue: 0.48)
    static let amber = Color(red: 1, green: 0.72, blue: 0.28)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.06)))
    }
}
extension View { func panel() -> some View { modifier(Panel()) } }

struct PrimaryButton: View {
    let title: String
    var symbol = "arrow.up.right"
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Image(systemName: symbol); Text(title).fontWeight(.bold); Spacer(); Image(systemName: "chevron.right").font(.caption.bold()) }
                .padding(.horizontal, 20).frame(minHeight: 54)
                .foregroundStyle(.white).background(destructive ? Palette.accent.opacity(0.8) : Palette.accent, in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
    }
}

struct InformationBanner: View {
    let text: String
    var symbol = "info.circle.fill"
    var color = Palette.amber
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(14).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }
}

struct SpeedLimitSign: View {
    let limit: Int?
    var size: CGFloat = 94
    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(Palette.accent, lineWidth: size * 0.075)
            Text(limit.map(String.init) ?? "– –")
                .font(.system(size: size * 0.38, weight: .black, design: .rounded)).monospacedDigit()
                .foregroundStyle(.black).minimumScaleFactor(0.6).padding(size * 0.14)
        }.frame(width: size, height: size)
            .accessibilityLabel(limit.map { "Giới hạn \($0) ki lô mét một giờ" } ?? "Chưa biết giới hạn tốc độ")
    }
}

struct HazardRow: View {
    let item: UpcomingHazard
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.hazard.kind.symbol).font(.title3).foregroundStyle(Palette.amber)
                .frame(width: 42, height: 42).background(Palette.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.hazard.title).font(.subheadline.bold())
                if !item.hazard.name.isEmpty { Text(item.hazard.name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(max(10, Int(item.distance / 10) * 10))").font(.title3.bold().monospacedDigit())
                Text("mét phía trước").font(.caption2).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}

enum DisplayFormat {
    static func distance(_ metres: Double) -> String { metres >= 1_000 ? String(format: "%.1f km", metres / 1_000) : "\(Int(max(0, metres))) m" }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60) giờ \(minutes % 60) phút" : "\(minutes) phút"
    }
}

struct StatLabel: View {
    let value: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
