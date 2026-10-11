//
//  GoalEnhancements.swift
//  Ahorro
//
//  Hitos, simulador, motivo de ahorro y controles rápidos por meta.
//

import Foundation
import SwiftUI

private enum GoalEnhancementFormat {
    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_EC")
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy"
        return formatter
    }()

    static func amount(from text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(cleaned), amount.isFinite, amount > 0 else { return nil }
        return amount
    }

    static func editableAmount(_ amount: Double) -> String {
        amount.rounded() == amount ? String(Int(amount)) : String(format: "%.2f", amount)
    }
}

// MARK: - Hitos

private struct GoalMilestone: Identifiable {
    let id: String
    let title: String
    let amount: Double
    let iconName: String

    static func forGoal(_ goal: Goal) -> [GoalMilestone] {
        var candidates: [GoalMilestone] = []
        if goal.target >= 500 {
            candidates.append(.init(id: "first-500", title: "Primer 500", amount: 500, iconName: "flag.fill"))
        }
        candidates += [
            .init(id: "half", title: "50% completado", amount: goal.target * 0.5, iconName: "chart.bar.fill"),
            .init(id: "three-quarters", title: "75% completado", amount: goal.target * 0.75, iconName: "sparkles"),
            .init(id: "complete", title: "Meta completada", amount: goal.target, iconName: "checkmark.seal.fill")
        ]

        // Evita mostrar dos veces el mismo importe cuando la meta es, por
        // ejemplo, exactamente 500. Conservamos el primer hito con ese valor.
        var seen = Set<Int>()
        return candidates.filter { seen.insert(Int(($0.amount * 100).rounded())).inserted }
    }
}

struct GoalMilestonesCard: View {
    @EnvironmentObject private var settings: AppSettings
    let goal: Goal

    private var milestones: [GoalMilestone] { GoalMilestone.forGoal(goal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("HITOS", systemImage: "flag.checkered")
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundColor(.mutedC)
                Spacer()
                Text("\(milestones.filter { goal.saved >= $0.amount }.count)/\(milestones.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(goal.resolvedGoalTheme.deepTint)
            }

            ForEach(milestones) { milestone in
                let completed = goal.saved >= milestone.amount
                HStack(spacing: 11) {
                    Image(systemName: completed ? "checkmark.circle.fill" : milestone.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(completed ? goal.resolvedGoalTheme.deepTint : .mutedC)
                        .frame(width: 30, height: 30)
                        .background((completed ? goal.resolvedGoalTheme.tint : Color.surface2).opacity(completed ? 0.18 : 1))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(milestone.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(completed ? .textC : .mutedC)
                        Text(completed ? "¡Alcanzado!" : "Al llegar a \(fmt(milestone.amount, currency: settings.currency))")
                            .font(.caption)
                            .foregroundColor(completed ? goal.resolvedGoalTheme.deepTint : .mutedC2)
                    }
                    Spacer()
                }
            }
        }
        .padding(17)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borderC))
    }
}

// MARK: - Depósitos rápidos

struct QuickDepositRow: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    let goal: Goal

    private let values: [Double] = [5, 10, 20]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("DEPÓSITO RÁPIDO")
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundColor(.mutedC)

            HStack(spacing: 9) {
                ForEach(values, id: \.self) { value in
                    Button {
                        store.addManualDeposit(goal, amount: value, note: "Depósito rápido")
                    } label: {
                        Text("+\(fmt(value, currency: settings.currency))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(goal.resolvedGoalTheme.deepTint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(goal.resolvedGoalTheme.tint.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Añadir \(fmt(value, currency: settings.currency))")
                }
            }
        }
    }
}

// MARK: - Simulador

struct SavingsSimulatorCard: View {
    @EnvironmentObject private var settings: AppSettings
    let goal: Goal
    @State private var weeklyText = "30"

    private var weeklyAmount: Double? { GoalEnhancementFormat.amount(from: weeklyText) }
    private var weeks: Int? {
        guard let weeklyAmount, goal.remaining > 0 else { return nil }
        return max(1, Int(ceil(goal.remaining / weeklyAmount)))
    }
    private var finishDate: Date? {
        guard let weeks else { return nil }
        return Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Simulador", systemImage: "calendar.badge.clock")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.textC)

            if goal.remaining <= 0 {
                Label("Esta meta ya está completada.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundColor(goal.resolvedGoalTheme.deepTint)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Si ahorro")
                        .font(.footnote)
                        .foregroundColor(.mutedC)
                    TextField("30", text: $weeklyText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.textC)
                        .frame(width: 82)
                        .padding(.vertical, 7)
                        .background(Color.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("cada semana")
                        .font(.footnote)
                        .foregroundColor(.mutedC)
                    Spacer(minLength: 0)
                }

                if let weeklyAmount, let weeks, let finishDate {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Terminas aproximadamente el")
                            .font(.caption)
                            .foregroundColor(.mutedC)
                        Text(GoalEnhancementFormat.shortDateFormatter.string(from: finishDate))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(goal.resolvedGoalTheme.deepTint)
                        Text("en \(weeks) semana\(weeks == 1 ? "" : "s") · \(fmt(weeklyAmount, currency: settings.currency)) por semana")
                            .font(.caption)
                            .foregroundColor(.mutedC2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(goal.resolvedGoalTheme.tint.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                } else {
                    Text("Ingresa un monto semanal válido para calcular una fecha.")
                        .font(.caption)
                        .foregroundColor(.dangerC)
                }
            }
        }
        .padding(17)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borderC))
    }
}

// MARK: - Edición de meta y motivo

struct GoalTargetEditorSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    @State private var targetText = ""

    private var target: Double? { GoalEnhancementFormat.amount(from: targetText) }
    private var isValid: Bool { (target ?? 0) >= goal.saved }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nueva meta (\(settings.currency.currencyCode))") {
                    TextField("Ej. 1500", text: $targetText)
                        .keyboardType(.decimalPad)
                    Text("Ya ahorrado: \(fmt(goal.saved, currency: settings.currency))")
                        .font(.caption)
                        .foregroundColor(.mutedC)
                }
                Section {
                    Text("Las casillas ya marcadas y todos los depósitos se conservan. Solo redistribuimos las casillas pendientes para completar la nueva meta.")
                        .font(.footnote)
                        .foregroundColor(.mutedC)
                }
                if target != nil && !isValid {
                    Section {
                        Text("La nueva meta no puede ser menor que lo ya ahorrado.")
                            .font(.footnote)
                            .foregroundColor(.dangerC)
                    }
                }
            }
            .navigationTitle("Recalcular tabla")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let target, isValid else { return }
                        store.updateTarget(goal, target: target)
                        dismiss()
                    }
                    .disabled(target == nil || !isValid)
                }
            }
        }
        .onAppear { targetText = GoalEnhancementFormat.editableAmount(goal.target) }
    }
}

struct GoalMotivationEditorSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    @State private var motivation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Tu motivo") {
                    TextField("Ej. Mi viaje, mi hogar o tranquilidad", text: $motivation, axis: .vertical)
                        .lineLimit(3...5)
                }
                Section {
                    Text("Lo mostraremos en la portada de esta meta.")
                        .font(.footnote)
                        .foregroundColor(.mutedC)
                }
            }
            .navigationTitle("Motivo de ahorro")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        store.updateMotivation(goal, motivation: motivation)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { motivation = goal.motivation ?? "" }
    }
}
