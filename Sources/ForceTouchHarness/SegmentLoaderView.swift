import SwiftUI

/// Color for segment `index` (0-based) of `count`: green through amber to red.
func segmentColor(_ index: Int, of count: Int) -> Color {
    let t = count > 1 ? Double(index) / Double(count - 1) : 0
    return Color(hue: 0.38 * (1 - t), saturation: 0.85, brightness: 0.95)
}

private let inactiveColor = Color.gray.opacity(0.18)

/// A row of `count` segments; the first `level` are lit.
struct LinearSegmentLoader: View {
    let level: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(index < level ? segmentColor(index, of: count) : inactiveColor)
                    .shadow(color: index < level ? segmentColor(index, of: count).opacity(0.6) : .clear, radius: 6)
            }
        }
        .frame(height: 44)
        // No animation, so the bar redraws on the same frame as the level change.
        .transaction { $0.animation = nil }
    }
}

/// A ring of `count` arc segments; the first `level` are lit.
struct CircularSegmentLoader: View {
    let level: Int
    let count: Int

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let gap = 0.012
                let start = Double(index) / Double(count) + gap / 2
                let end = Double(index + 1) / Double(count) - gap / 2
                Circle()
                    .trim(from: CGFloat(start), to: CGFloat(end))
                    .stroke(
                        index < level ? segmentColor(index, of: count) : inactiveColor,
                        style: StrokeStyle(lineWidth: 18, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(12)
        .transaction { $0.animation = nil }
    }
}
