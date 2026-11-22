import Foundation
import HealthKit

/// The Beurer BF500 syncs to Beurer HealthManager Pro, which writes to Apple Health.
/// HomeOn only reads from Health: weight, body fat, BMI and lean mass.
enum HealthScale {
    static let store = HKHealthStore()
    static let kinds: [(String, HKQuantityTypeIdentifier, HKUnit)] = [
        ("w", .bodyMass, .gramUnit(with: .kilo)),
        ("fat", .bodyFatPercentage, .percent()),
        ("bmi", .bodyMassIndex, .count()),
        ("lean", .leanBodyMass, .gramUnit(with: .kilo)),
    ]

    static func json(_ o: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func handle(_ body: [String: Any]) async throws -> String {
        guard HKHealthStore.isHealthDataAvailable() else { return json(["ok": false, "why": "nohealth"]) }
        let types = Set(kinds.compactMap { HKQuantityType.quantityType(forIdentifier: $0.1) })
        switch body["cmd"] as? String ?? "read" {
        case "auth":
            try await store.requestAuthorization(toShare: [], read: types)
            return json(["ok": true])
        default:
            let days = max(7, min(800, body["days"] as? Int ?? 400))
            if (try? await store.statusForAuthorizationRequest(toShare: [], read: types)) == .shouldRequest {
                return json(["ok": true, "ask": true, "w": [], "fat": [], "bmi": [], "lean": []])
            }
            let from = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            var out: [String: Any] = ["ok": true]
            for (key, id, unit) in kinds {
                guard let t = HKQuantityType.quantityType(forIdentifier: id) else { continue }
                out[key] = (try? await samples(t, unit: unit, from: from)) ?? []
            }
            return json(out)
        }
    }

    /// [[t(ms), value, source]] oldest first
    static func samples(_ t: HKQuantityType, unit: HKUnit, from: Date) async throws -> [[Any]] {
        try await withCheckedThrowingContinuation { c in
            let q = HKSampleQuery(sampleType: t, predicate: HKQuery.predicateForSamples(withStart: from, end: nil),
                                  limit: 3000, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, e in
                if let e { return c.resume(throwing: e) }
                let rows: [[Any]] = (s as? [HKQuantitySample] ?? []).map {
                    var v = $0.quantity.doubleValue(for: unit)
                    if unit == .percent() { v *= 100 }
                    return [Int($0.startDate.timeIntervalSince1970 * 1000), (v * 100).rounded() / 100, $0.sourceRevision.source.name]
                }
                c.resume(returning: rows)
            }
            store.execute(q)
        }
    }
}
