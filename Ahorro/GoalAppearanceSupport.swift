//
//  GoalAppearanceSupport.swift
//  Ahorro
//
//  Elementos visuales reutilizables para personalizar cada meta.
//

import SwiftUI
import UIKit
import PhotosUI

/// Temas disponibles para una meta. Los nombres cortos se guardan en
/// `Goal.themeName`, por lo que son estables para persistencia y exportación.
enum GoalTheme: String, CaseIterable, Identifiable, Codable {
    case sage
    case ocean
    case sunrise
    case berry
    case amber
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sage: "Salvia"
        case .ocean: "Océano"
        case .sunrise: "Amanecer"
        case .berry: "Baya"
        case .amber: "Ámbar"
        case .graphite: "Grafito"
        }
    }

    var defaultIconName: String {
        switch self {
        case .sage: "leaf.fill"
        case .ocean: "water.waves"
        case .sunrise: "sun.max.fill"
        case .berry: "heart.fill"
        case .amber: "sparkles"
        case .graphite: "flag.fill"
        }
    }

    /// El color base se mantiene legible tanto sobre los fondos claros como
    /// oscuros definidos por la paleta de la aplicación.
    var tint: Color {
        switch self {
        case .sage: .accentC
        case .ocean: Color(hex: "4E7F98")
        case .sunrise: Color(hex: "B46E4C")
        case .berry: Color(hex: "975C79")
        case .amber: Color(hex: "A47B35")
        case .graphite: .mutedC
        }
    }

    var deepTint: Color {
        switch self {
        case .sage: .accentStrong
        case .ocean: Color(hex: "315E77")
        case .sunrise: Color(hex: "8D4A32")
        case .berry: Color(hex: "743A5A")
        case .amber: Color(hex: "75531F")
        case .graphite: Color(hex: "54565A")
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.95), deepTint.opacity(0.88)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    init(themeName: String?) {
        let normalized = themeName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        self = GoalTheme(rawValue: normalized ?? "") ?? .sage
    }
}

/// Un catálogo compacto de SF Symbols que funcionan bien dentro de la insignia
/// y permiten crear metas de viaje, vehículo, hogar o emergencia sin fotos.
enum GoalIconCatalog {
    static let symbols = [
        "target",
        "flag.fill",
        "car.fill",
        "airplane",
        "house.fill",
        "motorcycle",
        "graduationcap.fill",
        "cross.case.fill",
        "gift.fill",
        "heart.fill",
        "briefcase.fill",
        "sparkles"
    ]
}

/// Adaptadores de lectura para que las vistas no tengan que repetir el manejo
/// de valores opcionales guardados en la meta.
///
/// Los tres campos (`iconName`, `themeName`, `coverImageFileName`) se guardan
/// opcionalmente en `Goal`. Al ser nil, la meta conserva una apariencia limpia
/// de salvia y un icono de objetivo.
extension Goal {
    var resolvedGoalTheme: GoalTheme {
        GoalTheme(themeName: themeName)
    }

    var resolvedGoalIconName: String {
        let candidate = iconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return candidate.isEmpty ? resolvedGoalTheme.defaultIconName : candidate
    }

    var resolvedGoalCoverImage: UIImage? {
        guard let filename = coverImageFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !filename.isEmpty else {
            return nil
        }

        return GoalCoverStore.image(named: filename)
    }
}

/// Insignia circular que identifica una meta en tarjetas, títulos y listas.
struct GoalIdentityBadge: View {
    let iconName: String
    let theme: GoalTheme
    let size: CGFloat
    let showBorder: Bool

    init(goal: Goal, size: CGFloat = 42, showBorder: Bool = true) {
        self.iconName = goal.resolvedGoalIconName
        self.theme = goal.resolvedGoalTheme
        self.size = size
        self.showBorder = showBorder
    }

    init(iconName: String, theme: GoalTheme = .sage, size: CGFloat = 42, showBorder: Bool = true) {
        self.iconName = iconName
        self.theme = theme
        self.size = size
        self.showBorder = showBorder
    }

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundColor(theme.deepTint)
            .frame(width: size, height: size)
            .background(theme.tint.opacity(0.18))
            .clipShape(Circle())
            .overlay {
                if showBorder {
                    Circle().stroke(theme.tint.opacity(0.30), lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Portada decorativa de una meta. Si `coverImageFileName` apunta a una imagen
/// local guardada para la meta, se muestra sobre el degradado; de lo contrario
/// presenta una portada de color con el icono de la meta.
struct GoalCoverView: View {
    let goal: Goal
    let height: CGFloat
    let showsName: Bool

    init(goal: Goal, height: CGFloat = 154, showsName: Bool = true) {
        self.goal = goal
        self.height = height
        self.showsName = showsName
    }

    var body: some View {
        let theme = goal.resolvedGoalTheme

        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(theme.gradient)

            if let image = goal.resolvedGoalCoverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.05), .black.opacity(0.48)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                Image(systemName: goal.resolvedGoalIconName)
                    .font(.system(size: height * 0.82, weight: .semibold))
                    .foregroundColor(.white.opacity(0.13))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 56, y: -24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .clipped()
            }

            if showsName {
                HStack(spacing: 11) {
                    GoalIdentityBadge(goal: goal, size: 40, showBorder: false)
                        .background(Color.white.opacity(0.86))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if let motivation = goal.motivation,
                           !motivation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(motivation)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.90))
                                .lineLimit(1)
                        }
                        Text("\(Int((goal.progress * 100).rounded()))% completado")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.82))
                    }
                }
                .padding(17)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.borderC))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Portada de la meta \(goal.name)")
    }
}

/// Selector reutilizable de temas para formularios de creación y edición.
/// La pantalla que lo use solo necesita persistir el `rawValue` elegido en
/// `Goal.themeName`.
struct GoalThemePicker: View {
    @Binding var themeName: String

    private var selectedTheme: GoalTheme {
        GoalTheme(themeName: themeName)
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(GoalTheme.allCases) { theme in
                Button {
                    themeName = theme.rawValue
                } label: {
                    Circle()
                        .fill(theme.gradient)
                        .frame(width: 31, height: 31)
                        .overlay {
                            if selectedTheme == theme {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .overlay(Circle().stroke(selectedTheme == theme ? Color.textC.opacity(0.75) : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tema \(theme.title)")
                .accessibilityAddTraits(selectedTheme == theme ? .isSelected : [])
            }
        }
    }
}

/// Selector pequeño de iconos. Es deliberadamente independiente de las hojas
/// del sistema para que sea seguro usarlo dentro de un `Form` de SwiftUI.
struct GoalIconPicker: View {
    @Binding var iconName: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4), spacing: 9) {
            ForEach(GoalIconCatalog.symbols, id: \.self) { symbol in
                Button {
                    iconName = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(iconName == symbol ? .accentStrong : .mutedC)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(iconName == symbol ? Color.accentC.opacity(0.16) : Color.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(iconName == symbol ? Color.accentC.opacity(0.42) : Color.borderC))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Icono \(symbol)")
                .accessibilityAddTraits(iconName == symbol ? .isSelected : [])
            }
        }
    }
}

/// Hoja lista para presentar desde el detalle de una meta. Conserva la edición
/// visual separada de los datos financieros e incluye la selección segura de
/// una foto local para la portada.
struct GoalAppearanceEditorSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let goal: Goal

    @State private var iconName = "target"
    @State private var themeName = GoalTheme.sage.rawValue
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var replacementCoverData: Data?
    @State private var replacementCoverImage: UIImage?
    @State private var removesCurrentCover = false
    @State private var isLoadingPhoto = false
    @State private var photoError: String?

    /// Da prioridad a una foto recién elegida; si no hay una, conserva la
    /// portada actual mientras el usuario no haya elegido eliminarla.
    private var previewImage: UIImage? {
        if let replacementCoverImage { return replacementCoverImage }
        return removesCurrentCover ? nil : goal.resolvedGoalCoverImage
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        GoalIdentityBadge(
                            iconName: normalizedIconName,
                            theme: GoalTheme(themeName: themeName),
                            size: 54
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(goal.name)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                            Text("Personaliza cómo se ve esta meta")
                                .font(.footnote)
                                .foregroundColor(.mutedC)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    GoalThemePicker(themeName: $themeName)
                        .padding(.vertical, 4)
                }

                Section("Icono") {
                    GoalIconPicker(iconName: $iconName)
                        .padding(.vertical, 4)
                }

                Section("Imagen de portada (opcional)") {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 155)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderC))
                            .accessibilityLabel("Vista previa de la portada")
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(
                            previewImage == nil ? "Elegir foto" : "Cambiar foto",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                    .disabled(isLoadingPhoto)

                    if isLoadingPhoto {
                        HStack(spacing: 9) {
                            ProgressView()
                            Text("Preparando la foto…")
                                .foregroundColor(.mutedC)
                        }
                    }

                    if previewImage != nil {
                        Button("Eliminar foto", role: .destructive) {
                            selectedPhoto = nil
                            replacementCoverData = nil
                            replacementCoverImage = nil
                            removesCurrentCover = true
                            photoError = nil
                        }
                    } else if goal.coverImageFileName != nil, removesCurrentCover {
                        Button("Conservar foto actual") {
                            removesCurrentCover = false
                            photoError = nil
                        }
                    }

                    if let photoError {
                        Text(photoError)
                            .font(.caption)
                            .foregroundColor(.dangerC)
                    } else {
                        Text("La foto queda guardada solo en este dispositivo y se usa como portada de esta meta.")
                            .font(.caption)
                            .foregroundColor(.mutedC)
                    }
                }
            }
            .navigationTitle("Personalizar meta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        saveAppearance()
                    }
                    .disabled(isLoadingPhoto)
                }
            }
        }
        .onAppear {
            iconName = goal.resolvedGoalIconName
            themeName = goal.resolvedGoalTheme.rawValue
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(from: newItem) }
        }
    }

    private var normalizedIconName: String {
        let trimmed = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? GoalTheme(themeName: themeName).defaultIconName : trimmed
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem) async {
        isLoadingPhoto = true
        photoError = nil
        defer { isLoadingPhoto = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                photoError = "No se pudo leer esta foto. Elige otra imagen."
                return
            }

            replacementCoverData = data
            replacementCoverImage = image
            removesCurrentCover = false
        } catch {
            photoError = "No se pudo cargar esta foto. Inténtalo de nuevo."
        }
    }

    private func saveAppearance() {
        var coverImageFileName = goal.coverImageFileName

        if let replacementCoverData {
            guard let savedFilename = GoalCoverStore.save(replacementCoverData, for: goal.id) else {
                photoError = "No fue posible guardar la foto en el dispositivo."
                return
            }
            coverImageFileName = savedFilename
        } else if removesCurrentCover {
            coverImageFileName = nil
        }

        // `Store` elimina la portada anterior después de actualizar la meta
        // cuando su nombre cambia. Al reutilizar el mismo nombre al reemplazar
        // una foto, se sobrescribe el archivo de forma atómica y no se borra.
        store.updateGoalAppearance(
            goal,
            iconName: normalizedIconName,
            themeName: themeName,
            coverImageFileName: coverImageFileName
        )
        dismiss()
    }
}
