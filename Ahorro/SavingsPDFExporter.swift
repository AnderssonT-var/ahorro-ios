//
//  SavingsPDFExporter.swift
//  Ahorro
//
//  Genera un reporte local, listo para previsualizar o compartir.
//

import Foundation
import QuickLook
import SwiftUI
import UIKit

struct PDFReport: Identifiable {
    let url: URL

    var id: URL { url }
}

enum SavingsPDFExporter {
    private static let pageSize = CGSize(width: 595.2, height: 841.8) // A4 en puntos PDF

    static func makeReport(goals: [Goal], currency: AppCurrency) throws -> URL {
        let exportsDirectory = try reportDirectory()
        let outputURL = exportsDirectory.appendingPathComponent("Ahorro-Reporte-\(fileStamp()).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        try renderer.writePDF(to: outputURL) { context in
            let canvas = SavingsPDFCanvas(
                context: context,
                pageSize: pageSize,
                goals: goals,
                currency: currency
            )
            canvas.render()
        }

        return outputURL
    }

    private static func reportDirectory() throws -> URL {
        let baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent("Reportes", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private final class SavingsPDFCanvas {
    private let context: UIGraphicsPDFRendererContext
    private let pageSize: CGSize
    private let goals: [Goal]
    private let currency: AppCurrency

    private let margin: CGFloat = 42
    private let footerHeight: CGFloat = 30
    private var pageNumber = 0
    private var cursorY: CGFloat = 0

    private let ink = UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
    private let muted = UIColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 1)
    private let divider = UIColor(red: 0.84, green: 0.84, blue: 0.84, alpha: 1)
    private let track = UIColor(red: 0.89, green: 0.89, blue: 0.89, alpha: 1)
    private let accent = UIColor(red: 0.22, green: 0.68, blue: 0.49, alpha: 1)

    private var pageBounds: CGRect {
        CGRect(origin: .zero, size: pageSize)
    }

    private var contentWidth: CGFloat {
        pageSize.width - (margin * 2)
    }

    private var contentBottom: CGFloat {
        pageSize.height - margin - footerHeight
    }

    init(
        context: UIGraphicsPDFRendererContext,
        pageSize: CGSize,
        goals: [Goal],
        currency: AppCurrency
    ) {
        self.context = context
        self.pageSize = pageSize
        self.goals = goals
        self.currency = currency
    }

    func render() {
        beginPage(isContinuation: false)
        drawOverview()

        if goals.isEmpty {
            ensureSpace(58)
            drawText(
                "Aun no hay metas registradas para incluir en este reporte.",
                at: CGPoint(x: margin, y: cursorY),
                width: contentWidth,
                font: .systemFont(ofSize: 12),
                color: muted
            )
            cursorY += 58
        } else {
            for goal in goals {
                drawGoal(goal)
            }
        }

        drawFooter()
    }

    private func beginPage(isContinuation: Bool) {
        pageNumber += 1
        context.beginPage()
        UIColor.white.setFill()
        UIRectFill(pageBounds)
        cursorY = margin

        guard isContinuation else { return }

        drawText(
            "Ahorro - Reporte de ahorros",
            at: CGPoint(x: margin, y: cursorY),
            width: contentWidth,
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: ink
        )
        cursorY += 27
        drawLine(at: cursorY)
        cursorY += 20
    }

    private func drawOverview() {
        let totalSaved = goals.reduce(0) { $0 + $1.saved }
        let activeGoals = goals.filter { $0.progress < 1 }.count
        let completedGoals = goals.filter { $0.progress >= 1 }.count
        let transactions = goals.reduce(0) { $0 + $1.deposits.count }

        drawText(
            "Ahorro - Reporte de ahorros",
            at: CGPoint(x: margin, y: cursorY),
            width: contentWidth,
            font: .systemFont(ofSize: 22, weight: .bold),
            color: ink
        )
        cursorY += 30

        drawText(
            "Generado el \(reportDate())",
            at: CGPoint(x: margin, y: cursorY),
            width: contentWidth,
            font: .systemFont(ofSize: 10),
            color: muted
        )
        cursorY += 22
        drawLine(at: cursorY)
        cursorY += 17

        drawText(
            "Total ahorrado: \(money(totalSaved))",
            at: CGPoint(x: margin, y: cursorY),
            width: contentWidth,
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: ink
        )
        cursorY += 20

        let summary = "Metas activas: \(activeGoals)    Completadas: \(completedGoals)    Transacciones: \(transactions)"
        drawText(
            summary,
            at: CGPoint(x: margin, y: cursorY),
            width: contentWidth,
            font: .systemFont(ofSize: 11),
            color: ink
        )
        cursorY += 24
        drawLine(at: cursorY)
        cursorY += 22
    }

    private func drawGoal(_ goal: Goal) {
        let movements = Array(goal.deposits.sorted { $0.date > $1.date }.prefix(5))
        let additionalNoteHeight: CGFloat = goal.deposits.count > movements.count ? 16 : 0
        let deadlineHeight: CGFloat = goal.deadline == nil ? 0 : 19
        let estimatedHeight = 139 + deadlineHeight + (CGFloat(movements.count) * 18) + additionalNoteHeight
        ensureSpace(estimatedHeight)

        drawText(
            goal.name,
            at: CGPoint(x: margin, y: cursorY),
            width: contentWidth,
            font: .systemFont(ofSize: 14, weight: .bold),
            color: ink
        )
        cursorY += 23

        drawProgressBar(progress: goal.progress, at: cursorY)
        cursorY += 17

        let percent = Int((min(max(goal.progress, 0), 1) * 100).rounded())
        let detail = "\(money(goal.saved)) de \(money(goal.target)) (\(percent)%) - Restante: \(money(goal.remaining))"
        drawText(
            detail,
            at: CGPoint(x: margin, y: cursorY),
            width: contentWidth,
            font: .systemFont(ofSize: 10.5),
            color: muted
        )
        cursorY += 21

        if let deadlineDetail = deadlineDetail(for: goal) {
            drawText(
                deadlineDetail,
                at: CGPoint(x: margin, y: cursorY),
                width: contentWidth,
                font: .systemFont(ofSize: 10),
                color: muted
            )
            cursorY += 19
        }

        drawText(
            "TRANSACCIONES",
            at: CGPoint(x: margin, y: cursorY),
            width: contentWidth,
            font: .systemFont(ofSize: 9, weight: .bold),
            color: muted
        )
        cursorY += 16

        if movements.isEmpty {
            drawText(
                "Sin movimientos registrados.",
                at: CGPoint(x: margin, y: cursorY),
                width: contentWidth,
                font: .systemFont(ofSize: 10),
                color: muted
            )
            cursorY += 18
        } else {
            for movement in movements {
                drawMovement(movement)
                cursorY += 18
            }
        }

        if goal.deposits.count > movements.count {
            drawText(
                "Se muestran los 5 movimientos mas recientes.",
                at: CGPoint(x: margin, y: cursorY),
                width: contentWidth,
                font: .systemFont(ofSize: 9),
                color: muted
            )
            cursorY += 16
        }

        cursorY += 7
        drawLine(at: cursorY)
        cursorY += 18
    }

    private func drawMovement(_ movement: Deposit) {
        let dateWidth: CGFloat = 88
        let amountWidth: CGFloat = 112
        let labelX = margin + dateWidth + amountWidth
        let labelWidth = contentWidth - dateWidth - amountWidth

        drawText(
            movementDate(movement.date),
            at: CGPoint(x: margin, y: cursorY),
            width: dateWidth,
            font: .systemFont(ofSize: 9.5),
            color: muted,
            lineBreakMode: .byTruncatingTail
        )
        drawText(
            "+\(money(movement.amount))",
            at: CGPoint(x: margin + dateWidth, y: cursorY),
            width: amountWidth,
            font: .systemFont(ofSize: 9.5, weight: .semibold),
            color: ink,
            lineBreakMode: .byTruncatingTail
        )
        drawText(
            movementLabel(movement),
            at: CGPoint(x: labelX, y: cursorY),
            width: labelWidth,
            font: .systemFont(ofSize: 9.5),
            color: muted,
            lineBreakMode: .byTruncatingTail
        )
    }

    private func drawProgressBar(progress: Double, at y: CGFloat) {
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: 7)
        context.cgContext.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).addClip()
        track.setFill()
        UIRectFill(rect)

        let clampedProgress = min(max(progress, 0), 1)
        let filledRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * clampedProgress, height: rect.height)
        accent.setFill()
        UIRectFill(filledRect)
        context.cgContext.restoreGState()
    }

    private func ensureSpace(_ height: CGFloat) {
        guard cursorY + height > contentBottom else { return }
        drawFooter()
        beginPage(isContinuation: true)
    }

    private func drawFooter() {
        let footerText = "Creado por A.T.    Pagina \(pageNumber)"
        drawLine(at: pageSize.height - margin - footerHeight + 8)
        drawText(
            footerText,
            at: CGPoint(x: margin, y: pageSize.height - margin - 13),
            width: contentWidth,
            font: .systemFont(ofSize: 9),
            color: muted,
            alignment: .center
        )
    }

    private func drawLine(at y: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
        divider.setStroke()
        path.lineWidth = 0.65
        path.stroke()
    }

    private func drawText(
        _ text: String,
        at origin: CGPoint,
        width: CGFloat,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        paragraph.minimumLineHeight = font.lineHeight
        paragraph.maximumLineHeight = font.lineHeight

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: font.lineHeight + 2)
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func money(_ value: Double) -> String {
        currency.formatted(value)
    }

    private func reportDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_EC")
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy"
        return formatter.string(from: Date())
    }

    private func movementDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_EC")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private func movementLabel(_ movement: Deposit) -> String {
        switch movement.type {
        case .cell:
            if let index = movement.idx { return "Casilla \(index + 1)" }
            return "Casilla marcada"
        case .recurring:
            let note = movement.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return note.isEmpty ? "Depósito programado" : "Programado · \(note)"
        case .manual:
            let note = movement.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return note.isEmpty ? "Depósito manual" : note
        }
    }

    private func deadlineDetail(for goal: Goal) -> String? {
        guard let deadline = goal.deadline else { return nil }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: deadline)
        let days = max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
        let dateText = goalDeadlineDate(deadline)

        guard goal.remaining > 0 else {
            return "Fecha límite: \(dateText) · Meta completada"
        }

        let weeks = max(Double(max(days, 1)) / 7, 1.0 / 7.0)
        let weeklyAmount = goal.remaining / weeks
        let timing = days == 0 ? "vence hoy" : days == 1 ? "falta 1 día" : "faltan \(days) días"
        return "Fecha límite: \(dateText) (\(timing)) · Ritmo: \(money(weeklyAmount))/semana"
    }

    private func goalDeadlineDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_EC")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

struct PDFPreviewSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, dismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let previewController = QLPreviewController()
        previewController.dataSource = context.coordinator
        previewController.title = "Ahorro_Reporte"
        previewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cerrar",
            style: .prominent,
            target: context.coordinator,
            action: #selector(Coordinator.close)
        )
        return UINavigationController(rootViewController: previewController)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        (controller.topViewController as? QLPreviewController)?.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        let dismiss: () -> Void

        init(url: URL, dismiss: @escaping () -> Void) {
            self.url = url
            self.dismiss = dismiss
        }

        @objc func close() {
            dismiss()
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
