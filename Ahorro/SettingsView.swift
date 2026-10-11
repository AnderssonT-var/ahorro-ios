//
//  SettingsView.swift
//  Ahorro
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var pdfReport: PDFReport?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsSectionTitle("SINCRONIZACIÓN")
                    SettingsCard {
                        SettingsRowLabel(
                            symbol: "icloud.slash.fill",
                            tint: .mutedC,
                            title: "iCloud",
                            detail: "Disponible con Apple Developer Program"
                        )
                    }

                    Text("Esta versión guarda tus metas en este dispositivo. La sincronización entre iPhone y Mac se podrá activar al usar una cuenta de Apple Developer con CloudKit.")
                        .font(.caption)
                        .foregroundColor(.mutedC)
                        .padding(.horizontal, 4)

                    SettingsSectionTitle("SEGURIDAD")
                    SettingsCard {
                        Toggle(isOn: faceIDBinding) {
                            SettingsRowLabel(
                                symbol: "faceid",
                                tint: .accentC,
                                title: settings.biometricDisplayName,
                                detail: "Pedirlo al abrir o volver a la app"
                            )
                        }
                        .tint(.accentC)
                    }

                    SettingsSectionTitle("NOTIFICACIONES")
                    SettingsCard {
                        Toggle(isOn: remindersBinding) {
                            SettingsRowLabel(
                                symbol: "bell.fill",
                                tint: .accentC,
                                title: "Recordatorios",
                                detail: "Un recordatorio inteligente a las 19:00"
                            )
                        }
                        .tint(.accentC)
                    }

                    SettingsSectionTitle("PREFERENCIAS")
                    SettingsCard(spacing: 0) {
                        NavigationLink { CurrencyPickerView() } label: {
                            SettingsActionRow(
                                symbol: settings.currency.sfSymbol,
                                tint: .accentC,
                                title: "Moneda predeterminada",
                                value: settings.currency.title
                            )
                        }
                        .buttonStyle(.plain)

                        SettingsDivider()

                        NavigationLink { AppearancePickerView() } label: {
                            SettingsActionRow(
                                symbol: settings.appearance.sfSymbol,
                                tint: .accentC,
                                title: "Apariencia",
                                value: settings.appearance.title
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    SettingsSectionTitle("REPORTE")
                    SettingsCard {
                        Button(action: exportPDF) {
                            SettingsActionRow(
                                symbol: "doc.richtext.fill",
                                tint: .accentC,
                                title: "Exportar en PDF",
                                value: "Reporte de ahorros"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    SettingsSectionTitle("INFORMACIÓN")
                    SettingsCard(spacing: 0) {
                        SettingsActionRow(
                            symbol: "info.circle.fill",
                            tint: .accentC,
                            title: "Versión",
                            value: appVersion,
                            showsChevron: false
                        )

                        SettingsDivider()

                        SettingsActionRow(
                            symbol: "person.crop.circle.fill",
                            tint: .accentC,
                            title: "Creado por",
                            value: "A.T.",
                            showsChevron: false
                        )
                    }

                    Text("Ahorro te ayuda a avanzar una casilla a la vez.")
                        .font(.footnote)
                        .foregroundColor(.mutedC)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.bg)
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .sheet(item: $pdfReport) { report in
                PDFPreviewSheet(url: report.url)
            }
            .alert("No se pudo exportar el PDF", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("Aceptar", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "Inténtalo de nuevo.")
            }
            .alert(settings.biometricDisplayName, isPresented: Binding(
                get: { settings.faceIDSetupMessage != nil },
                set: { if !$0 { settings.dismissFaceIDSetupMessage() } }
            )) {
                Button("Aceptar", role: .cancel) { settings.dismissFaceIDSetupMessage() }
            } message: {
                Text(settings.faceIDSetupMessage ?? "Inténtalo de nuevo.")
            }
        }
        .tint(.accentC)
    }

    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { settings.remindersEnabled },
            set: { enabled in
                Task {
                    await settings.setRemindersEnabled(enabled)
                    // Al conceder el permiso, sustituye el texto genérico por
                    // uno basado en la meta cuya fecha límite está más cerca.
                    if settings.remindersEnabled {
                        await settings.refreshSmartReminder(for: store.goals)
                    }
                }
            }
        )
    }

    private var faceIDBinding: Binding<Bool> {
        Binding(
            get: { settings.faceIDEnabled },
            set: { enabled in
                Task { await settings.setFaceIDEnabled(enabled) }
            }
        )
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }

    private func exportPDF() {
        do {
            pdfReport = PDFReport(url: try SavingsPDFExporter.makeReport(goals: store.goals, currency: settings.currency))
        } catch {
            exportError = error.localizedDescription
        }
    }
}

struct CurrencyPickerView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(AppCurrency.allCases) { currency in
                Button {
                    settings.currency = currency
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: currency.sfSymbol)
                            .foregroundColor(.accentC)
                            .frame(width: 24)
                        Text(currency.title)
                            .foregroundColor(.textC)
                        Spacer()
                        if currency == settings.currency {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundColor(.accentC)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Moneda")
    }
}

struct AppearancePickerView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(AppAppearance.allCases) { appearance in
                Button {
                    settings.appearance = appearance
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: appearance.sfSymbol)
                            .foregroundColor(.accentC)
                            .frame(width: 24)
                        Text(appearance.title)
                            .foregroundColor(.textC)
                        Spacer()
                        if appearance == settings.appearance {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundColor(.accentC)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Apariencia")
    }
}

private struct SettingsSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(1.1)
            .foregroundColor(.mutedC)
            .padding(.horizontal, 4)
    }
}

private struct SettingsCard<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(spacing: spacing) {
            content
        }
        .padding(spacing == 0 ? 0 : 16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderC))
    }
}

private struct SettingsRowLabel: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.textC)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.mutedC)
            }
        }
    }
}

private struct SettingsActionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    let showsChevron: Bool

    init(symbol: String, tint: Color, title: String, value: String, showsChevron: Bool = true) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.value = value
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.textC)
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.accentC)
                    .lineLimit(1)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.mutedC2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderC)
            .frame(height: 1)
            .padding(.leading, 62)
    }
}
