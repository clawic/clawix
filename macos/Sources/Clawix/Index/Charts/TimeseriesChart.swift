import SwiftUI

/// Minimal line chart for a single timeseries field. Charts in this
/// project are hand-drawn so they match the dark glass aesthetic
/// instead of system AppKit chart chrome.
struct TimeseriesChart: View {
    let points: [ClawJSIndexClient.HistoryPoint]
    var accent: Color = Color(red: 1.00, green: 0.71, blue: 0.42)

    private var numericPoints: [(Date, Double)] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let altFormatter = ISO8601DateFormatter()
        altFormatter.formatOptions = [.withInternetDateTime]
        var result: [(Date, Double)] = []
        for point in points {
            let date = formatter.date(from: point.validFrom) ?? altFormatter.date(from: point.validFrom)
            guard let date else { continue }
            switch point.value {
            case .number(let value):
                result.append((date, value))
            case .string(let raw):
                if let parsed = Double(raw) { result.append((date, parsed)) }
            default:
                continue
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        let pts = numericPoints
        return Group {
            if pts.count < 2 {
                emptyChart
            } else {
                ChartCanvas(points: pts, accent: accent)
            }
        }
    }

    private var emptyChart: some View {
        ContentUnavailableView(
            "Need 2+ observations",
            systemImage: "chart.line.uptrend.xyaxis",
            description: Text("Fire the Monitor or Search again to add another data point.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}

private struct ChartCanvas: View {
    let points: [(Date, Double)]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let values = points.map(\.1)
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 1
            let span = max(maxValue - minValue, 0.0001)
            let firstX = points.first!.0.timeIntervalSinceReferenceDate
            let lastX = points.last!.0.timeIntervalSinceReferenceDate
            let xSpan = max(lastX - firstX, 1)

            ZStack {
                fillPath(geo: geo.size, points: points, firstX: firstX, xSpan: xSpan, minValue: minValue, span: span)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.30), accent.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                linePath(geo: geo.size, points: points, firstX: firstX, xSpan: xSpan, minValue: minValue, span: span)
                    .stroke(accent, lineWidth: 1.6)

                ForEach(Array(points.enumerated()), id: \.offset) { _, entry in
                    let x = xCoord(entry.0, geo: geo.size, firstX: firstX, xSpan: xSpan)
                    let y = yCoord(entry.1, geo: geo.size, minValue: minValue, span: span)
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        .position(x: x, y: y)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(formatValue(maxValue))
                            .font(BodyFont.system(size: 10, wght: 500))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                        Text(formatValue(minValue))
                            .font(BodyFont.system(size: 10, wght: 500))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .padding(.vertical, 2)
                    Spacer()
                }
            }
        }
    }

    private func xCoord(_ date: Date, geo: CGSize, firstX: TimeInterval, xSpan: TimeInterval) -> CGFloat {
        let normalized = (date.timeIntervalSinceReferenceDate - firstX) / xSpan
        return geo.width * CGFloat(normalized)
    }
    private func yCoord(_ value: Double, geo: CGSize, minValue: Double, span: Double) -> CGFloat {
        let normalized = (value - minValue) / span
        return geo.height * (1 - CGFloat(normalized))
    }

    private func fillPath(geo: CGSize, points: [(Date, Double)], firstX: TimeInterval, xSpan: TimeInterval, minValue: Double, span: Double) -> Path {
        var path = Path()
        let fillPoints = points.map { CGPoint(x: xCoord($0.0, geo: geo, firstX: firstX, xSpan: xSpan), y: yCoord($0.1, geo: geo, minValue: minValue, span: span)) }
        guard let first = fillPoints.first else { return path }
        path.move(to: CGPoint(x: first.x, y: geo.height))
        for point in fillPoints { path.addLine(to: point) }
        path.addLine(to: CGPoint(x: fillPoints.last?.x ?? 0, y: geo.height))
        path.closeSubpath()
        return path
    }

    private func linePath(geo: CGSize, points: [(Date, Double)], firstX: TimeInterval, xSpan: TimeInterval, minValue: Double, span: Double) -> Path {
        var path = Path()
        for (idx, entry) in points.enumerated() {
            let coord = CGPoint(x: xCoord(entry.0, geo: geo, firstX: firstX, xSpan: xSpan), y: yCoord(entry.1, geo: geo, minValue: minValue, span: span))
            if idx == 0 { path.move(to: coord) } else { path.addLine(to: coord) }
        }
        return path
    }

    private func formatValue(_ value: Double) -> String {
        if value == floor(value) { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}
