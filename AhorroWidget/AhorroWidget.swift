//
//  AhorroWidget.swift
//  AhorroWidget
//

import AppIntents
import Foundation
import SwiftUI
import WidgetKit

private enum WidgetSharedData {
    static let appGroup = "group.com.personal.Ahorro"
    static let kind = "AhorroWidget"
    static let hasGoalKey = "widget.hasGoal"
    static let goalIDKey = "widget.goalID"
    static let nameKey = "widget.goalName"
    static let savedKey = "widget.saved"
    static let targetKey = "widget.target"
    static let progressKey = "widget.progress"
    static let stepsRemainingKey = "widget.stepsRemaining"
    static let nextCellIndexKey = "widget.nextCellIndex"
    static let nextCellAmountKey = "widget.nextCellAmount"
    static let pendingActionKey = "widget.pendingAction"
    static let pendingActionIDKey = "widget.pendingActionID"
    static let markNextCellAction = "markNextCell"
    static let currencyCodeKey = "widget.currencyCode"

    /// `integer(forKey:)` returns 0 for a missing value, but index 0 is a
    /// perfectly valid first cell. Keep the distinction so the button is not
    /// offered until the app has published an actual next cell.
    static func integerValue(forKey key: String, in defaults: UserDefaults?) -> Int? {
        guard let defaults, defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }
}

struct AhorroWidgetEntry: TimelineEntry {
    let date: Date
    let hasGoal: Bool
    let goalID: String
    let name: String
    let saved: Double
    let target: Double
    let progress: Double
    let stepsRemaining: Int
    let nextCellIndex: Int?
    let nextCellAmount: Double
    let pendingAction: String?
    let currencyCode: String

    var hasPendingAction: Bool { pendingAction != nil }

    var canMarkNextCell: Bool {
        hasGoal
            && !hasPendingAction
            && !goalID.isEmpty
            && target > 0
            && progress < 1
            && stepsRemaining > 0
            && nextCellIndex != nil
            && nextCellAmount > 0
    }
}

struct AhorroWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AhorroWidgetEntry {
        AhorroWidgetEntry(
            date: .now,
            hasGoal: true,
            goalID: UUID().uuidString,
            name: "Para mi moto",
            saved: 420,
            target: 1_200,
            progress: 0.35,
            stepsRemaining: 18,
            nextCellIndex: 8,
            nextCellAmount: 25,
            pendingAction: nil,
            currencyCode: "USD"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AhorroWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AhorroWidgetEntry>) -> Void) {
        // En la versión local, la app actualiza el widget mediante el App
        // Group y WidgetCenter. Así funciona sin CloudKit ni Push Notifications.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> AhorroWidgetEntry {
        let defaults = UserDefaults(suiteName: WidgetSharedData.appGroup)
        let hasGoal = defaults?.bool(forKey: WidgetSharedData.hasGoalKey) ?? false

        return AhorroWidgetEntry(
            date: .now,
            hasGoal: hasGoal,
            goalID: defaults?.string(forKey: WidgetSharedData.goalIDKey) ?? "",
            name: defaults?.string(forKey: WidgetSharedData.nameKey) ?? "Meta de ahorro",
            saved: defaults?.double(forKey: WidgetSharedData.savedKey) ?? 0,
            target: defaults?.double(forKey: WidgetSharedData.targetKey) ?? 0,
            progress: defaults?.double(forKey: WidgetSharedData.progressKey) ?? 0,
            stepsRemaining: defaults?.integer(forKey: WidgetSharedData.stepsRemainingKey) ?? 0,
            nextCellIndex: WidgetSharedData.integerValue(forKey: WidgetSharedData.nextCellIndexKey, in: defaults),
            nextCellAmount: defaults?.double(forKey: WidgetSharedData.nextCellAmountKey) ?? 0,
            pendingAction: defaults?.string(forKey: WidgetSharedData.pendingActionKey),
            currencyCode: defaults?.string(forKey: WidgetSharedData.currencyCodeKey) ?? "USD"
        )
    }

}

/// Runs inside the widget on iOS 17 and later. The app owns the source of
/// truth, so this intent publishes an optimistic widget snapshot and leaves a
/// small, validated command for `Store` to apply when Ahorro next opens.
@available(iOS 17.0, *)
struct MarkNextCellIntent: AppIntent {
    static var title: LocalizedStringResource = "Marcar siguiente"
    static var description = IntentDescription("Marca la siguiente casilla de la meta mostrada.")
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        guard
            let defaults = UserDefaults(suiteName: WidgetSharedData.appGroup),
            defaults.bool(forKey: WidgetSharedData.hasGoalKey),
            let goalID = defaults.string(forKey: WidgetSharedData.goalIDKey),
            !goalID.isEmpty,
            let nextCellIndex = WidgetSharedData.integerValue(forKey: WidgetSharedData.nextCellIndexKey, in: defaults),
            nextCellIndex >= 0,
            defaults.string(forKey: WidgetSharedData.pendingActionKey) == nil
        else {
            return .result()
        }

        let target = defaults.double(forKey: WidgetSharedData.targetKey)
        let saved = defaults.double(forKey: WidgetSharedData.savedKey)
        let progress = defaults.double(forKey: WidgetSharedData.progressKey)
        let stepsRemaining = defaults.integer(forKey: WidgetSharedData.stepsRemainingKey)
        let nextCellAmount = defaults.double(forKey: WidgetSharedData.nextCellAmountKey)

        guard target > 0, progress < 1, stepsRemaining > 0, nextCellAmount > 0 else {
            return .result()
        }

        // Retain all command context so Store can validate and apply exactly
        // this cell after the app becomes active.
        defaults.set(goalID, forKey: WidgetSharedData.goalIDKey)
        defaults.set(nextCellIndex, forKey: WidgetSharedData.nextCellIndexKey)
        defaults.set(nextCellAmount, forKey: WidgetSharedData.nextCellAmountKey)
        defaults.set(WidgetSharedData.markNextCellAction, forKey: WidgetSharedData.pendingActionKey)
        defaults.set(UUID().uuidString, forKey: WidgetSharedData.pendingActionIDKey)

        // Optimistically update the data used by the next widget timeline.
        // This makes the tap feel immediate; the app republishes the canonical
        // values after applying the pending action.
        let updatedSaved = saved + nextCellAmount
        defaults.set(updatedSaved, forKey: WidgetSharedData.savedKey)
        defaults.set(min(1, max(0, updatedSaved / target)), forKey: WidgetSharedData.progressKey)
        defaults.set(max(0, stepsRemaining - 1), forKey: WidgetSharedData.stepsRemainingKey)

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedData.kind)
        return .result()
    }
}

struct AhorroWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AhorroWidgetEntry

    var body: some View {
        if entry.hasGoal {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 9 : 12) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("META DE AHORRO")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(WidgetColors.muted)
                        Text(entry.name)
                            .font(.system(size: family == .systemSmall ? 17 : 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(WidgetColors.text)
                            .lineLimit(family == .systemSmall ? 2 : 1)
                    }
                    Spacer(minLength: 0)
                    Text("\(Int(clampedProgress * 100))%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetColors.accentStrong)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("AHORRADO")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(WidgetColors.muted)
                    Text(widgetMoney(entry.saved, currencyCode: entry.currencyCode))
                        .font(.system(size: family == .systemSmall ? 25 : 29, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetColors.text)
                }

                WidgetProgressBar(progress: clampedProgress)

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text(stepsText)
                        .lineLimit(1)
                    if family != .systemSmall {
                        Spacer(minLength: 0)
                        Text("Meta \(widgetMoney(entry.target, currencyCode: entry.currencyCode))")
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetColors.muted)

                nextCellAction
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(WidgetColors.accentStrong)
                Text("Ahorro")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetColors.text)
                Text("Crea una meta en la app para ver tu avance aquí.")
                    .font(.system(size: 13))
                    .foregroundStyle(WidgetColors.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var clampedProgress: Double { min(max(entry.progress, 0), 1) }

    private var stepsText: String {
        entry.stepsRemaining == 0
            ? "Meta completada"
            : "\(entry.stepsRemaining) \(entry.stepsRemaining == 1 ? "casilla por marcar" : "casillas por marcar")"
    }

    @ViewBuilder
    private var nextCellAction: some View {
        if entry.canMarkNextCell {
            Button(intent: MarkNextCellIntent()) {
                Label("Marcar siguiente", systemImage: "checkmark.circle.fill")
                    .font(.system(size: family == .systemSmall ? 11 : 12, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WidgetColors.accent)
            .foregroundStyle(WidgetColors.buttonText)
            .controlSize(family == .systemSmall ? .small : .regular)
        } else if entry.hasGoal, entry.hasPendingAction, clampedProgress < 1 {
            Label("Se guardará al abrir Ahorro", systemImage: "clock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetColors.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct WidgetProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(WidgetColors.accent)
                    .frame(width: max(4, geometry.size.width * progress))
            }
        }
        .frame(height: 8)
    }
}

struct AhorroWidget: Widget {
    let kind = WidgetSharedData.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AhorroWidgetProvider()) { entry in
            AhorroWidgetEntryView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("Avance de ahorro")
        .description("Consulta el avance de tu meta en el iPhone, iPad o Mac.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private enum WidgetColors {
    static let background = Color(widgetHex: "131313")
    static let text = Color(widgetHex: "EDEDEA")
    static let muted = Color(widgetHex: "98978F")
    static let accent = Color(widgetHex: "9CA890")
    static let accentStrong = Color(widgetHex: "B7C2AC")
    static let buttonText = Color(widgetHex: "15170F")
}

private extension Color {
    init(widgetHex: String) {
        let scanner = Scanner(string: widgetHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255,
            green: Double((rgb & 0x00FF00) >> 8) / 255,
            blue: Double(rgb & 0x0000FF) / 255
        )
    }
}

private func widgetMoney(_ value: Double, currencyCode: String) -> String {
    let normalizedCode = currencyCode.uppercased()
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = Locale(identifier: normalizedCode == "EUR" ? "es_ES" : normalizedCode == "MXN" ? "es_MX" : "en_US")
    formatter.currencyCode = normalizedCode
    formatter.currencySymbol = normalizedCode == "EUR" ? "€" : "$"
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "\(formatter.currencySymbol ?? "$")\(value.rounded())"
}
