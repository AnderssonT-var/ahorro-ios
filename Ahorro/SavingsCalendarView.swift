//
//  SavingsCalendarView.swift
//  Ahorro
//
//  Calendario compacto y reutilizable de actividad por meta.
//

import SwiftUI

/// Muestra cuatro semanas de actividad de una meta. Cada día con movimientos
/// enseña el total ahorrado ese día y permite reconocer rápidamente la racha.
///
/// La vista no modifica la meta: se puede reutilizar tanto en el detalle como
/// en resúmenes o reportes dentro de la aplicación.
struct SavingsCalendarView: View {
    @EnvironmentObject private var settings: AppSettings

    let goal: Goal
    let weeksToShow: Int

    init(goal: Goal, weeksToShow: Int = 4) {
        self.goal = goal
        self.weeksToShow = max(3, weeksToShow)
    }

    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale(identifier: "es_EC")
        return calendar
    }

    /// Son las últimas cuatro semanas completas de días hasta hoy, sin celdas
    /// futuras. Los encabezados se rotan para que cada fecha conserve su día
    /// real de la semana aunque el intervalo empiece a mitad de una semana.
    private var startDate: Date {
        let today = calendar.startOfDay(for: Date())
        let daysBeforeToday = weeksToShow * 7 - 1
        return calendar.date(byAdding: .day, value: -daysBeforeToday, to: today) ?? today
    }

    private var dates: [Date] {
        let numberOfDays = weeksToShow * 7
        return (0..<numberOfDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: startDate)
        }
    }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var dailyTotals: [Date: Double] {
        goal.deposits.reduce(into: [:]) { totals, deposit in
            let day = calendar.startOfDay(for: deposit.date)
            totals[day, default: 0] += deposit.amount
        }
    }

    /// Una racha requiere haber ahorrado hoy; así el valor no promete una
    /// continuidad que ya se interrumpió.
    private var currentStreak: Int {
        var streak = 0
        var day = today

        while (dailyTotals[day] ?? 0) > 0 {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }

        return streak
    }

    private var activeDays: Int {
        dates.filter { (dailyTotals[$0] ?? 0) > 0 }.count
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = max(calendar.component(.weekday, from: startDate) - 1, 0)
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var visibleMonthRange: String {
        let formatter = DateIntervalFormatter()
        formatter.locale = Locale(identifier: "es_EC")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        guard let lastDate = dates.last else { return "" }
        return formatter.string(from: startDate, to: lastDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(spacing: 8) {
                weekdayHeader

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7),
                    spacing: 5
                ) {
                    ForEach(dates, id: \.self) { date in
                        SavingsCalendarDayCell(
                            date: date,
                            amount: dailyTotals[date] ?? 0,
                            isToday: calendar.isDate(date, inSameDayAs: today),
                            isFuture: date > today,
                            calendar: calendar,
                            currency: settings.currency
                        )
                    }
                }
            }

            HStack(spacing: 12) {
                CalendarMetric(
                    icon: "flame.fill",
                    title: "Racha actual",
                    value: currentStreak == 1 ? "1 día" : "\(currentStreak) días",
                    tint: currentStreak > 0 ? .accentStrong : .mutedC
                )

                Divider()
                    .frame(height: 34)

                CalendarMetric(
                    icon: "calendar.badge.checkmark",
                    title: "Días con ahorro",
                    value: activeDays == 1 ? "1 día" : "\(activeDays) días",
                    tint: .accentStrong
                )
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borderC))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendario de ahorro de \(goal.name). \(currentStreak) días de racha actual y \(activeDays) días con ahorro.")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CALENDARIO DE AHORRO")
                    .font(.caption)
                    .tracking(1.1)
                    .foregroundColor(.mutedC)

                Text(visibleMonthRange)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.textC)
            }

            Spacer()

            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentStrong)
                .frame(width: 34, height: 34)
                .background(Color.accentC.opacity(0.14))
                .clipShape(Circle())
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 5) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.mutedC2)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct SavingsCalendarDayCell: View {
    let date: Date
    let amount: Double
    let isToday: Bool
    let isFuture: Bool
    let calendar: Calendar
    let currency: AppCurrency

    private var hasActivity: Bool { amount > 0 }

    private var amountText: String {
        guard hasActivity else { return "" }

        if amount >= 1_000 {
            let compact = (amount / 1_000 * 10).rounded() / 10
            return "\(currency.symbol)\(compact.formatted(.number.precision(.fractionLength(compact.rounded() == compact ? 0 : 1))))k"
        }

        return currency.formatted(amount)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 11, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundColor(dayForeground)

            if hasActivity {
                Text(amountText)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundColor(.accentStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 3, height: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 39)
        .background(cellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isToday ? Color.accentC.opacity(0.78) : Color.clear, lineWidth: 1.2)
        )
        .opacity(isFuture ? 0.36 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var cellBackground: Color {
        if hasActivity { return Color.accentC.opacity(0.17) }
        if isToday { return Color.surface2 }
        return Color.borderC.opacity(0.3)
    }

    private var dayForeground: Color {
        if isFuture { return .mutedC2 }
        if isToday { return .accentStrong }
        return .textC
    }

    private var accessibilityDescription: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_EC")
        formatter.dateStyle = .full
        let dateText = formatter.string(from: date)

        if hasActivity {
            return "\(dateText), ahorraste \(currency.formatted(amount))"
        }

        return "\(dateText), sin ahorro registrado"
    }
}

private struct CalendarMetric: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.mutedC)
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.textC)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
