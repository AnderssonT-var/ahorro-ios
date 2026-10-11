//
//  CloudKitSyncService.swift
//  Ahorro
//
//  Sincronización privada de las metas entre dispositivos del mismo Apple ID.
//

#if CLOUDKIT_SYNC
import CloudKit
#endif
import Foundation

enum CloudSyncStatus: Equatable {
    case disabled
    case syncing
    case synced(Date)
    case unavailable(String)
    case failed(String)

    var settingsDetail: String {
        switch self {
        case .disabled:
            return "Sincronizar metas entre dispositivos"
        case .syncing:
            return "Sincronizando…"
        case .synced:
            return "Metas sincronizadas"
        case .unavailable:
            return "iCloud no disponible"
        case .failed:
            return "Reintentar sincronización"
        }
    }

    var message: String? {
        switch self {
        case let .unavailable(message), let .failed(message): message
        default: nil
        }
    }
}

// El código de CloudKit permanece preparado para la versión firmada con el
// Apple Developer Program. Esta compilación local no define CLOUDKIT_SYNC,
// por lo que no enlaza ni ejecuta ningún servicio de iCloud.
#if CLOUDKIT_SYNC

/// Registra eliminaciones para que una meta borrada en un dispositivo no
/// vuelva a aparecer al descargar una copia más antigua desde otro equipo.
struct AhorroCloudTombstones: Codable, Equatable {
    var deletedGoals: [String: Date] = [:]
}

/// Un único registro privado de CloudKit contiene el estado de ahorro del
/// usuario. Cada meta conserva su `updatedAt`, lo que permite combinar los
/// cambios independientes hechos sin conexión antes del siguiente sync.
struct AhorroCloudSnapshot: Codable, Equatable {
    var goals: [Goal]
    var tombstones: AhorroCloudTombstones

    static func merged(_ left: AhorroCloudSnapshot, _ right: AhorroCloudSnapshot) -> AhorroCloudSnapshot {
        var tombstones = AhorroCloudTombstones()
        let tombstoneIDs = Set(left.tombstones.deletedGoals.keys)
            .union(right.tombstones.deletedGoals.keys)

        for id in tombstoneIDs {
            let leftDate = left.tombstones.deletedGoals[id] ?? .distantPast
            let rightDate = right.tombstones.deletedGoals[id] ?? .distantPast
            tombstones.deletedGoals[id] = max(leftDate, rightDate)
        }

        let leftByID = Dictionary(uniqueKeysWithValues: left.goals.map { ($0.id, $0) })
        let rightByID = Dictionary(uniqueKeysWithValues: right.goals.map { ($0.id, $0) })
        let allIDs = Set(leftByID.keys).union(rightByID.keys)
        var mergedGoals: [Goal] = []

        for id in allIDs {
            let candidate: Goal?
            switch (leftByID[id], rightByID[id]) {
            case let (leftGoal?, rightGoal?):
                candidate = mergeGoal(leftGoal, rightGoal)
            case let (leftGoal?, nil):
                candidate = leftGoal
            case let (nil, rightGoal?):
                candidate = rightGoal
            case (nil, nil):
                candidate = nil
            }

            guard let goal = candidate else { continue }
            let key = id.uuidString
            if let deletedAt = tombstones.deletedGoals[key], deletedAt >= goal.updatedAt {
                continue
            }

            // Un cambio más reciente que un borrado es una recreación válida
            // de la meta en otro dispositivo; ya no conservamos su lápida.
            tombstones.deletedGoals.removeValue(forKey: key)
            mergedGoals.append(goal)
        }

        return AhorroCloudSnapshot(
            goals: mergedGoals.sorted { $0.updatedAt > $1.updatedAt },
            tombstones: tombstones
        )
    }

    private static func mergeGoal(_ left: Goal, _ right: Goal) -> Goal {
        var winner = left.updatedAt >= right.updatedAt ? left : right
        let other = left.updatedAt >= right.updatedAt ? right : left

        // Los depósitos tienen UUID propios. Unimos los que se agregaron en
        // paralelo para no perder un ahorro hecho desde el iPhone o la Mac.
        var deposits = Dictionary(uniqueKeysWithValues: winner.deposits.map { ($0.id, $0) })
        for deposit in other.deposits where deposits[deposit.id] == nil {
            deposits[deposit.id] = deposit
        }
        winner.deposits = deposits.values.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.id.uuidString < rhs.id.uuidString : lhs.date < rhs.date
        }
        return winner
    }
}

enum AhorroCloudSyncError: LocalizedError {
    case accountUnavailable

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            return "Inicia sesión en iCloud para sincronizar tus metas."
        }
    }
}

actor CloudKitSyncService {
    static let containerIdentifier = "iCloud.com.personal.Ahorro"
    static let snapshotRecordType = "AhorroSnapshot"
    static let snapshotRecordName = "current"
    static let widgetRecordType = "AhorroWidgetSnapshot"
    static let widgetRecordName = "current"

    private let container = CKContainer(identifier: CloudKitSyncService.containerIdentifier)

    private var database: CKDatabase { container.privateCloudDatabase }

    func synchronize(
        localSnapshot: AhorroCloudSnapshot,
        currencyCode: String
    ) async throws -> AhorroCloudSnapshot {
        guard try await container.accountStatus() == .available else {
            throw AhorroCloudSyncError.accountUnavailable
        }

        let recordID = CKRecord.ID(recordName: Self.snapshotRecordName)
        let remoteRecord = try await fetchRecordIfItExists(id: recordID)
        let remoteSnapshot = remoteRecord.flatMap(decodeSnapshot(from:))
            ?? AhorroCloudSnapshot(goals: [], tombstones: .init())
        let merged = AhorroCloudSnapshot.merged(localSnapshot, remoteSnapshot)

        if remoteRecord == nil || remoteSnapshot != merged {
            let record = remoteRecord ?? CKRecord(recordType: Self.snapshotRecordType, recordID: recordID)
            record["payload"] = try encodedSnapshot(merged) as CKRecordValue
            record["schemaVersion"] = 1 as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            _ = try await database.save(record)
        }

        try await publishWidgetSnapshot(from: merged.goals, currencyCode: currencyCode)
        return merged
    }

    private func fetchRecordIfItExists(id: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func encodedSnapshot(_ snapshot: AhorroCloudSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    private func decodeSnapshot(from record: CKRecord) -> AhorroCloudSnapshot? {
        guard let payload = record["payload"] as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AhorroCloudSnapshot.self, from: payload)
    }

    /// El widget de Mac puede leer este registro compacto directamente cuando
    /// la app no está abierta. Es el mismo resumen que publica el App Group.
    private func publishWidgetSnapshot(from goals: [Goal], currencyCode: String) async throws {
        let goal = goals.first(where: { $0.progress < 1 }) ?? goals.first
        let recordID = CKRecord.ID(recordName: Self.widgetRecordName)
        let record = try await fetchRecordIfItExists(id: recordID)
            ?? CKRecord(recordType: Self.widgetRecordType, recordID: recordID)

        record["hasGoal"] = (goal != nil ? 1 : 0) as CKRecordValue
        record["currencyCode"] = currencyCode.uppercased() as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue

        if let goal {
            record["goalID"] = goal.id.uuidString as CKRecordValue
            record["name"] = goal.name as CKRecordValue
            record["saved"] = goal.saved as CKRecordValue
            record["target"] = goal.target as CKRecordValue
            record["progress"] = goal.progress as CKRecordValue
            record["stepsRemaining"] = goal.pendingCellCount as CKRecordValue
            if let nextIndex = goal.activeCellIndices.first(where: { !goal.isCellDone($0) }) {
                record["nextCellIndex"] = nextIndex as CKRecordValue
                record["nextCellAmount"] = goal.amounts[nextIndex] as CKRecordValue
            } else {
                record["nextCellIndex"] = nil
                record["nextCellAmount"] = nil
            }
        } else {
            ["goalID", "name", "saved", "target", "progress", "stepsRemaining", "nextCellIndex", "nextCellAmount"].forEach {
                record[$0] = nil
            }
        }
        _ = try await database.save(record)
    }
}

#endif
