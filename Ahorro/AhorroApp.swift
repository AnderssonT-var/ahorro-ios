//
//  AhorroApp.swift
//  Ahorro
//
//  Created by Andersson Toapanta on 11/8/26.
//

import SwiftUI
import Foundation
import Combine
import WidgetKit
import UIKit

// MARK: - Colores

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: .init(charactersIn: "#")))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255,
            green: Double((rgb & 0x00FF00) >> 8) / 255,
            blue: Double(rgb & 0x0000FF) / 255
        )
    }

    private static func adaptive(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let bg = adaptive(light: "F5F6F8", dark: "131313")
    static let surface = adaptive(light: "FFFFFF", dark: "1B1B1A")
    static let surface2 = adaptive(light: "ECEFF2", dark: "232322")
    static let borderC = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .white.withAlphaComponent(0.09)
            : .black.withAlphaComponent(0.08)
    })
    static let textC = adaptive(light: "1B1C1D", dark: "EDEDEA")
    static let mutedC = adaptive(light: "74777B", dark: "98978F")
    static let mutedC2 = adaptive(light: "8C9095", dark: "6F6E67")
    static let accentC = adaptive(light: "5E7056", dark: "9CA890")
    static let accentStrong = adaptive(light: "4D6246", dark: "B7C2AC")
    static let dangerC = adaptive(light: "B6534D", dark: "B37067")
}

private extension UIColor {
    convenience init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb & 0xFF0000) >> 16) / 255,
            green: CGFloat((rgb & 0x00FF00) >> 8) / 255,
            blue: CGFloat(rgb & 0x0000FF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Modelos y generador

enum DepositType: String, Codable {
    case cell
    case manual
    case recurring
}

/// La frecuencia con la que un depósito programado vuelve a generarse.
enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly
    case biweekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: "Semanal"
        case .biweekly: "Quincenal"
        case .monthly: "Mensual"
        }
    }

    fileprivate func nextDate(after date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .weekly:
            calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly:
            calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:
            calendar.date(byAdding: .month, value: 1, to: date)
        }
    }
}

/// Configuración persistente de un depósito que se registra con una frecuencia
/// determinada. `nextDueDate` permite retomar el calendario sin duplicar los
/// movimientos generados al volver a abrir la app.
struct RecurringDeposit: Identifiable, Codable, Equatable {
    var id: UUID
    var amount: Double
    var note: String?
    var frequency: RecurrenceFrequency
    var firstDate: Date
    var nextDueDate: Date
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        amount: Double,
        note: String? = nil,
        frequency: RecurrenceFrequency,
        firstDate: Date,
        nextDueDate: Date? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.note = note
        self.frequency = frequency
        self.firstDate = firstDate
        self.nextDueDate = nextDueDate ?? firstDate
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, amount, note, frequency, firstDate, nextDueDate, isEnabled, createdAt
    }

    /// Las versiones previas no tenían depósitos recurrentes. Aunque esta
    /// estructura sea nueva, toleramos datos incompletos para que una copia de
    /// seguridad nunca impida abrir la app.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        note = try container.decodeIfPresent(String.self, forKey: .note)
        frequency = try container.decodeIfPresent(RecurrenceFrequency.self, forKey: .frequency) ?? .weekly
        firstDate = try container.decodeIfPresent(Date.self, forKey: .firstDate) ?? Date()
        nextDueDate = try container.decodeIfPresent(Date.self, forKey: .nextDueDate) ?? firstDate
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? firstDate
    }
}

struct Deposit: Identifiable, Codable, Equatable {
    var id = UUID()
    var type: DepositType
    var idx: Int?
    var amount: Double
    var note: String?
    var date: Date

    /// Se rellena solo para movimientos creados desde una recurrencia. Junto
    /// con `recurrenceOccurrenceDate` forma una identidad estable que evita
    /// duplicados si la app se cierra durante el procesamiento.
    var recurringDepositID: UUID?
    var recurrenceOccurrenceDate: Date?

    init(
        id: UUID = UUID(),
        type: DepositType,
        idx: Int? = nil,
        amount: Double,
        note: String? = nil,
        date: Date,
        recurringDepositID: UUID? = nil,
        recurrenceOccurrenceDate: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.idx = idx
        self.amount = amount
        self.note = note
        self.date = date
        self.recurringDepositID = recurringDepositID
        self.recurrenceOccurrenceDate = recurrenceOccurrenceDate
    }
}

struct Goal: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var target: Double
    var amounts: [Double]
    /// Conserva la intención original de la tabla para poder recalcular las
    /// casillas pendientes sin arrastrar importes antiguos o ya vacíos.
    var tableStyle: TableStyle
    var deposits: [Deposit]
    var createdAt: Date
    /// Fecha de la última modificación local. Permite combinar metas que se
    /// editaron en dispositivos distintos antes de la siguiente sincronización.
    var updatedAt: Date

    /// Información opcional de las funciones nuevas. Son opcionales para que
    /// los JSON de versiones anteriores sigan decodificando sin migraciones.
    var deadline: Date?
    var iconName: String?
    var themeName: String?
    var coverImageFileName: String?
    /// Una frase corta que recuerda por qué esta meta importa. Se muestra en
    /// la portada para que acompañe el avance diario.
    var motivation: String?
    var recurringDeposits: [RecurringDeposit]

    init(
        id: UUID = UUID(),
        name: String,
        target: Double,
        amounts: [Double],
        tableStyle: TableStyle = .sequential,
        deposits: [Deposit] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deadline: Date? = nil,
        iconName: String? = nil,
        themeName: String? = nil,
        coverImageFileName: String? = nil,
        motivation: String? = nil,
        recurringDeposits: [RecurringDeposit] = []
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.amounts = amounts
        self.tableStyle = tableStyle
        self.deposits = deposits
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deadline = deadline
        self.iconName = iconName
        self.themeName = themeName
        self.coverImageFileName = coverImageFileName
        self.motivation = motivation
        self.recurringDeposits = recurringDeposits
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, target, amounts, tableStyle, deposits, createdAt, updatedAt
        case deadline, iconName, themeName, coverImageFileName, motivation, recurringDeposits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Meta de ahorro"
        target = try container.decodeIfPresent(Double.self, forKey: .target) ?? 0
        amounts = try container.decodeIfPresent([Double].self, forKey: .amounts) ?? []
        // Las tablas de las primeras versiones eran secuenciales; usar ese
        // valor por defecto además corrige automáticamente sus recálculos.
        tableStyle = try container.decodeIfPresent(TableStyle.self, forKey: .tableStyle) ?? .sequential
        deposits = try container.decodeIfPresent([Deposit].self, forKey: .deposits) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        themeName = try container.decodeIfPresent(String.self, forKey: .themeName)
        coverImageFileName = try container.decodeIfPresent(String.self, forKey: .coverImageFileName)
        motivation = try container.decodeIfPresent(String.self, forKey: .motivation)
        recurringDeposits = try container.decodeIfPresent([RecurringDeposit].self, forKey: .recurringDeposits) ?? []
    }

    var saved: Double { deposits.reduce(0) { $0 + $1.amount } }
    var progress: Double { target > 0 ? min(1, saved / target) : 0 }
    var remaining: Double { max(0, target - saved) }
    var cellsDone: Int { deposits.filter { $0.type == .cell }.count }
    func isCellDone(_ index: Int) -> Bool { deposits.contains { $0.type == .cell && $0.idx == index } }
    var activeCellIndices: [Int] {
        let indices = amounts.indices.filter { isCellDone($0) || amounts[$0] > 0.000_001 }
        // Tras un recálculo las casillas conservan su identificador interno
        // (para no alterar las marcadas), pero se presentan en orden de monto
        // para que una tabla secuencial siempre se lea de menor a mayor.
        guard tableStyle == .sequential else { return indices }
        return indices.sorted {
            amounts[$0] == amounts[$1] ? $0 < $1 : amounts[$0] < amounts[$1]
        }
    }
    var pendingCellCount: Int {
        amounts.indices.filter { !isCellDone($0) && amounts[$0] > 0.000_001 }.count
    }
}

enum TableStyle: String, CaseIterable, Codable { case sequential = "Secuencial", pattern = "Patrón variado" }

enum TableGenerator {
    static func niceRound(_ value: Double) -> Double {
        if value >= 100 { return (value / 10).rounded() * 10 }
        if value >= 20 { return (value / 5).rounded() * 5 }
        return max(1, value.rounded())
    }

    static func sequential(target: Double) -> [Double] {
        guard target > 0 else { return [] }

        // Añade el resto como una casilla independiente. El generador anterior
        // lo sumaba a la última casilla: para una meta de $1.500 podía convertir
        // el $54 final en $69, dejando una tabla que ya no era secuencial.
        let wholePart = Int(target.rounded(.down))
        var amounts: [Double] = []
        var sum = 0
        var next = 1
        while sum + next <= wholePart {
            amounts.append(Double(next))
            sum += next
            next += 1
        }

        let remainder = target - Double(sum)
        if remainder > 0.000_001 {
            amounts.append(remainder)
        }
        return amounts.sorted()
    }

    static func pattern(target: Double, count: Int) -> [Double] {
        let multipliers: [Double] = [0.5, 1, 0.25, 1, 0.5, 1, 0.75, 1, 0.75, 1]
        var amounts = (0..<count).map { niceRound(target / Double(count) * multipliers[$0 % multipliers.count]) }
        amounts[amounts.count - 1] = max(1, amounts.last! + target - amounts.reduce(0, +))
        return amounts
    }
}

// MARK: - Persistencia

@MainActor
final class Store: ObservableObject {
    @Published var goals: [Goal] = [] {
        didSet {
            save()
            publishWidgetSnapshot()
            refreshSmartReminder()
#if CLOUDKIT_SYNC
            if !isApplyingCloudSnapshot {
                scheduleCloudSync()
            }
#endif
        }
    }
    @Published private(set) var cloudSyncStatus: CloudSyncStatus = .disabled

    private var isProcessingRecurrences = false
#if CLOUDKIT_SYNC
    private var isApplyingCloudSnapshot = false
    private var cloudSyncTask: Task<Void, Never>?
    // No se instancia CKContainer en la versión local. Hacerlo incluso sin
    // sincronizar provoca un cierre al arrancar en un dispositivo firmado con
    // Personal Team, pues la app no incluye la capacidad de iCloud.
    private lazy var cloudSyncService: CloudKitSyncService? = {
        guard AppSettings.iCloudSyncAvailable else { return nil }
        return CloudKitSyncService()
    }()
    private var cloudTombstones = AhorroCloudTombstones()
    private let cloudTombstonesKey = "cloudSync.tombstones"
#endif

    private let fileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ahorro_goals.json")
    }()

    init() {
#if CLOUDKIT_SYNC
        loadCloudTombstones()
#endif
        load()
        processPendingWidgetAction()
        publishWidgetSnapshot()
        refreshSmartReminder()
    }

    func load() {
        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let savedGoals = try? decoder.decode([Goal].self, from: data) {
                var repairedGoals = savedGoals
                for index in repairedGoals.indices {
                    let before = repairedGoals[index].amounts
                    rebalancePendingCells(of: &repairedGoals[index])
                    if repairedGoals[index].amounts != before {
                        repairedGoals[index].updatedAt = Date()
                    }
                }
                goals = repairedGoals
            }
        }
        processDueRecurringDeposits()
        refreshSmartReminder()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(goals) { try? data.write(to: fileURL, options: .atomic) }
    }

    /// Activa o pausa CloudKit desde Ajustes. La primera activación descarga
    /// las metas existentes y las combina con las que ya están en este equipo.
    func setCloudSyncEnabled(_ enabled: Bool) {
#if CLOUDKIT_SYNC
        guard AppSettings.iCloudSyncAvailable else {
            AppSettings.shared.iCloudEnabled = false
            cloudSyncTask?.cancel()
            cloudSyncTask = nil
            cloudSyncStatus = .disabled
            return
        }
        guard enabled else {
            cloudSyncTask?.cancel()
            cloudSyncTask = nil
            cloudSyncStatus = .disabled
            return
        }
        syncWithICloud()
#else
        AppSettings.shared.iCloudEnabled = false
        cloudSyncStatus = .disabled
#endif
    }

    func syncWithICloud() {
#if CLOUDKIT_SYNC
        guard AppSettings.iCloudSyncAvailable, AppSettings.shared.iCloudEnabled else {
            cloudSyncStatus = .disabled
            return
        }
        guard let cloudSyncService else {
            cloudSyncStatus = .disabled
            return
        }

        cloudSyncTask?.cancel()
        let snapshot = AhorroCloudSnapshot(goals: goals, tombstones: cloudTombstones)
        let currencyCode = AppSettings.shared.currency.currencyCode
        cloudSyncStatus = .syncing

        cloudSyncTask = Task { [weak self, cloudSyncService] in
            do {
                // Agrupa los cambios consecutivos que ocurren al marcar varias
                // casillas, sin retrasar la primera sincronización perceptible.
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                let remoteSnapshot = try await cloudSyncService.synchronize(
                    localSnapshot: snapshot,
                    currencyCode: currencyCode
                )
                try Task.checkCancellation()
                self?.applyCloudSnapshot(remoteSnapshot)
            } catch is CancellationError {
                // Un cambio nuevo inicia una tarea más reciente; no mostramos
                // un error por una sincronización reemplazada intencionalmente.
            } catch {
                self?.cloudSyncStatus = .unavailable(error.localizedDescription)
            }
        }
#else
        cloudSyncStatus = .disabled
#endif
    }

    private func publishWidgetSnapshot() {
        let defaults = UserDefaults(suiteName: AhorroWidgetData.appGroup)
        let widgetGoal = goals.first(where: { $0.progress < 1 }) ?? goals.first

        guard let goal = widgetGoal else {
            defaults?.set(false, forKey: AhorroWidgetData.hasGoalKey)
            AhorroWidgetData.clearActionSnapshot(in: defaults)
            WidgetCenter.shared.reloadTimelines(ofKind: AhorroWidgetData.kind)
            return
        }

        defaults?.set(true, forKey: AhorroWidgetData.hasGoalKey)
        defaults?.set(goal.name, forKey: AhorroWidgetData.nameKey)
        defaults?.set(goal.saved, forKey: AhorroWidgetData.savedKey)
        defaults?.set(goal.target, forKey: AhorroWidgetData.targetKey)
        defaults?.set(goal.progress, forKey: AhorroWidgetData.progressKey)
        defaults?.set(goal.pendingCellCount, forKey: AhorroWidgetData.stepsRemainingKey)

        // Contrato con el widget: muestra estos valores y, para pedir que se
        // marque la siguiente casilla, escribe `markNextCell` en
        // `widget.pendingAction` (con un UUID único en pendingActionID).
        defaults?.set(goal.id.uuidString, forKey: AhorroWidgetData.goalIDKey)
        if let nextIndex = goal.activeCellIndices.first(where: { !goal.isCellDone($0) }) {
            defaults?.set(nextIndex, forKey: AhorroWidgetData.nextCellIndexKey)
            defaults?.set(goal.amounts[nextIndex], forKey: AhorroWidgetData.nextCellAmountKey)
            defaults?.set(true, forKey: AhorroWidgetData.canMarkNextCellKey)
        } else {
            defaults?.removeObject(forKey: AhorroWidgetData.nextCellIndexKey)
            defaults?.removeObject(forKey: AhorroWidgetData.nextCellAmountKey)
            defaults?.set(false, forKey: AhorroWidgetData.canMarkNextCellKey)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: AhorroWidgetData.kind)
    }

    @discardableResult
    func addGoal(
        name: String,
        target: Double,
        style: TableStyle,
        count: Int,
        deadline: Date? = nil,
        iconName: String? = nil,
        themeName: String? = nil,
        coverImageFileName: String? = nil,
        motivation: String? = nil,
        recurringDeposits: [RecurringDeposit] = []
    ) -> Goal {
        let amounts = style == .sequential ? TableGenerator.sequential(target: target) : TableGenerator.pattern(target: target, count: count)
        let goal = Goal(
            name: name.isEmpty ? "Meta de ahorro" : name,
            target: amounts.reduce(0, +),
            amounts: amounts,
            tableStyle: style,
            deadline: deadline,
            iconName: iconName,
            themeName: themeName,
            coverImageFileName: coverImageFileName,
            motivation: normalizedNote(motivation ?? ""),
            recurringDeposits: recurringDeposits
        )
        goals.insert(goal, at: 0)
        processDueRecurringDeposits()
        return goal
    }

    func deleteGoal(_ goal: Goal) {
#if CLOUDKIT_SYNC
        cloudTombstones.deletedGoals[goal.id.uuidString] = Date()
        saveCloudTombstones()
#endif
        goals.removeAll { $0.id == goal.id }
        GoalCoverStore.remove(named: goal.coverImageFileName)
        processDueRecurringDeposits()
    }

    func resetProgress(_ goal: Goal) {
        let now = Date()
        update(goal) { current in
            current.deposits.removeAll()
            // Al reiniciar, las recurrencias siguen configuradas pero no
            // recrean de inmediato todos los movimientos históricos.
            for index in current.recurringDeposits.indices where current.recurringDeposits[index].isEnabled {
                var nextDate = current.recurringDeposits[index].nextDueDate
                var safeguards = 0
                while nextDate <= now, safeguards < 10_000,
                      let followingDate = current.recurringDeposits[index].frequency.nextDate(after: nextDate, calendar: .current),
                      followingDate > nextDate {
                    nextDate = followingDate
                    safeguards += 1
                }
                current.recurringDeposits[index].nextDueDate = nextDate
            }
        }
    }

    func rename(_ goal: Goal, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        update(goal) { $0.name = trimmed }
    }

    /// Guarda identidad visual opcional de una meta. Las imágenes se guardan
    /// localmente por su nombre de archivo, no dentro del JSON de las metas.
    func updateGoalAppearance(
        _ goal: Goal,
        iconName: String?,
        themeName: String?,
        coverImageFileName: String?
    ) {
        let previousCoverFileName = goal.coverImageFileName
        update(goal) { current in
            current.iconName = iconName
            current.themeName = themeName
            current.coverImageFileName = coverImageFileName
        }

        // Una portada nueva se guarda con un nombre distinto solo si el
        // usuario la reemplaza. Limpiamos la anterior después de actualizar
        // el modelo, sin borrar el archivo si ambos nombres coinciden.
        if previousCoverFileName != coverImageFileName {
            GoalCoverStore.remove(named: previousCoverFileName)
        }
    }

    func updateDeadline(_ goal: Goal, deadline: Date?) {
        update(goal) { $0.deadline = deadline }
    }

    /// Cambia el valor final y redistribuye únicamente las casillas que aún
    /// no se han marcado. Los depósitos y las casillas completadas quedan
    /// intactos, incluso si se modifica la meta varias veces.
    func updateTarget(_ goal: Goal, target: Double) {
        guard target.isFinite else { return }
        update(goal) { current in
            guard target >= current.saved else { return }
            current.target = target
        }
    }

    func updateMotivation(_ goal: Goal, motivation: String) {
        update(goal) { $0.motivation = normalizedNote(motivation) }
    }

    func toggleCell(_ goal: Goal, index: Int) {
        guard goal.amounts.indices.contains(index) else { return }
        update(goal) { current in
            if let existing = current.deposits.firstIndex(where: { $0.type == .cell && $0.idx == index }) {
                current.deposits.remove(at: existing)
            } else {
                current.deposits.append(Deposit(type: .cell, idx: index, amount: current.amounts[index], date: Date()))
            }
        }
    }

    func addManualDeposit(_ goal: Goal, amount: Double, note: String, date: Date = Date()) {
        guard amount > 0 else { return }
        update(goal) {
            $0.deposits.append(
                Deposit(type: .manual, idx: nil, amount: amount, note: normalizedNote(note), date: date)
            )
        }
    }

    /// Edita únicamente un movimiento manual. Las casillas y los movimientos
    /// creados por recurrencias conservan su propia lógica de control.
    func updateDeposit(_ goal: Goal, deposit: Deposit, amount: Double, note: String, date: Date) {
        guard amount > 0, deposit.type == .manual else { return }
        update(goal) { current in
            guard let index = current.deposits.firstIndex(where: { $0.id == deposit.id && $0.type == .manual }) else { return }
            current.deposits[index].amount = amount
            current.deposits[index].note = normalizedNote(note)
            current.deposits[index].date = date
        }
    }

    func deleteManualDeposit(_ goal: Goal, deposit: Deposit) {
        guard deposit.type == .manual else { return }
        update(goal) { current in
            current.deposits.removeAll { $0.id == deposit.id && $0.type == .manual }
        }
    }

    /// Se mantiene para las pantallas existentes, que también permiten borrar
    /// una casilla desde el historial. Las nuevas pantallas de edición manual
    /// deben usar `deleteManualDeposit(_:deposit:)`.
    func deleteDeposit(_ goal: Goal, deposit: Deposit) {
        update(goal) { $0.deposits.removeAll { $0.id == deposit.id } }
    }

    func addRecurringDeposit(
        _ goal: Goal,
        amount: Double,
        note: String,
        frequency: RecurrenceFrequency,
        firstDate: Date
    ) {
        guard amount > 0 else { return }
        update(goal) { current in
            current.recurringDeposits.append(
                RecurringDeposit(
                    amount: amount,
                    note: normalizedNote(note),
                    frequency: frequency,
                    firstDate: firstDate
                )
            )
        }
    }

    func updateRecurringDeposit(
        _ goal: Goal,
        recurring: RecurringDeposit,
        amount: Double,
        note: String,
        frequency: RecurrenceFrequency,
        firstDate: Date,
        isEnabled: Bool
    ) {
        guard amount > 0 else { return }
        update(goal) { current in
            guard let index = current.recurringDeposits.firstIndex(where: { $0.id == recurring.id }) else { return }
            current.recurringDeposits[index].amount = amount
            current.recurringDeposits[index].note = normalizedNote(note)
            current.recurringDeposits[index].frequency = frequency
            current.recurringDeposits[index].firstDate = firstDate
            current.recurringDeposits[index].nextDueDate = firstDate
            current.recurringDeposits[index].isEnabled = isEnabled
        }
    }

    func setRecurringDepositEnabled(_ goal: Goal, recurring: RecurringDeposit, isEnabled: Bool) {
        update(goal) { current in
            guard let index = current.recurringDeposits.firstIndex(where: { $0.id == recurring.id }) else { return }
            current.recurringDeposits[index].isEnabled = isEnabled
        }
    }

    func deleteRecurringDeposit(_ goal: Goal, recurring: RecurringDeposit) {
        update(goal) { current in
            current.recurringDeposits.removeAll { $0.id == recurring.id }
        }
    }

    /// Procesa recurrencias pendientes de forma idempotente. Aunque la app se
    /// cerrase entre guardar un movimiento y adelantar su fecha, la búsqueda de
    /// la ocurrencia ya creada impide que se sume dos veces.
    func processDueRecurringDeposits(now: Date = Date(), calendar: Calendar = .current) {
        guard !isProcessingRecurrences else { return }

        var updatedGoals = goals
        var didChange = false

        for goalIndex in updatedGoals.indices {
            var addedDepositForGoal = false
            for recurrenceIndex in updatedGoals[goalIndex].recurringDeposits.indices {
                guard updatedGoals[goalIndex].recurringDeposits[recurrenceIndex].isEnabled,
                      updatedGoals[goalIndex].recurringDeposits[recurrenceIndex].amount > 0 else { continue }

                var recurrence = updatedGoals[goalIndex].recurringDeposits[recurrenceIndex]
                var processedOccurrences = 0

                // El límite solo protege de datos dañados (por ejemplo, una
                // fecha que no avanza); 10 000 cubre décadas de recurrencias.
                while recurrence.nextDueDate <= now, processedOccurrences < 10_000 {
                    let occurrenceDate = recurrence.nextDueDate
                    let alreadyGenerated = updatedGoals[goalIndex].deposits.contains { deposit in
                        guard deposit.type == .recurring, deposit.recurringDepositID == recurrence.id else { return false }
                        return calendar.isDate(deposit.recurrenceOccurrenceDate ?? deposit.date, inSameDayAs: occurrenceDate)
                    }

                    if !alreadyGenerated {
                        updatedGoals[goalIndex].deposits.append(
                            Deposit(
                                type: .recurring,
                                amount: recurrence.amount,
                                note: recurrence.note,
                                date: occurrenceDate,
                                recurringDepositID: recurrence.id,
                                recurrenceOccurrenceDate: occurrenceDate
                            )
                        )
                        addedDepositForGoal = true
                        didChange = true
                    }

                    guard let followingDate = recurrence.frequency.nextDate(after: occurrenceDate, calendar: calendar),
                          followingDate > occurrenceDate else { break }
                    recurrence.nextDueDate = followingDate
                    processedOccurrences += 1
                    didChange = true
                }

                if updatedGoals[goalIndex].recurringDeposits[recurrenceIndex] != recurrence {
                    updatedGoals[goalIndex].recurringDeposits[recurrenceIndex] = recurrence
                    didChange = true
                }
            }
            if addedDepositForGoal {
                rebalancePendingCells(of: &updatedGoals[goalIndex])
                updatedGoals[goalIndex].updatedAt = now
            }
        }

        guard didChange else { return }
        isProcessingRecurrences = true
        goals = updatedGoals
        isProcessingRecurrences = false
    }

    /// Lee la solicitud compartida que deja el widget y marca exactamente la
    /// casilla que éste publicó. Se puede invocar con seguridad al abrir la
    /// app o cuando esta vuelve a primer plano.
    func processPendingWidgetAction() {
        let defaults = UserDefaults(suiteName: AhorroWidgetData.appGroup)
        guard defaults?.string(forKey: AhorroWidgetData.pendingActionKey) == AhorroWidgetData.markNextCellAction else { return }

        let actionID = defaults?.string(forKey: AhorroWidgetData.pendingActionIDKey) ?? UUID().uuidString
        defaults?.set(actionID, forKey: AhorroWidgetData.pendingActionIDKey)

        defer { AhorroWidgetData.clearPendingAction(in: defaults) }

        // Una acción repetida tras un relanzamiento no debe marcar una segunda
        // casilla. El identificador se guarda dentro del mismo App Group.
        guard defaults?.string(forKey: AhorroWidgetData.lastProcessedActionIDKey) != actionID else {
            // Si el sistema vuelve a entregar la misma intención, conserva el
            // resultado canónico de la app y limpia el estado optimista.
            publishWidgetSnapshot()
            return
        }
        guard let rawGoalID = defaults?.string(forKey: AhorroWidgetData.goalIDKey),
              let goalID = UUID(uuidString: rawGoalID),
              let goalIndex = goals.firstIndex(where: { $0.id == goalID }),
              let nextIndex = defaults?.object(forKey: AhorroWidgetData.nextCellIndexKey) as? Int,
              goals[goalIndex].amounts.indices.contains(nextIndex),
              goals[goalIndex].amounts[nextIndex] > 0.000_001,
              !goals[goalIndex].isCellDone(nextIndex) else {
            defaults?.set(actionID, forKey: AhorroWidgetData.lastProcessedActionIDKey)
            // El widget pudo mostrar datos que cambiaron antes de que la app
            // consumiera la acción. Publicamos de nuevo la fuente canónica en
            // vez de marcar una casilla distinta por sorpresa.
            publishWidgetSnapshot()
            return
        }

        goals[goalIndex].deposits.append(
            Deposit(
                type: .cell,
                idx: nextIndex,
                amount: goals[goalIndex].amounts[nextIndex],
                date: Date()
            )
        )
        goals[goalIndex].updatedAt = Date()
        rebalancePendingCells(of: &goals[goalIndex])
        defaults?.set(actionID, forKey: AhorroWidgetData.lastProcessedActionIDKey)
        processDueRecurringDeposits()
    }

    private func update(_ goal: Goal, action: (inout Goal) -> Void) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        action(&goals[index])
        goals[index].updatedAt = Date()
        rebalancePendingCells(of: &goals[index])
        processDueRecurringDeposits()
    }

    /// Hace que la suma de las casillas pendientes sea exactamente el dinero
    /// que falta. En una tabla secuencial la reconstruye desde 1, 2, 3…;
    /// nunca usa como referencia los importes que ya se redujeron a cero.
    /// Las casillas marcadas no se alteran en ningún caso.
    private func rebalancePendingCells(of goal: inout Goal) {
        let remaining = max(0, goal.target - goal.saved)
        var pendingIndices = goal.amounts.indices.filter { !goal.isCellDone($0) }

        guard !pendingIndices.isEmpty else { return }
        guard remaining > 0 else {
            for index in pendingIndices { goal.amounts[index] = 0 }
            return
        }

        let recalculatedAmounts: [Double]
        switch goal.tableStyle {
        case .sequential:
            recalculatedAmounts = sequentialPendingAmounts(total: remaining)
        case .pattern:
            let count = min(pendingIndices.count, max(1, Int(remaining.rounded(.up))))
            recalculatedAmounts = patternedPendingAmounts(total: remaining, count: count)
        }

        // Una meta puede necesitar más casillas activas que las que quedaron
        // libres tras marcar varias. Agregamos solo nuevas casillas pendientes;
        // los índices y los importes de las casillas ya marcadas se preservan.
        if pendingIndices.count < recalculatedAmounts.count {
            let missing = recalculatedAmounts.count - pendingIndices.count
            let firstNewIndex = goal.amounts.count
            goal.amounts.append(contentsOf: Array(repeating: 0, count: missing))
            pendingIndices.append(contentsOf: firstNewIndex..<(firstNewIndex + missing))
        }

        for (offset, index) in pendingIndices.enumerated() {
            goal.amounts[index] = offset < recalculatedAmounts.count ? recalculatedAmounts[offset] : 0
        }
    }

    /// Reconstruye la secuencia sin inflar la última casilla. El resto queda
    /// como una casilla separada, por lo que nunca revive valores grandes como
    /// $69 después de registrar o eliminar un depósito manual.
    private func sequentialPendingAmounts(total: Double) -> [Double] {
        TableGenerator.sequential(target: total)
    }

    /// Mantiene el estilo variado sin conservar pesos deteriorados de un
    /// cálculo previo. La distribución se hace desde el patrón base cada vez.
    private func patternedPendingAmounts(total: Double, count: Int) -> [Double] {
        guard count > 0, total > 0 else { return [] }
        let multipliers: [Double] = [0.5, 1, 0.25, 1, 0.5, 1, 0.75, 1, 0.75, 1]
        let weights = (0..<count).map { multipliers[$0 % multipliers.count] }
        let weightTotal = weights.reduce(0, +)
        let scale = total.rounded() == total ? 1.0 : 100.0
        let totalUnits = Int((total * scale).rounded())
        let ideal = weights.map { Double(totalUnits) * $0 / weightTotal }
        var units = ideal.map { Int($0.rounded(.down)) }
        var remainingUnits = totalUnits - units.reduce(0, +)
        let order = ideal.indices.sorted {
            let left = ideal[$0] - Double(units[$0])
            let right = ideal[$1] - Double(units[$1])
            return left == right ? $0 < $1 : left > right
        }
        var cursor = 0
        while remainingUnits > 0 {
            units[order[cursor % order.count]] += 1
            remainingUnits -= 1
            cursor += 1
        }
        return units.map { Double($0) / scale }
    }

    private func normalizedNote(_ note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func refreshSmartReminder() {
        let currentGoals = goals
        Task { @MainActor in
            await AppSettings.shared.refreshSmartReminder(for: currentGoals)
        }
    }

#if CLOUDKIT_SYNC
    private func scheduleCloudSync() {
        guard AppSettings.iCloudSyncAvailable, AppSettings.shared.iCloudEnabled else { return }
        syncWithICloud()
    }

    private func applyCloudSnapshot(_ remoteSnapshot: AhorroCloudSnapshot) {
        // Vuelve a combinar contra el estado actual por si se marcó una
        // casilla mientras CloudKit estaba respondiendo.
        let currentSnapshot = AhorroCloudSnapshot(goals: goals, tombstones: cloudTombstones)
        let resolved = AhorroCloudSnapshot.merged(currentSnapshot, remoteSnapshot)
        let shouldUploadAgain = resolved != remoteSnapshot

        isApplyingCloudSnapshot = true
        if goals != resolved.goals {
            goals = resolved.goals
        }
        cloudTombstones = resolved.tombstones
        saveCloudTombstones()
        isApplyingCloudSnapshot = false
        cloudSyncStatus = .synced(Date())

        if shouldUploadAgain {
            syncWithICloud()
        }
    }

    private func loadCloudTombstones() {
        guard let data = UserDefaults.standard.data(forKey: cloudTombstonesKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        cloudTombstones = (try? decoder.decode(AhorroCloudTombstones.self, from: data)) ?? .init()
    }

    private func saveCloudTombstones() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(cloudTombstones) {
            UserDefaults.standard.set(data, forKey: cloudTombstonesKey)
        }
    }
#endif
}

func fmt(_ value: Double, currency: AppCurrency) -> String {
    currency.formatted(value)
}

let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMM · HH:mm"
    formatter.locale = Locale(identifier: "es_EC")
    return formatter
}()

/// Claves compartidas entre Ahorro y su extensión de widget.
///
/// El widget publica una acción con `pendingAction = markNextCell` y un UUID
/// nuevo en `pendingActionID`; la app la consume mediante
/// `Store.processPendingWidgetAction()` al abrirse o volver a primer plano.
enum AhorroWidgetData {
    static let appGroup = "group.com.personal.Ahorro"
    static let kind = "AhorroWidget"
    static let hasGoalKey = "widget.hasGoal"
    static let nameKey = "widget.goalName"
    static let savedKey = "widget.saved"
    static let targetKey = "widget.target"
    static let progressKey = "widget.progress"
    static let stepsRemainingKey = "widget.stepsRemaining"
    static let goalIDKey = "widget.goalID"
    static let nextCellIndexKey = "widget.nextCellIndex"
    static let nextCellAmountKey = "widget.nextCellAmount"
    static let canMarkNextCellKey = "widget.canMarkNextCell"
    static let pendingActionKey = "widget.pendingAction"
    static let pendingActionIDKey = "widget.pendingActionID"
    static let lastProcessedActionIDKey = "widget.lastProcessedActionID"
    static let markNextCellAction = "markNextCell"

    static func clearActionSnapshot(in defaults: UserDefaults?) {
        [goalIDKey, nextCellIndexKey, nextCellAmountKey, canMarkNextCellKey].forEach {
            defaults?.removeObject(forKey: $0)
        }
    }

    static func clearPendingAction(in defaults: UserDefaults?) {
        [pendingActionKey, pendingActionIDKey].forEach {
            defaults?.removeObject(forKey: $0)
        }
    }
}

@main
struct AhorroApp: App {
    @StateObject private var store = Store()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            AppSecurityRoot()
                .environmentObject(store)
                .environmentObject(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}

/// Añade una capa de privacidad por encima de toda la navegación sin recrear
/// las metas ni perder la pantalla en la que estaba el usuario.
private struct AppSecurityRoot: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            ContentView()
                .allowsHitTesting(!settings.isAppLocked)
                .accessibilityHidden(settings.isAppLocked)

            if settings.isAppLocked {
                FaceIDLockView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: settings.isAppLocked)
        .onAppear {
            store.processDueRecurringDeposits()
            store.processPendingWidgetAction()
            store.setCloudSyncEnabled(settings.iCloudEnabled)
            settings.handleScenePhase(.active)
        }
        .onChange(of: settings.iCloudEnabled) { _, enabled in
            store.setCloudSyncEnabled(enabled)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.processDueRecurringDeposits()
                store.processPendingWidgetAction()
                if settings.iCloudEnabled { store.syncWithICloud() }
            }
            settings.handleScenePhase(phase)
        }
    }
}

private struct FaceIDLockView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            Color.bg
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "faceid")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundColor(.accentStrong)
                    .frame(width: 82, height: 82)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                    .overlay(RoundedRectangle(cornerRadius: 25).stroke(Color.borderC))

                Text("Ahorro protegido")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundColor(.textC)

                Text("Usa \(settings.biometricDisplayName) para continuar.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(.mutedC)
                    .multilineTextAlignment(.center)

                if let lockMessage = settings.lockMessage {
                    Text(lockMessage)
                        .font(.footnote)
                        .foregroundColor(.mutedC)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }

                Button {
                    Task { await settings.authenticateToUnlock() }
                } label: {
                    HStack(spacing: 8) {
                        if settings.isAuthenticating {
                            ProgressView()
                                .tint(Color(hex: "15170F"))
                        } else {
                            Image(systemName: "faceid")
                        }
                        Text(settings.isAuthenticating ? "Verificando…" : "Desbloquear con \(settings.biometricDisplayName)")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "15170F"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentC)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(settings.isAuthenticating)
                .padding(.top, 8)
                .accessibilityLabel("Desbloquear Ahorro con \(settings.biometricDisplayName)")
            }
            .frame(maxWidth: 330)
            .padding(28)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.borderC))
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Pantalla principal

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @State private var showingNewGoal = false
    @State private var showingSettings = false

    private var totalSaved: Double { store.goals.reduce(0) { $0 + $1.saved } }
    private var totalTarget: Double { store.goals.reduce(0) { $0 + $1.target } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.goals.isEmpty {
                        emptyState
                    } else {
                        totalsCard
                        Text("TUS METAS")
                            .font(.caption).tracking(1.1).foregroundColor(.mutedC)
                            .padding(.horizontal, 4)
                        ForEach(store.goals) { goal in
                            NavigationLink(value: goal.id) { GoalCard(goal: goal) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
            .background(Color.bg)
            .navigationTitle("Ahorro")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Ajustes")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let goal = store.goals.first(where: { $0.id == id }) { GoalDetailView(goalID: goal.id) }
            }
            .overlay(alignment: .bottomTrailing) {
                Button { showingNewGoal = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color(hex: "15170F"))
                        .frame(width: 56, height: 56)
                        .background(Color.accentC)
                        .clipShape(RoundedRectangle(cornerRadius: 17))
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                }
                .padding(20)
            }
            .sheet(isPresented: $showingNewGoal) { NewGoalSheet() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
        .tint(.accentC)
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AHORRADO EN TOTAL").font(.caption).tracking(1.1).foregroundColor(.mutedC)
            Text(fmt(totalSaved, currency: settings.currency)).font(.system(size: 34, weight: .semibold, design: .rounded))
            Text("de \(fmt(totalTarget, currency: settings.currency)) entre \(store.goals.count) meta\(store.goals.count == 1 ? "" : "s")")
                .font(.footnote).foregroundColor(.mutedC)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderC))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.square.dashed")
                .font(.system(size: 22)).foregroundColor(.accentStrong)
                .frame(width: 44, height: 44).background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("Aún no tienes metas").font(.headline)
            Text("Crea tu primera tabla de ahorro y empieza\na registrar cada monto que guardes.")
                .font(.footnote).foregroundColor(.mutedC).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

struct GoalCard: View {
    @EnvironmentObject private var settings: AppSettings
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GoalIdentityBadge(goal: goal, size: 38)
                Text(goal.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(goal.resolvedGoalTheme.deepTint)
            }
            ProgressBar(progress: goal.progress, tint: goal.resolvedGoalTheme.tint)
            HStack {
                HStack(spacing: 0) {
                    Text("Ahorrado ").foregroundColor(.mutedC)
                    Text(fmt(goal.saved, currency: settings.currency)).foregroundColor(.textC).fontWeight(.semibold)
                }
                Spacer()
                HStack(spacing: 0) {
                    Text("Meta ").foregroundColor(.mutedC)
                    Text(fmt(goal.target, currency: settings.currency)).foregroundColor(.textC).fontWeight(.semibold)
                }
            }
            .font(.system(size: 12.5, design: .rounded))
        }
        .padding(18).background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borderC))
    }
}

struct ProgressBar: View {
    let progress: Double
    var tint: Color = .accentC

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.borderC)
                Capsule().fill(tint).frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 7)
    }
}

// MARK: - Detalle de meta

struct GoalDetailView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    let goalID: UUID
    @State private var showingDeposit = false
    @State private var showingRename = false
    @State private var showingHistory = false
    @State private var showingAllCells = false
    @State private var showingResetConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDeadlineEditor = false
    @State private var showingAppearanceEditor = false
    @State private var showingTargetEditor = false
    @State private var showingMotivationEditor = false
    @State private var editingDeposit: Deposit?
    @State private var pdfReport: PDFReport?
    @State private var exportError: String?

    private let compactCellLimit = 16

    private var goal: Goal? { store.goals.first { $0.id == goalID } }

    var body: some View {
        Group {
            if let goal {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GoalCoverView(goal: goal)
                        progressCard(goal)
                        GoalMilestonesCard(goal: goal)
                        GoalDeadlinePaceCard(goal: goal) {
                            showingDeadlineEditor = true
                        }
                        GoalProgressChart(goal: goal)

                        QuickDepositRow(goal: goal)

                        Button { showingDeposit = true } label: {
                            Text("Registrar depósito")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "15170F"))
                                .frame(maxWidth: .infinity).padding(13)
                                .background(Color.accentC)
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4), spacing: 9) {
                            ForEach(visibleCellIndices(for: goal), id: \.self) { index in
                                CellView(
                                    amount: goal.amounts[index],
                                    done: goal.isCellDone(index),
                                    tint: goal.resolvedGoalTheme.tint
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        store.toggleCell(goal, index: index)
                                    }
                                }
                            }
                        }

                        if goal.activeCellIndices.count > compactCellLimit {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showingAllCells.toggle()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(cellToggleTitle(for: goal))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    Image(systemName: showingAllCells ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.accentStrong)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showingAllCells ? "Mostrar solo cuatro filas" : "Ver más casillas")
                        }

                        SavingsSimulatorCard(goal: goal)
                        SavingsCalendarView(goal: goal)
                        RecurringDepositsSection(goal: goal)

                        Button { withAnimation { showingHistory.toggle() } } label: {
                            HStack {
                                Text("HISTORIAL DE MOVIMIENTOS").font(.caption).tracking(1.1).foregroundColor(.mutedC)
                                Spacer()
                                Image(systemName: showingHistory ? "minus" : "plus").foregroundColor(.textC)
                            }
                        }
                        .padding(.top, 6)

                        if showingHistory { historyList(goal) }

                        HStack(spacing: 10) {
                            Button("Reiniciar progreso") { showingResetConfirmation = true }
                                .buttonStyle(.bordered).tint(.surface).foregroundColor(.textC)
                            Button("Eliminar meta", role: .destructive) { showingDeleteConfirmation = true }
                                .buttonStyle(.bordered).tint(.dangerC)
                        }
                        .padding(.top, 10)
                    }
                    .padding(20).padding(.bottom, 60)
                }
                .background(Color.bg)
                .navigationTitle(goal.name)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button { export(goal) } label: { Image(systemName: "doc.richtext") }
                        Menu {
                            Button { showingRename = true } label: {
                                Label("Cambiar nombre", systemImage: "pencil")
                            }
                            Button { showingDeadlineEditor = true } label: {
                                Label("Fecha límite", systemImage: "calendar")
                            }
                            Button { showingTargetEditor = true } label: {
                                Label("Recalcular tabla", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button { showingMotivationEditor = true } label: {
                                Label("Motivo de ahorro", systemImage: "quote.bubble")
                            }
                            Button { showingAppearanceEditor = true } label: {
                                Label("Personalizar meta", systemImage: "paintpalette")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showingDeposit) { DepositSheet(goal: goal) }
                .sheet(isPresented: $showingRename) { RenameSheet(goal: goal) }
                .sheet(isPresented: $showingDeadlineEditor) { DeadlineEditorSheet(goal: goal) }
                .sheet(isPresented: $showingAppearanceEditor) { GoalAppearanceEditorSheet(goal: goal) }
                .sheet(isPresented: $showingTargetEditor) { GoalTargetEditorSheet(goal: goal) }
                .sheet(isPresented: $showingMotivationEditor) { GoalMotivationEditorSheet(goal: goal) }
                .sheet(item: $editingDeposit) { deposit in
                    EditManualDepositSheet(goal: goal, deposit: deposit)
                }
                .sheet(item: $pdfReport) { report in PDFPreviewSheet(url: report.url) }
                .alert("No se pudo exportar el PDF", isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                )) {
                    Button("Aceptar", role: .cancel) { exportError = nil }
                } message: {
                    Text(exportError ?? "Inténtalo de nuevo.")
                }
                .alert("¿Reiniciar progreso?", isPresented: $showingResetConfirmation) {
                    Button("Cancelar", role: .cancel) { }
                    Button("Reiniciar", role: .destructive) {
                        store.resetProgress(goal)
                    }
                } message: {
                    Text("Se eliminarán todos los depósitos registrados de esta meta.")
                }
                .alert("¿Eliminar meta?", isPresented: $showingDeleteConfirmation) {
                    Button("Cancelar", role: .cancel) { }
                    Button("Eliminar", role: .destructive) {
                        store.deleteGoal(goal)
                    }
                } message: {
                    Text("Esta acción no se puede deshacer.")
                }
            } else {
                Text("Meta no encontrada").foregroundColor(.mutedC)
            }
        }
    }

    private func progressCard(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(fmt(goal.saved, currency: settings.currency)).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(goal.resolvedGoalTheme.deepTint)
                Spacer()
                Text("de \(fmt(goal.target, currency: settings.currency))").font(.system(size: 13.5, design: .rounded)).foregroundColor(.mutedC)
            }
            ProgressBar(progress: goal.progress, tint: goal.resolvedGoalTheme.tint)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FALTA POR AHORRAR")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundColor(.mutedC)
                    Text(fmt(goal.remaining, currency: settings.currency))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.textC)
                }
                Spacer()
                Text("\(goal.pendingCellCount) casillas\npor marcar")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.mutedC)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(20).background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borderC))
    }

    private func visibleCellIndices(for goal: Goal) -> [Int] {
        Array(goal.activeCellIndices.prefix(showingAllCells ? goal.activeCellIndices.count : compactCellLimit))
    }

    private func cellToggleTitle(for goal: Goal) -> String {
        guard !showingAllCells else { return "Mostrar solo 4 filas" }
        let remainingCells = goal.activeCellIndices.count - compactCellLimit
        return "Ver \(remainingCells) casilla\(remainingCells == 1 ? "" : "s") más"
    }

    private func historyList(_ goal: Goal) -> some View {
        VStack(spacing: 8) {
            if goal.deposits.isEmpty {
                Text("Todavía no hay movimientos registrados.")
                    .font(.footnote).foregroundColor(.mutedC2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(goal.deposits.sorted { $0.date > $1.date }) { deposit in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("+\(fmt(deposit.amount, currency: settings.currency))").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.accentStrong)
                            Text(historyDescription(for: deposit))
                                .font(.caption).foregroundColor(.mutedC)
                            Text(dateFormatter.string(from: deposit.date)).font(.caption2).foregroundColor(.mutedC2)
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            if deposit.type == .manual {
                                Button { editingDeposit = deposit } label: {
                                    Image(systemName: "pencil").foregroundColor(.accentStrong)
                                }
                                .accessibilityLabel("Editar depósito")
                            }
                            Button {
                                if deposit.type == .manual {
                                    store.deleteManualDeposit(goal, deposit: deposit)
                                } else {
                                    store.deleteDeposit(goal, deposit: deposit)
                                }
                            } label: {
                                Image(systemName: "xmark").foregroundColor(.dangerC)
                            }
                            .accessibilityLabel("Eliminar movimiento")
                        }
                    }
                    .padding(14).background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.borderC))
                }
            }
        }
    }

    private func historyDescription(for deposit: Deposit) -> String {
        switch deposit.type {
        case .cell:
            return "Casilla marcada"
        case .manual:
            return deposit.note?.isEmpty == false ? deposit.note! : "Depósito manual"
        case .recurring:
            let note = deposit.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return note.isEmpty ? "Depósito programado" : "Programado · \(note)"
        }
    }

    private func export(_ goal: Goal) {
        do {
            pdfReport = PDFReport(url: try SavingsPDFExporter.makeReport(goals: [goal], currency: settings.currency))
        } catch {
            exportError = error.localizedDescription
        }
    }
}

struct CellView: View {
    @EnvironmentObject private var settings: AppSettings
    let amount: Double
    let done: Bool
    var tint: Color = .accentC
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 13)
                    .fill(done ? tint.opacity(0.16) : Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(done ? tint.opacity(0.4) : Color.borderC))
                Text(fmt(amount, currency: settings.currency))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(done ? .mutedC2 : .textC)
                    .strikethrough(done, color: .mutedC.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if done {
                    ZStack {
                        Circle().fill(tint).frame(width: 15, height: 15)
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundColor(Color(hex: "15170F"))
                    }
                    .padding(5).transition(.scale.combined(with: .opacity))
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hojas

struct NewGoalSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var targetText = ""
    @State private var style: TableStyle = .sequential
    @State private var count = 24
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var iconName = "target"
    @State private var themeName = GoalTheme.sage.rawValue
    @State private var motivation = ""
    private let counts = [16, 24, 36, 52, 100]

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre de la meta") { TextField("Ej. Para mi moto", text: $name) }
                Section("Monto objetivo (\(settings.currency.currencyCode))") { TextField("1500", text: $targetText).keyboardType(.decimalPad) }
                Section("Estilo de tabla") {
                    Picker("Estilo", selection: $style) {
                        ForEach(TableStyle.allCases, id: \.self) { style in Text(style.rawValue).tag(style) }
                    }
                    .pickerStyle(.segmented)
                }
                if style == .pattern {
                    Section("Cantidad de casillas") {
                        Picker("Casillas", selection: $count) {
                            ForEach(counts, id: \.self) { count in Text("\(count)").tag(count) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("Plan de ahorro") {
                    Toggle("Definir fecha límite", isOn: $hasDeadline)
                        .tint(GoalTheme(themeName: themeName).tint)
                    if hasDeadline {
                        DatePicker(
                            "Fecha límite",
                            selection: $deadline,
                            in: Date()...,
                            displayedComponents: .date
                        )
                    }
                    Text(hasDeadline
                         ? "Te mostraremos el ritmo semanal necesario para llegar a tiempo."
                         : "Puedes agregar una fecha límite más tarde desde la meta.")
                        .font(.caption)
                        .foregroundColor(.mutedC)
                }
                Section("Personaliza tu meta") {
                    GoalThemePicker(themeName: $themeName)
                        .padding(.vertical, 4)
                    GoalIconPicker(iconName: $iconName)
                        .padding(.vertical, 4)
                }
                Section("¿Para qué ahorras?") {
                    TextField("Ej. Mi moto, mi viaje o tranquilidad", text: $motivation, axis: .vertical)
                        .lineLimit(2...3)
                    Text("Esta nota aparecerá en la portada de la meta.")
                        .font(.caption)
                        .foregroundColor(.mutedC)
                }
                Text(style == .sequential ? "Una casilla por cada dólar, del 1 hasta completar tu meta." : "Montos variados repartidos en las casillas elegidas.")
                    .font(.caption).foregroundColor(.mutedC)
            }
            .navigationTitle("Nueva meta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear tabla") {
                        guard let target = Double(targetText), target > 0 else { return }
                        store.addGoal(
                            name: name,
                            target: target,
                            style: style,
                            count: count,
                            deadline: hasDeadline ? deadline : nil,
                            iconName: iconName,
                            themeName: themeName,
                            motivation: motivation
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DepositSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Monto (\(settings.currency.currencyCode))") { TextField("20", text: $amountText).keyboardType(.decimalPad) }
                Section("Nota (opcional)") { TextField("Ej. Ahorro de la semana", text: $note) }
                Section("Fecha") {
                    DatePicker("Registrar el", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                Text("Este monto se suma directo a tu progreso, sin necesidad de marcar una casilla.")
                    .font(.caption).foregroundColor(.mutedC)
            }
            .navigationTitle("Registrar depósito")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Agregar") {
                        guard let amount = Double(amountText), amount > 0 else { return }
                        store.addManualDeposit(goal, amount: amount, note: note, date: date)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RenameSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form { Section("Nombre") { TextField("Nombre de la meta", text: $name) } }
                .navigationTitle("Editar meta")
                .onAppear { name = goal.name }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Guardar") { store.rename(goal, to: name); dismiss() }
                    }
                }
        }
    }
}
