import Foundation
import SwiftUI

/// A compact, dependency-free chart of a goal's deposits over time.
///
/// The line represents the accumulated amount after each movement; the top of
/// the chart is the goal target. The first point always starts at zero so a
/// single deposit still shows a meaningful progression.
struct GoalProgressChart: View {
    @EnvironmentObject private var settings: AppSettings
    let goal: Goal

    private var depositsByDate: [Deposit] {
        goal.deposits.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.date < rhs.date
        }
    }

    private var progressValues: [Double] {
        guard goal.target > 0, !depositsByDate.isEmpty else { return [] }

        var accumulated = 0.0
        let depositProgress = depositsByDate.map { deposit -> Double in
            accumulated += deposit.amount
            return min(max(accumulated / goal.target, 0), 1)
        }

        return [0] + depositProgress
    }

    private var percentage: Int {
        Int((min(max(goal.progress, 0), 1) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if progressValues.isEmpty {
                emptyChart
            } else {
                chart
            }
        }
        .padding(18)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borderC))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AVANCE DE LA META")
                    .font(.caption)
                    .tracking(1.1)
                    .foregroundColor(.mutedC)
                Text("\(fmt(goal.saved, currency: settings.currency)) ahorrado")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.textC)
            }

            Spacer()

            Text("\(percentage)%")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.accentStrong)
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let drawingRect = geometry.frame(in: .local).insetBy(dx: 5, dy: 10)

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.borderC.opacity(0.45))

                    GoalChartTargetLine()
                        .stroke(Color.mutedC.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 10)

                    GoalChartArea(values: progressValues)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentC.opacity(0.38), Color.accentC.opacity(0.025)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(.horizontal, 5)
                        .padding(.vertical, 10)

                    GoalChartLine(values: progressValues)
                        .stroke(Color.accentC, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 10)

                    Circle()
                        .fill(Color.accentStrong)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                        .position(GoalChartGeometry.lastPoint(for: progressValues, in: drawingRect))
                }
            }
            .frame(height: 130)

            HStack {
                Text("Inicio")
                Spacer()
                Text("Meta \(fmt(goal.target, currency: settings.currency))")
            }
            .font(.caption2)
            .foregroundColor(.mutedC2)
        }
    }

    private var emptyChart: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 21, weight: .medium))
                .foregroundColor(.mutedC)
            Text("Aún no hay movimientos")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.textC)
            Text("Registra un depósito o marca una casilla para ver tu avance.")
                .font(.caption)
                .foregroundColor(.mutedC)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private enum GoalChartGeometry {
    static func point(for value: Double, index: Int, count: Int, in rect: CGRect) -> CGPoint {
        let denominator = max(count - 1, 1)
        let x = rect.minX + rect.width * CGFloat(index) / CGFloat(denominator)
        let y = rect.maxY - rect.height * CGFloat(min(max(value, 0), 1))
        return CGPoint(x: x, y: y)
    }

    static func lastPoint(for values: [Double], in rect: CGRect) -> CGPoint {
        guard let last = values.last else { return CGPoint(x: rect.minX, y: rect.maxY) }
        return point(for: last, index: values.count - 1, count: values.count, in: rect)
    }
}

private struct GoalChartLine: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard let first = values.first else { return Path() }

        var path = Path()
        path.move(to: GoalChartGeometry.point(for: first, index: 0, count: values.count, in: rect))

        for (index, value) in values.dropFirst().enumerated() {
            path.addLine(to: GoalChartGeometry.point(for: value, index: index + 1, count: values.count, in: rect))
        }

        return path
    }
}

private struct GoalChartArea: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard let first = values.first else { return Path() }

        var path = Path()
        let start = GoalChartGeometry.point(for: first, index: 0, count: values.count, in: rect)
        path.move(to: CGPoint(x: start.x, y: rect.maxY))
        path.addLine(to: start)

        for (index, value) in values.dropFirst().enumerated() {
            path.addLine(to: GoalChartGeometry.point(for: value, index: index + 1, count: values.count, in: rect))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct GoalChartTargetLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
