//
//  GoalCoverStore.swift
//  Ahorro
//
//  Persistencia local de las imágenes de portada elegidas para cada meta.
//

import Foundation
import UIKit

enum GoalCoverStore {
    private static var directoryURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("GoalCovers", isDirectory: true)
    }

    @discardableResult
    static func save(_ data: Data, for goalID: UUID) -> String? {
        let filename = "goal-\(goalID.uuidString).jpg"
        let fileURL = directoryURL.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let compactData = UIImage(data: data)?.jpegData(compressionQuality: 0.82) ?? data
            try compactData.write(to: fileURL, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func image(named filename: String?) -> UIImage? {
        guard let filename else { return nil }
        let fileURL = directoryURL.appendingPathComponent(filename)
        return UIImage(contentsOfFile: fileURL.path)
    }

    static func remove(named filename: String?) {
        guard let filename else { return }
        let fileURL = directoryURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
