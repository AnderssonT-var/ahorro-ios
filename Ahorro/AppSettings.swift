//
//  AppSettings.swift
//  Ahorro
//
//  Preferencias persistentes compartidas por la app.
//

import Combine
import Foundation
import LocalAuthentication
import SwiftUI
import UserNotifications
import WidgetKit

enum AppCurrency: String, CaseIterable, Codable, Identifiable {
    case usd = "USD"
    case mxn = "MXN"
    case eur = "EUR"

    var id: String { rawValue }
    var currencyCode: String { rawValue }

    var title: String {
        switch self {
        case .usd: "USD — Dólar estadounidense"
        case .mxn: "MXN — Peso mexicano"
        case .eur: "EUR — Euro"
        }
    }

    var symbol: String {
        switch self {
        case .usd, .mxn: "$"
        case .eur: "€"
        }
    }

    var sfSymbol: String {
        switch self {
        case .usd: "dollarsign.circle.fill"
        case .mxn: "banknote.fill"
        case .eur: "eurosign.circle.fill"
        }
    }

    /// Formatea importes de forma coherente en la app, los reportes y el widget.
    func formatted(_ value: Double, maximumFractionDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        formatter.currencySymbol = symbol
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "\(symbol)\(value)"
    }

    private var locale: Locale {
        switch self {
        case .usd: Locale(identifier: "en_US")
        case .mxn: Locale(identifier: "es_MX")
        case .eur: Locale(identifier: "es_ES")
        }
    }
}

enum AppAppearance: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Automático"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }

    var sfSymbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Las cuentas gratuitas de Apple no pueden firmar CloudKit ni Push
    /// Notifications. Se reactiva al preparar la versión con una cuenta del
    /// Apple Developer Program y volver a añadir sus capacidades.
    static let iCloudSyncAvailable = false

    @Published var currency: AppCurrency {
        didSet {
            defaults.set(currency.rawValue, forKey: Keys.currency)
            publishCurrencyToWidget()
        }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// Se conserva para una futura versión con CloudKit, pero esta compilación
    /// local la mantiene desactivada para que pueda instalarse con Personal Team.
    @Published var iCloudEnabled: Bool {
        didSet { defaults.set(iCloudEnabled, forKey: Keys.iCloudEnabled) }
    }

    /// Cambiar esta preferencia desde la interfaz mediante `setRemindersEnabled(_:)`.
    @Published private(set) var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Keys.remindersEnabled) }
    }

    /// Protege el contenido de la app mediante Face ID (o Touch ID en los
    /// dispositivos que solo disponen de ese sensor).
    @Published private(set) var faceIDEnabled: Bool {
        didSet { defaults.set(faceIDEnabled, forKey: Keys.faceIDEnabled) }
    }

    /// Controla la cortina de seguridad que se muestra al iniciar o volver a
    /// abrir Ahorro. No se persiste: cada proceso nuevo vuelve a requerir
    /// autenticación cuando Face ID está habilitado.
    @Published private(set) var isAppLocked: Bool
    @Published private(set) var isAuthenticating = false
    @Published private(set) var faceIDSetupMessage: String?
    @Published private(set) var lockMessage: String?

    private let defaults: UserDefaults

    private enum Keys {
        static let currency = "settings.currency"
        static let appearance = "settings.appearance"
        static let iCloudEnabled = "settings.iCloudEnabled"
        static let remindersEnabled = "settings.remindersEnabled"
        static let faceIDEnabled = "settings.faceIDEnabled"
    }

    private enum WidgetData {
        static let appGroup = "group.com.personal.Ahorro"
        static let currencyCodeKey = "widget.currencyCode"
        static let kind = "AhorroWidget"
    }

    private static let dailyReminderIdentifier = "ahorro.dailyReminder"
    private var requiresAuthentication: Bool

    private init(defaults: UserDefaults = .standard) {
        let storedFaceIDEnabled = defaults.object(forKey: Keys.faceIDEnabled) as? Bool ?? false
        let storedICloudEnabled = defaults.object(forKey: Keys.iCloudEnabled) as? Bool ?? false
        self.defaults = defaults
        self.currency = AppCurrency(rawValue: defaults.string(forKey: Keys.currency) ?? "") ?? .usd
        self.appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .dark
        self.iCloudEnabled = Self.iCloudSyncAvailable && storedICloudEnabled
        self.remindersEnabled = defaults.object(forKey: Keys.remindersEnabled) as? Bool ?? false
        self.faceIDEnabled = storedFaceIDEnabled
        self.isAppLocked = storedFaceIDEnabled
        self.requiresAuthentication = storedFaceIDEnabled
        if storedICloudEnabled && !Self.iCloudSyncAvailable {
            defaults.set(false, forKey: Keys.iCloudEnabled)
        }
        publishCurrencyToWidget()
    }

    /// Nombre visible del mecanismo biométrico disponible. Mantiene "Face ID"
    /// como predeterminado para que la preferencia sea clara antes del primer uso.
    var biometricDisplayName: String {
        let context = LAContext()
        switch context.biometryType {
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Face ID"
        @unknown default:
            return "Face ID"
        }
    }

    /// Punto único del toggle de seguridad. Al activarlo pide una verificación
    /// inmediata; así nunca se guarda una protección que el usuario no pudo usar.
    func setFaceIDEnabled(_ enabled: Bool) async {
        faceIDSetupMessage = nil

        guard enabled else {
            faceIDEnabled = false
            requiresAuthentication = false
            isAppLocked = false
            lockMessage = nil
            return
        }

        if let unavailableMessage = biometricUnavailableMessage() {
            faceIDEnabled = false
            requiresAuthentication = false
            isAppLocked = false
            faceIDSetupMessage = unavailableMessage
            return
        }

        await authenticateToEnableFaceID()
    }

    /// Debe llamarse desde la raíz de la escena para pedir Face ID al abrir o
    /// volver a la aplicación desde segundo plano.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard faceIDEnabled else { return }
            requiresAuthentication = true
            isAppLocked = true

        case .active:
            guard faceIDEnabled, requiresAuthentication, !isAuthenticating else { return }
            isAppLocked = true
            Task { await authenticateToUnlock() }

        case .inactive:
            break

        @unknown default:
            break
        }
    }

    /// Reintenta el desbloqueo desde la pantalla protegida tras una cancelación
    /// o un fallo de lectura. El usuario nunca queda bloqueado de forma permanente.
    func authenticateToUnlock() async {
        guard faceIDEnabled, !isAuthenticating else { return }

        if let unavailableMessage = biometricUnavailableMessage() {
            faceIDEnabled = false
            requiresAuthentication = false
            isAppLocked = false
            lockMessage = nil
            faceIDSetupMessage = "\(unavailableMessage) Face ID se desactivó para que puedas entrar a la app."
            return
        }

        isAuthenticating = true
        lockMessage = nil
        defer { isAuthenticating = false }

        do {
            try await evaluateBiometrics(reason: "Desbloquea Ahorro para ver tus metas y movimientos.")
            requiresAuthentication = false
            isAppLocked = false
        } catch {
            // Mantener la cortina es intencional, pero la acción "Intentar de
            // nuevo" permite recuperarse de cancelaciones sin cerrar la app.
            isAppLocked = true
            lockMessage = unlockFailureMessage(for: error)
        }
    }

    func dismissFaceIDSetupMessage() {
        faceIDSetupMessage = nil
    }

    private func authenticateToEnableFaceID() async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await evaluateBiometrics(reason: "Confirma tu identidad para activar Face ID en Ahorro.")
            faceIDEnabled = true
            requiresAuthentication = false
            isAppLocked = false
        } catch {
            faceIDEnabled = false
            requiresAuthentication = false
            isAppLocked = false
            faceIDSetupMessage = enableFailureMessage(for: error)
        }
    }

    /// `nil` significa que el sensor está listo para usarse.
    private func biometricUnavailableMessage() -> String? {
        let context = LAContext()
        var error: NSError?
        guard !context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return nil
        }

        guard let error else {
            return "Face ID no está disponible en este dispositivo."
        }

        switch LAError.Code(rawValue: error.code) {
        case .biometryNotAvailable:
            return "Este dispositivo no tiene Face ID o Touch ID disponible."
        case .biometryNotEnrolled:
            return "Configura Face ID en Ajustes del iPhone antes de activarlo en Ahorro."
        case .biometryLockout:
            return "Face ID está bloqueado temporalmente. Desbloquea el iPhone e inténtalo otra vez."
        default:
            return "Face ID no está disponible en este momento."
        }
    }

    private func evaluateBiometrics(reason: String) async throws {
        let context = LAContext()
        try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
    }

    private func enableFailureMessage(for error: Error) -> String {
        let code = (error as? LAError)?.code
        switch code {
        case .userCancel, .systemCancel, .appCancel:
            return "Face ID no se activó. Puedes volver a intentarlo cuando quieras."
        case .biometryLockout:
            return "Face ID está bloqueado temporalmente. Desbloquea el iPhone e inténtalo otra vez."
        default:
            return "No se pudo activar Face ID. Inténtalo nuevamente."
        }
    }

    private func unlockFailureMessage(for error: Error) -> String {
        let code = (error as? LAError)?.code
        switch code {
        case .userCancel, .systemCancel, .appCancel:
            return "La verificación se canceló. Puedes intentarlo de nuevo cuando quieras."
        case .authenticationFailed:
            return "Face ID no pudo reconocerte. Inténtalo de nuevo."
        case .biometryLockout:
            return "Face ID está bloqueado temporalmente. Desbloquea el iPhone e inténtalo otra vez."
        default:
            return "No se pudo verificar tu identidad. Inténtalo de nuevo."
        }
    }

    /// Pide permiso si hace falta y crea un recordatorio diario inteligente a las 19:00.
    /// Devuelve `true` únicamente cuando el recordatorio queda programado.
    @discardableResult
    func enableDailyReminder() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let notificationSettings = await center.notificationSettings()

        let isAuthorized: Bool
        switch notificationSettings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .notDetermined:
            do {
                isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                isAuthorized = false
            }
        case .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }

        guard isAuthorized else {
            remindersEnabled = false
            await removeDailyReminder()
            return false
        }

        return await scheduleDailyReminder(using: center, goals: [])
    }

    /// Elimina el recordatorio local y actualiza la preferencia persistida.
    func removeDailyReminder() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.dailyReminderIdentifier])
        remindersEnabled = false
    }

    /// Punto único para el `Toggle` de recordatorios: no activa la preferencia
    /// hasta que el permiso y la programación se hayan completado correctamente.
    func setRemindersEnabled(_ enabled: Bool) async {
        if enabled {
            _ = await enableDailyReminder()
        } else {
            await removeDailyReminder()
        }
    }

    /// Actualiza el texto del recordatorio con la meta cuya fecha límite está
    /// más próxima. Se invoca desde Store cada vez que cambian las metas.
    func refreshSmartReminder(for goals: [Goal]) async {
        guard remindersEnabled else { return }
        _ = await scheduleDailyReminder(using: UNUserNotificationCenter.current(), goals: goals)
    }

    private func scheduleDailyReminder(
        using center: UNUserNotificationCenter,
        goals: [Goal]
    ) async -> Bool {
        let content = UNMutableNotificationContent()
        let copy = smartReminderCopy(for: goals)
        content.title = copy.title
        content.body = copy.body
        content.sound = .default

        var components = DateComponents()
        components.hour = 19
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.dailyReminderIdentifier,
            content: content,
            trigger: trigger
        )

        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderIdentifier])
        do {
            try await center.add(request)
            remindersEnabled = true
            return true
        } catch {
            remindersEnabled = false
            return false
        }
    }

    private func smartReminderCopy(for goals: [Goal]) -> (title: String, body: String) {
        let now = Date()
        let candidate = goals
            .filter { $0.remaining > 0 && $0.deadline != nil }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            .first

        guard let goal = candidate, let deadline = goal.deadline else {
            return ("Tu ahorro te espera", "Registra el avance de tu meta de hoy.")
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let daysLeft = max(0, calendar.dateComponents([.day], from: startOfToday, to: deadline).day ?? 0)
        let amountPerWeek = goal.remaining / max(Double(max(daysLeft, 1)) / 7, 1.0 / 7)
        let remainingText = currency.formatted(goal.remaining)

        if daysLeft == 0 {
            return ("Hoy vence \(goal.name)", "Te faltan \(remainingText). Registra un avance para acercarte a tu meta.")
        }

        if daysLeft <= 7 {
            return ("\(goal.name) está cerca", "Quedan \(daysLeft) días y \(remainingText) por ahorrar. Cada depósito cuenta.")
        }

        return (
            "Mantén el ritmo de \(goal.name)",
            "Te faltan \(remainingText). Tu ritmo sugerido es \(currency.formatted(amountPerWeek)) por semana."
        )
    }

    private func publishCurrencyToWidget() {
        let appGroupDefaults = UserDefaults(suiteName: WidgetData.appGroup)
        appGroupDefaults?.set(currency.currencyCode, forKey: WidgetData.currencyCodeKey)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetData.kind)
    }
}
