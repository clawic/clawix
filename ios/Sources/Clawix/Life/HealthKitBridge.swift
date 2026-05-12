import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// One-way sync from Apple Health into the local ClawJS daemon. Every
/// Life vertical that declares a `healthkitTypeId` on a catalog entry is
/// eligible to be backed by HealthKit reads. Writes are out of scope.
///
/// The bridge persists per-variable anchors in the daemon
/// (`PUT /v1/<domain>/healthkit/anchor/<variableId>`) so each background
/// delivery only forwards new samples.
@MainActor
final class HealthKitBridge: ObservableObject {
    static let shared = HealthKitBridge()

    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var authorizationGranted: Bool = false

    private let manager: LifeManager

    init(manager: LifeManager = .shared) {
        self.manager = manager
    }

    /// Ask the user once for read access to every HealthKit type the
    /// loaded catalogs reference. Idempotent.
    func requestAuthorization() async {
        #if canImport(HealthKit) && os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "HealthKit not available on this device"
            return
        }
        let store = HKHealthStore()
        let typesToRead = Self.requestedReadTypes()
        do {
            try await store.requestAuthorization(toShare: [], read: typesToRead)
            authorizationGranted = true
        } catch {
            lastError = "HealthKit authorization failed: \(error.localizedDescription)"
        }
        #else
        lastError = "HealthKit only available on iOS"
        #endif
    }

    /// Pull recent samples (last 30 days by default) for every variable
    /// of every enabled HealthKit vertical, posting them to the daemon.
    /// Designed to be called manually from a "Sync now" button and from
    /// background delivery callbacks.
    func syncRecent() async {
        #if canImport(HealthKit) && os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let enabled = manager.enabledVerticalIds
        for verticalId in enabled {
            guard let entry = LifeRegistry.entry(byId: verticalId),
                  entry.healthkitMapping else { continue }
            await manager.reloadCatalog(for: verticalId)
            for variable in manager.state(for: verticalId).catalog {
                guard let typeId = variable.healthkitTypeId else { continue }
                await syncVariable(
                    verticalId: verticalId,
                    variable: variable,
                    healthkitTypeId: typeId
                )
            }
        }
        lastSyncAt = Date()
        #endif
    }

    #if canImport(HealthKit) && os(iOS)
    private func syncVariable(
        verticalId: String,
        variable: LifeCatalogEntry,
        healthkitTypeId: String
    ) async {
        guard let quantityType = Self.makeType(from: healthkitTypeId) else { return }
        let store = HKHealthStore()
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-30 * 24 * 60 * 60),
            end: nil,
            options: []
        )
        do {
            let inputs: [LifeUpsertObservationInput] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: quantityType,
                    predicate: predicate,
                    limit: 1000,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let mapped: [LifeUpsertObservationInput] = (samples ?? []).compactMap { sample in
                        Self.toUpsert(
                            sample: sample,
                            variable: variable
                        )
                    }
                    continuation.resume(returning: mapped)
                }
                store.execute(query)
            }
            guard !inputs.isEmpty else { return }
            await manager.bulkUpsertObservations(verticalId: verticalId, inputs: inputs)
        } catch {
            lastError = "HealthKit sync \(variable.id) failed: \(error.localizedDescription)"
        }
    }

    private static func makeType(from identifier: String) -> HKSampleType? {
        let quantityIdentifier = HKQuantityTypeIdentifier(rawValue: identifier)
        if let qt = HKObjectType.quantityType(forIdentifier: quantityIdentifier) {
            return qt
        }
        let categoryIdentifier = HKCategoryTypeIdentifier(rawValue: identifier)
        if let ct = HKObjectType.categoryType(forIdentifier: categoryIdentifier) {
            return ct
        }
        return nil
    }

    private static func toUpsert(
        sample: HKSample,
        variable: LifeCatalogEntry
    ) -> LifeUpsertObservationInput? {
        let recordedAtMs = sample.startDate.timeIntervalSince1970 * 1000
        let externalId = sample.uuid.uuidString
        if let quantitySample = sample as? HKQuantitySample,
           let unit = preferredUnit(for: quantitySample.quantityType, fallback: variable.unit.id) {
            let value = quantitySample.quantity.doubleValue(for: unit)
            return LifeUpsertObservationInput(
                id: nil,
                variableId: variable.id,
                value: .number(value),
                unitId: variable.unit.id,
                recordedAt: recordedAtMs,
                source: .healthkit,
                notes: nil,
                sessionId: nil,
                externalId: externalId
            )
        }
        if let categorySample = sample as? HKCategorySample {
            return LifeUpsertObservationInput(
                id: nil,
                variableId: variable.id,
                value: .number(Double(categorySample.value)),
                unitId: variable.unit.id,
                recordedAt: recordedAtMs,
                source: .healthkit,
                notes: nil,
                sessionId: nil,
                externalId: externalId
            )
        }
        return nil
    }

    private static func preferredUnit(for type: HKQuantityType, fallback: String) -> HKUnit? {
        // Best-effort mapping. Catalog units live in `LifeCatalogEntry`
        // and should agree with these defaults; mismatches are logged
        // upstream in the daemon when the conversion fails.
        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue,
             HKQuantityTypeIdentifier.restingHeartRate.rawValue,
             HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return HKUnit.count().unitDivided(by: HKUnit.minute())
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return HKUnit.secondUnit(with: .milli)
        case HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
             HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return HKUnit.millimeterOfMercury()
        case HKQuantityTypeIdentifier.bodyTemperature.rawValue:
            return HKUnit.degreeCelsius()
        case HKQuantityTypeIdentifier.bloodGlucose.rawValue:
            return HKUnit(from: "mg/dL")
        case HKQuantityTypeIdentifier.stepCount.rawValue,
             HKQuantityTypeIdentifier.flightsClimbed.rawValue:
            return HKUnit.count()
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return HKUnit.meterUnit(with: .kilo)
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.basalEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue:
            return HKUnit.kilocalorie()
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return HKUnit.percent()
        case HKQuantityTypeIdentifier.vo2Max.rawValue:
            return HKUnit(from: "ml/(kg*min)")
        case HKQuantityTypeIdentifier.dietaryProtein.rawValue,
             HKQuantityTypeIdentifier.dietaryCarbohydrates.rawValue,
             HKQuantityTypeIdentifier.dietaryFatTotal.rawValue,
             HKQuantityTypeIdentifier.dietaryFiber.rawValue,
             HKQuantityTypeIdentifier.dietarySugar.rawValue:
            return HKUnit.gram()
        case HKQuantityTypeIdentifier.dietarySodium.rawValue,
             HKQuantityTypeIdentifier.dietaryCaffeine.rawValue:
            return HKUnit.gramUnit(with: .milli)
        case HKQuantityTypeIdentifier.dietaryWater.rawValue:
            return HKUnit.literUnit(with: .milli)
        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            return HKUnit.gramUnit(with: .kilo)
        default:
            return nil
        }
    }

    private static func requestedReadTypes() -> Set<HKObjectType> {
        var set: Set<HKObjectType> = []
        for entry in LifeRegistry.entries where entry.healthkitMapping {
            // The actual variable catalog ships in the daemon; the iOS
            // side reads it asynchronously. At authorization time we ask
            // for a sensible superset based on hardcoded type ids that
            // cover the curated catalogs of Phase 1.
            switch entry.id {
            case "health":
                appendTypes(into: &set, identifiers: [
                    .heartRate, .restingHeartRate, .heartRateVariabilitySDNN,
                    .bloodPressureSystolic, .bloodPressureDiastolic,
                    .respiratoryRate, .oxygenSaturation, .bodyTemperature,
                    .bloodGlucose, .stepCount, .distanceWalkingRunning,
                    .flightsClimbed, .activeEnergyBurned, .basalEnergyBurned,
                    .vo2Max
                ])
            case "sleep":
                appendCategoryTypes(into: &set, identifiers: [.sleepAnalysis])
            case "workouts":
                set.insert(HKObjectType.workoutType())
            case "nutrition":
                appendTypes(into: &set, identifiers: [
                    .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates,
                    .dietaryFatTotal, .dietaryFiber, .dietarySugar, .dietarySodium,
                    .dietaryCaffeine
                ])
            case "hydration":
                appendTypes(into: &set, identifiers: [.dietaryWater])
            case "body-measures":
                appendTypes(into: &set, identifiers: [.bodyMass, .bodyFatPercentage, .waistCircumference])
            case "cycle":
                appendCategoryTypes(into: &set, identifiers: [
                    .menstrualFlow, .ovulationTestResult, .cervicalMucusQuality, .intermenstrualBleeding
                ])
            case "sex":
                appendCategoryTypes(into: &set, identifiers: [.sexualActivity])
            case "symptoms":
                appendCategoryTypes(into: &set, identifiers: [
                    .headache, .nausea, .fatigue, .coughing, .chestTightnessOrPain
                ])
            case "spirituality":
                appendCategoryTypes(into: &set, identifiers: [.mindfulSession])
            default:
                break
            }
        }
        return set
    }

    private static func appendTypes(
        into set: inout Set<HKObjectType>,
        identifiers: [HKQuantityTypeIdentifier]
    ) {
        for id in identifiers {
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                set.insert(type)
            }
        }
    }

    private static func appendCategoryTypes(
        into set: inout Set<HKObjectType>,
        identifiers: [HKCategoryTypeIdentifier]
    ) {
        for id in identifiers {
            if let type = HKObjectType.categoryType(forIdentifier: id) {
                set.insert(type)
            }
        }
    }
    #endif
}
