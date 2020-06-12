//
//  DosingDecisionStore+SimulatedCoreData.swift
//  Loop
//
//  Created by Darin Krauss on 6/5/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

// MARK: - Simulated Core Data

extension DosingDecisionStore {
    private var historicalEndDate: Date { Date(timeIntervalSinceNow: -.hours(24)) }

    private var simulatedStartDateInterval: TimeInterval { .minutes(5) }
    private var simulatedLimit: Int { 10000 }

    public func generateSimulatedHistoricalDosingDecisionObjects(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: expireDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var simulated = [StoredDosingDecision]()

        while startDate < endDate {
            simulated.append(StoredDosingDecision.simulated(date: startDate))

            if simulated.count >= simulatedLimit {
                if let error = addSimulatedHistoricalDosingDecisionObjects(dosingDecisions: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            startDate = startDate.addingTimeInterval(simulatedStartDateInterval)
        }

        completion(addSimulatedHistoricalDosingDecisionObjects(dosingDecisions: simulated))
    }

    private func addSimulatedHistoricalDosingDecisionObjects(dosingDecisions: [StoredDosingDecision]) -> Error? {
        var addError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        addStoredDosingDecisions(dosingDecisions: dosingDecisions) { error in
            addError = error
            semaphore.signal()
        }
        semaphore.wait()
        return addError
    }

    public func purgeHistoricalDosingDecisionObjects(completion: @escaping (Error?) -> Void) {
        purgeDosingDecisions(before: historicalEndDate, completion: completion)
    }
}

fileprivate extension StoredDosingDecision {
    static func simulated(date: Date) -> StoredDosingDecision {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let insulinOnBoard = InsulinValue(startDate: date, value: 1.5)
        let carbsOnBoard = CarbValue(startDate: date,
                                     endDate: date.addingTimeInterval(.minutes(5)),
                                     quantity: HKQuantity(unit: .gram(), doubleValue: 45.5))
        let scheduleOverride = TemporaryScheduleOverride(context: .preMeal,
                                                         settings: TemporaryScheduleOverrideSettings(unit: .milligramsPerDeciliter,
                                                                                                     targetRange: DoubleRange(minValue: 80.0,
                                                                                                                              maxValue: 90.0),
                                                                                                     insulinNeedsScaleFactor: 1.5),
                                                         startDate: date.addingTimeInterval(-.hours(1.5)),
                                                         duration: .finite(.hours(1)),
                                                         enactTrigger: .local,
                                                         syncIdentifier: UUID())
        let glucoseTargetRangeSchedule = GlucoseRangeSchedule(rangeSchedule: DailyQuantitySchedule(unit: .milligramsPerDeciliter,
                                                                                                   dailyItems: [RepeatingScheduleValue(startTime: .hours(0), value: DoubleRange(minValue: 100.0, maxValue: 110.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(8), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(10), value: DoubleRange(minValue: 90.0, maxValue: 100.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(12), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(14), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(16), value: DoubleRange(minValue: 100.0, maxValue: 110.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(18), value: DoubleRange(minValue: 90.0, maxValue: 100.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(21), value: DoubleRange(minValue: 110.0, maxValue: 120.0))],
                                                                                                   timeZone: timeZone)!)
        let glucoseTargetRangeScheduleApplyingOverrideIfActive = GlucoseRangeSchedule(rangeSchedule: DailyQuantitySchedule(unit: .milligramsPerDeciliter,
                                                                                                                           dailyItems: [RepeatingScheduleValue(startTime: .hours(0), value: DoubleRange(minValue: 100.0, maxValue: 110.0)),
                                                                                                                                        RepeatingScheduleValue(startTime: .hours(8), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                                        RepeatingScheduleValue(startTime: .hours(10), value: DoubleRange(minValue: 90.0, maxValue: 100.0)),
                                                                                                                                        RepeatingScheduleValue(startTime: .hours(12), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                                        RepeatingScheduleValue(startTime: .hours(14), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                                        RepeatingScheduleValue(startTime: .hours(16), value: DoubleRange(minValue: 100.0, maxValue: 110.0)),
                                                                                                                                        RepeatingScheduleValue(startTime: .hours(18), value: DoubleRange(minValue: 90.0, maxValue: 100.0)),
                                                                                                                                        RepeatingScheduleValue(startTime: .hours(21), value: DoubleRange(minValue: 110.0, maxValue: 120.0))],
                                                                                                                           timeZone: timeZone)!)
        var predictedGlucose = [PredictedGlucoseValue]()
        for minutes in stride(from: 0.0, to: 360.0, by: 5.0) {
            predictedGlucose.append(PredictedGlucoseValue(startDate: date.addingTimeInterval(.minutes(minutes)),
                                                          quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 125 + minutes / 10)))
        }
        var predictedGlucoseIncludingPendingInsulin = [PredictedGlucoseValue]()
        for minutes in stride(from: 0.0, to: 360.0, by: 5.0) {
            predictedGlucoseIncludingPendingInsulin.append(PredictedGlucoseValue(startDate: date.addingTimeInterval(.minutes(minutes)),
                                                                                 quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 95 + minutes / 10)))
        }
        let lastReservoirValue = StoredDosingDecision.LastReservoirValue(startDate: date.addingTimeInterval(-.minutes(1)),
                                                                         unitVolume: 113.3)
        let recommendedTempBasal = StoredDosingDecision.TempBasalRecommendationWithDate(recommendation: TempBasalRecommendation(unitsPerHour: 0.75,
                                                                                                                                duration: .minutes(30)),
                                                                                        date: date.addingTimeInterval(-.minutes(1)))
        let recommendedBolus = StoredDosingDecision.BolusRecommendationWithDate(recommendation: BolusRecommendation(amount: 0.2,
                                                                                                                    pendingInsulin: 0.75,
                                                                                                                    notice: .predictedGlucoseBelowTarget(minGlucose: PredictedGlucoseValue(startDate: date.addingTimeInterval(.minutes(30)),
                                                                                                                                                                                           quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 95.0)))),
                                                                                date: date.addingTimeInterval(-.minutes(1)))
        let pumpManagerStatus = PumpManagerStatus(timeZone: timeZone,
                                                  device: HKDevice(name: "Device Name",
                                                                   manufacturer: "Device Manufacturer",
                                                                   model: "Device Model",
                                                                   hardwareVersion: "Device Hardware Version",
                                                                   firmwareVersion: "Device Firmware Version",
                                                                   softwareVersion: "Device Software Version",
                                                                   localIdentifier: "Device Local Identifier",
                                                                   udiDeviceIdentifier: "Device UDI Device Identifier"),
                                                  pumpBatteryChargeRemaining: 3.5,
                                                  basalDeliveryState: .initiatingTempBasal,
                                                  bolusState: .none)
        let deviceSettings = StoredDosingDecision.DeviceSettings(name: "Device Name",
                                                                 systemName: "Device System Name",
                                                                 systemVersion: "Device System Version",
                                                                 model: "Device Model",
                                                                 modelIdentifier: "Device Model Identifier",
                                                                 batteryLevel: 0.5,
                                                                 batteryState: .charging)

        return StoredDosingDecision(date: date,
                                    insulinOnBoard: insulinOnBoard,
                                    carbsOnBoard: carbsOnBoard,
                                    scheduleOverride: scheduleOverride,
                                    glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
                                    glucoseTargetRangeScheduleApplyingOverrideIfActive: glucoseTargetRangeScheduleApplyingOverrideIfActive,
                                    predictedGlucose: predictedGlucose,
                                    predictedGlucoseIncludingPendingInsulin: predictedGlucoseIncludingPendingInsulin,
                                    lastReservoirValue: lastReservoirValue,
                                    recommendedTempBasal: recommendedTempBasal,
                                    recommendedBolus: recommendedBolus,
                                    pumpManagerStatus: pumpManagerStatus,
                                    notificationSettings: historicalNotificationSettings,
                                    deviceSettings: deviceSettings,
                                    errors: nil,
                                    syncIdentifier: UUID().uuidString)
    }
}

fileprivate let historicalNotificationSettingsBase64 = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V" +
    "5ZWRBcmNoaXZlctEICVRyb290gAGjCwwgVSRudWxs3g0ODxAREhMUFRYXGBkaGxsbGxscHBwdHhsfHBtcYmFkZ2VTZXR0aW5nXxATYXV0aG9yaXphdGlvblN0YXR" +
    "1c1xzb3VuZFNldHRpbmdfEBlub3RpZmljYXRpb25DZW50ZXJTZXR0aW5nXxAUY3JpdGljYWxBbGVydFNldHRpbmdfEBNzaG93UHJldmlld3NTZXR0aW5nXxAPZ3J" +
    "vdXBpbmdTZXR0aW5nXmNhclBsYXlTZXR0aW5nXxAfcHJvdmlkZXNBcHBOb3RpZmljYXRpb25TZXR0aW5nc1YkY2xhc3NfEBFsb2NrU2NyZWVuU2V0dGluZ1phbGV" +
    "ydFN0eWxlXxATYW5ub3VuY2VtZW50U2V0dGluZ1xhbGVydFNldHRpbmcQAhAACIACEAHSISIjJFokY2xhc3NuYW1lWCRjbGFzc2VzXxAWVU5Ob3RpZmljYXRpb25" +
    "TZXR0aW5nc6IlJl8QFlVOTm90aWZpY2F0aW9uU2V0dGluZ3NYTlNPYmplY3QACAARABoAJAApADIANwBJAEwAUQBTAFcAXQB6AIcAnQCqAMYA3QDzAQUBFAE2AT0" +
"BUQFcAXIBfwGBAYMBhAGGAYgBjQGYAaEBugG9AdYAAAAAAAACAQAAAAAAAAAnAAAAAAAAAAAAAAAAAAAB3w=="
fileprivate let historicalNotificationSettingsData = Data(base64Encoded: historicalNotificationSettingsBase64)!
fileprivate let historicalNotificationSettings = try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(historicalNotificationSettingsData) as! UNNotificationSettings