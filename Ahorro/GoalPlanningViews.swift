//
//  GoalPlanningViews.swift
//  Ahorro
//
//  Vistas reutilizables para planificar una meta: fecha límite, ritmo de
//  ahorro, depósitos recurrentes y edición de movimientos manuales.
//

import Foundation
import SwiftUI

// MARK: - Formato y cálculos de planificación

private enum GoalPlanningFormat {
    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_EC")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_EC")
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy"
        return formatter
    }()

    static func editableAmount(_ amount: Double) -> String {
        if amount.rounded() == amount {
            return String(Int(amount))
        }
        return String(format: "%.2f", amount)
    }

    /// Acepta punto o coma como separador decimal, que es más cómodo en
    /// teclados configurados en español.
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
}

private struct GoalDeadlineMetrics {
    let daysRemaining: Int
    let weeklyAmount: Double

    init(goal: Goal, calendar: Calendar = .current, now: Date = Date()) {
        guard let deadline = goal.deadline else {
            daysRemaining = 0
            weeklyAmount = 0
            return
        }

        let today = calendar.startOfDay(for: now)
        let dueDate = calendar.startOfDay(for: deadline)
        daysRemaining = calendar.dateComponents([.day], from: today, to: dueDate).day ?? 0

        // Cuando la fecha es hoy (o ya pasó), mostramos el total restante en
        // vez de dividir entre cero. Para un solo día, el ritmo equivale a
        // siete veces el saldo semanal, que comunica claramente la urgencia.
        let weeksAvailable = max(Double(max(daysRemaining, 1)) / 7, 1.0 / 7)
        weeklyAmount = goal.remaining / weeksAvailable
    }
}

// MARK: - Fecha límite y ritmo sugerido

/// Tarjeta compacta para el detalle de una meta. La acción de editar es
/// opcional; por eso también puede reutilizarse en una vista de resumen.
struct GoalDeadlinePaceCard: View {
    @EnvironmentObject private var settings: AppSettings

    let goal: Goal
    var onEdit: (() -> Void)? = nil

    private var metrics: GoalDeadlineMetrics? {
        goal.deadline.map { _ in GoalDeadlineMetrics(goal: goal) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center) {
                Label("Plan de ahorro", systemImage: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.textC)
                Spacer()
                editButton
            }

            if let deadline = goal.deadline, let metrics {
                deadlineSummary(deadline: deadline, metrics: metrics)
            } else {
                noDeadlineSummary
            }
        }
        .padding(17)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borderC))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var editButton: some View {
        if let onEdit {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(goal.resolvedGoalTheme.deepTint)
                    .frame(width: 32, height: 32)
                    .background(goal.resolvedGoalTheme.tint.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(goal.deadline == nil ? "Añadir fecha límite" : "Editar fecha límite")
        }
    }

    private func deadlineSummary(deadline: Date, metrics: GoalDeadlineMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FECHA LÍMITE")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.75)
                        .foregroundColor(.mutedC)
                    Text(GoalPlanningFormat.fullDateFormatter.string(from: deadline))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.textC)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                deadlineStatus(days: metrics.daysRemaining)
            }

            if goal.remaining > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(goal.resolvedGoalTheme.deepTint)
                        .frame(width: 32, height: 32)
                        .background(goal.resolvedGoalTheme.tint.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("RITMO RECOMENDADO")
                            .font(.caption2.weight(.semibold))
                            .tracking(0.7)
                            .foregroundColor(.mutedC)
                        Text("\(fmt(metrics.weeklyAmount, currency: settings.currency)) por semana")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.textC)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Label("¡Meta completada!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(goal.resolvedGoalTheme.deepTint)
            }
        }
    }

    private var noDeadlineSummary: some View {
        HStack(spacing: 11) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(goal.resolvedGoalTheme.deepTint)
                .frame(width: 35, height: 35)
                .background(goal.resolvedGoalTheme.tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sin fecha límite")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.textC)
                Text("Añade una fecha para conocer tu ritmo semanal.")
                    .font(.footnote)
                    .foregroundColor(.mutedC)
            }
            Spacer(minLength: 0)
        }
    }

    private func deadlineStatus(days: Int) -> some View {
        let label: String
        let foreground: Color
        let background: Color

        switch days {
        case ...(-1):
            label = "Vencida"
            foreground = .dangerC
            background = Color.dangerC.opacity(0.13)
        case 0:
            label = "Hoy"
            foreground = goal.resolvedGoalTheme.deepTint
            background = goal.resolvedGoalTheme.tint.opacity(0.16)
        case 1:
            label = "1 día"
            foreground = goal.resolvedGoalTheme.deepTint
            background = goal.resolvedGoalTheme.tint.opacity(0.16)
        default:
            label = "\(days) días"
            foreground = goal.resolvedGoalTheme.deepTint
            background = goal.resolvedGoalTheme.tint.opacity(0.16)
        }

        return Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(background)
            .clipShape(Capsule())
    }
}

/// Hoja para definir, cambiar o quitar la fecha límite de una meta.
struct DeadlineEditorSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let goal: Goal

    @State private var usesDeadline = false
    @State private var deadline = Date()

    private var earliestDate: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fecha objetivo") {
                    Toggle("Usar fecha límite", isOn: $usesDeadline)
                        .tint(goal.resolvedGoalTheme.tint)

                    if usesDeadline {
                        DatePicker(
                            "Fecha",
                            selection: $deadline,
                            in: earliestDate...Date.distantFuture,
                            displayedComponents: .date
                        )
                    }
                }

                Section {
                    Text(usesDeadline
                        ? "Te mostraremos el ritmo semanal sugerido y los recordatorios podrán priorizar esta meta."
                        : "Sin una fecha límite, tu meta seguirá funcionando normalmente sin un ritmo sugerido.")
                        .font(.footnote)
                        .foregroundColor(.mutedC)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Fecha límite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let date = usesDeadline ? Calendar.current.startOfDay(for: deadline) : nil
                        store.updateDeadline(goal, deadline: date)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            usesDeadline = goal.deadline != nil
            deadline = max(goal.deadline ?? earliestDate, earliestDate)
        }
    }
}

// MARK: - Depósitos recurrentes

/// Hoja común para crear una recurrencia o editar una ya existente.
struct RecurringDepositEditorSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let goal: Goal
    let recurring: RecurringDeposit?

    @State private var amountText = ""
    @State private var note = ""
    @State private var frequency: RecurrenceFrequency = .weekly
    @State private var firstDate = Date()
    @State private var isEnabled = true

    private var isEditing: Bool { recurring != nil }
    private var amount: Double? { GoalPlanningFormat.amount(from: amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Monto (\(settings.currency.currencyCode))") {
                    TextField("Ej. 25", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section("Descripción (opcional)") {
                    TextField("Ej. Ahorro de cada viernes", text: $note)
                }

                Section("Programación") {
                    Picker("Frecuencia", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    DatePicker(
                        isEditing ? "Fecha de inicio" : "Primer depósito",
                        selection: $firstDate,
                        displayedComponents: .date
                    )

                    if isEditing {
                        Toggle("Regla activa", isOn: $isEnabled)
                            .tint(goal.resolvedGoalTheme.tint)
                    }
                }

                Section {
                    Text(isEditing
                        ? "Cambiar la fecha de inicio actualiza el próximo depósito programado."
                        : "La app registra este ahorro automáticamente cuando llegue cada fecha programada.")
                        .font(.footnote)
                        .foregroundColor(.mutedC)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle(isEditing ? "Editar ahorro programado" : "Nuevo ahorro programado")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Guardar" : "Crear") {
                        save()
                    }
                    .disabled(amount == nil)
                }
            }
        }
        .onAppear(perform: loadExistingRule)
    }

    private func loadExistingRule() {
        guard let recurring else { return }
        amountText = GoalPlanningFormat.editableAmount(recurring.amount)
        note = recurring.note ?? ""
        frequency = recurring.frequency
        firstDate = recurring.firstDate
        isEnabled = recurring.isEnabled
    }

    private func save() {
        guard let amount else { return }

        if let recurring {
            store.updateRecurringDeposit(
                goal,
                recurring: recurring,
                amount: amount,
                note: note,
                frequency: frequency,
                firstDate: Calendar.current.startOfDay(for: firstDate),
                isEnabled: isEnabled
            )
        } else {
            store.addRecurringDeposit(
                goal,
                amount: amount,
                note: note,
                frequency: frequency,
                firstDate: Calendar.current.startOfDay(for: firstDate)
            )
        }
        dismiss()
    }
}

/// Sección de detalle que permite pausar, editar o borrar los ahorros
/// programados de una meta. Está diseñada para colocarse dentro de un
/// `ScrollView` sin depender de una `Form` externa.
struct RecurringDepositsSection: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings

    let goal: Goal

    @State private var showingEditor = false
    @State private var editingRule: RecurringDeposit?
    @State private var rulePendingDeletion: RecurringDeposit?

    private var orderedRules: [RecurringDeposit] {
        goal.recurringDeposits.sorted { lhs, rhs in
            if lhs.isEnabled != rhs.isEnabled { return lhs.isEnabled && !rhs.isEnabled }
            return lhs.nextDueDate < rhs.nextDueDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AHORROS PROGRAMADOS")
                        .font(.caption)
                        .tracking(1.0)
                        .foregroundColor(.mutedC)
                    Text("Automatiza aportes para esta meta")
                        .font(.footnote)
                        .foregroundColor(.mutedC2)
                }
                Spacer()
                Button {
                    editingRule = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "15170F"))
                        .frame(width: 32, height: 32)
                        .background(goal.resolvedGoalTheme.tint)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Añadir ahorro programado")
            }

            if orderedRules.isEmpty {
                emptyState
            } else {
                ForEach(orderedRules) { rule in
                    GoalRecurringRuleRow(
                        goal: goal,
                        rule: rule,
                        onEdit: {
                            editingRule = rule
                            showingEditor = true
                        },
                        onDelete: {
                            rulePendingDeletion = rule
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: { editingRule = nil }) {
            RecurringDepositEditorSheet(goal: goal, recurring: editingRule)
        }
        .confirmationDialog(
            "¿Eliminar ahorro programado?",
            isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { if !$0 { rulePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let rule = rulePendingDeletion {
                Button("Eliminar", role: .destructive) {
                    store.deleteRecurringDeposit(goal, recurring: rule)
                    rulePendingDeletion = nil
                }
            }
            Button("Cancelar", role: .cancel) { rulePendingDeletion = nil }
        } message: {
            if let rule = rulePendingDeletion {
                Text("Se dejarán de crear depósitos de \(fmt(rule.amount, currency: settings.currency)) \(rule.frequency.title.lowercased()).")
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 11) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(goal.resolvedGoalTheme.deepTint)
                .frame(width: 34, height: 34)
                .background(goal.resolvedGoalTheme.tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("Crea un aporte semanal, quincenal o mensual para no olvidarte de ahorrar.")
                .font(.footnote)
                .foregroundColor(.mutedC)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderC))
    }
}

private struct GoalRecurringRuleRow: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings

    let goal: Goal
    let rule: RecurringDeposit
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var scheduleDescription: String {
        let status = rule.isEnabled
            ? "Próximo \(GoalPlanningFormat.shortDateFormatter.string(from: rule.nextDueDate))"
            : "Pausado"
        return "\(rule.frequency.title) · \(status)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(goal.resolvedGoalTheme.deepTint)
                .frame(width: 34, height: 34)
                .background(goal.resolvedGoalTheme.tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(fmt(rule.amount, currency: settings.currency))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(rule.isEnabled ? .textC : .mutedC)

                Text(scheduleDescription)
                    .font(.caption)
                    .foregroundColor(.mutedC)

                if let note = rule.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.mutedC2)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                Toggle(
                    "Activar ahorro programado",
                    isOn: Binding(
                        get: { rule.isEnabled },
                        set: { enabled in
                            store.setRecurringDepositEnabled(goal, recurring: rule, isEnabled: enabled)
                        }
                    )
                )
                .labelsHidden()
                .tint(goal.resolvedGoalTheme.tint)
                .accessibilityLabel("Activar \(rule.frequency.title.lowercased())")

                HStack(spacing: 14) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.mutedC)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Editar ahorro programado")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.dangerC)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Eliminar ahorro programado")
                }
            }
        }
        .padding(14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderC))
        .opacity(rule.isEnabled ? 1 : 0.72)
    }
}

// MARK: - Edición de depósitos manuales

/// Permite editar con seguridad un depósito manual ya registrado. Las casillas
/// y las ocurrencias automáticas no se editan aquí, pues conservan su lógica
/// propia y su historial de programación.
struct EditManualDepositSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let goal: Goal
    let deposit: Deposit

    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var showingDeleteConfirmation = false

    private var amount: Double? { GoalPlanningFormat.amount(from: amountText) }
    private var isManualDeposit: Bool { deposit.type == .manual }

    var body: some View {
        NavigationStack {
            Group {
                if isManualDeposit {
                    editorForm
                } else {
                    unsupportedMovementState
                }
            }
            .navigationTitle("Editar depósito")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                if isManualDeposit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Guardar") { save() }
                            .disabled(amount == nil)
                    }
                }
            }
        }
        .onAppear(perform: loadDeposit)
        .alert("¿Eliminar depósito?", isPresented: $showingDeleteConfirmation) {
            Button("Cancelar", role: .cancel) { }
            Button("Eliminar", role: .destructive) {
                store.deleteManualDeposit(goal, deposit: deposit)
                dismiss()
            }
        } message: {
            Text("Este movimiento se quitará del progreso de la meta.")
        }
    }

    private var editorForm: some View {
        Form {
            Section("Monto (\(settings.currency.currencyCode))") {
                TextField("Ej. 20", text: $amountText)
                    .keyboardType(.decimalPad)
            }

            Section("Nota (opcional)") {
                TextField("Ej. Ahorro de la semana", text: $note)
            }

            Section("Fecha") {
                DatePicker("Día del depósito", selection: $date, displayedComponents: .date)
            }

            Section {
                Text("Puedes corregir el monto, la nota o la fecha de este depósito manual.")
                    .font(.footnote)
                    .foregroundColor(.mutedC)
            }

            Section {
                Button("Eliminar depósito", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
    }

    private var unsupportedMovementState: some View {
        VStack(spacing: 13) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.mutedC)
                .frame(width: 48, height: 48)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text("Este movimiento no se edita aquí")
                .font(.headline)
                .foregroundColor(.textC)
            Text("Las casillas y los depósitos programados conservan su propio registro.")
                .font(.footnote)
                .foregroundColor(.mutedC)
                .multilineTextAlignment(.center)
            Button("Cerrar") { dismiss() }
                .buttonStyle(.bordered)
                .tint(goal.resolvedGoalTheme.tint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .background(Color.bg)
    }

    private func loadDeposit() {
        amountText = GoalPlanningFormat.editableAmount(deposit.amount)
        note = deposit.note ?? ""
        date = deposit.date
    }

    private func save() {
        guard let amount else { return }
        store.updateDeposit(goal, deposit: deposit, amount: amount, note: note, date: date)
        dismiss()
    }
}
