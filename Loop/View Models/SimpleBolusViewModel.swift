//
//  SimpleBolusViewModel.swift
//  Loop
//
//  Created by Pete Schwamb on 9/29/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import os.log
import SwiftUI
import LoopCore
import Intents

protocol SimpleBolusViewModelDelegate: class {
    
    ///
    func addGlucose(_ samples: [NewGlucoseSample], completion: @escaping (Error?) -> Void)
    
    ///
    func addCarbEntry(_ carbEntry: NewCarbEntry, completion: @escaping (Error?) -> Void)
    
    ///
    func enactBolus(units: Double, at startDate: Date)

    ///
    func insulinOnBoard(at date: Date, completion: @escaping (_ result: DoseStoreResult<InsulinValue>) -> Void)

    ///
    func computeSimpleBolusRecommendation(carbs: HKQuantity?, glucose: HKQuantity?) -> HKQuantity?

    ///
    var preferredGlucoseUnit: HKUnit { get }
    
    ///
    var maximumBolus: Double { get }

    ///
    var suspendThreshold: HKQuantity { get }
}

class SimpleBolusViewModel: ObservableObject {
    
    @Environment(\.authenticate) var authenticate

    enum Alert: Int {
        case maxBolusExceeded
        case carbEntryPersistenceFailure
        case carbEntrySizeTooLarge
        case manualGlucoseEntryOutOfAcceptableRange
        case manualGlucoseEntryPersistenceFailure
        case infoPopup
    }
    
    @Published var activeAlert: Alert?
    
    enum Notice: Int {
        case glucoseBelowSuspendThreshold
    }

    @Published var activeNotice: Notice?

    var isNoticeVisible: Bool { return activeNotice != nil }    

    @Published var recommendedBolus: String = "0"
    
    @Published var enteredCarbAmount: String = "" {
        didSet {
            if let enteredCarbs = Self.carbAmountFormatter.number(from: enteredCarbAmount)?.doubleValue, enteredCarbs > 0 {
                carbs = HKQuantity(unit: .gram(), doubleValue: enteredCarbs)
            } else {
                carbs = nil
            }
            updateRecommendation()
        }
    }

    @Published var enteredGlucoseAmount: String = "" {
        didSet {
            if let enteredGlucose = glucoseAmountFormatter.number(from: enteredGlucoseAmount)?.doubleValue {
                glucose = HKQuantity(unit: delegate.preferredGlucoseUnit, doubleValue: enteredGlucose)
                if let glucose = glucose, glucose < suspendThreshold {
                    activeNotice = .glucoseBelowSuspendThreshold
                } else {
                    activeNotice = nil
                }
            } else {
                glucose = nil
            }
            updateRecommendation()
        }
    }

    @Published var enteredBolusAmount: String {
        didSet {
            if let enteredBolusAmount = Self.doseAmountFormatter.number(from: enteredBolusAmount)?.doubleValue, enteredBolusAmount > 0 {
                bolus = HKQuantity(unit: .internationalUnit(), doubleValue: enteredBolusAmount)
            } else {
                bolus = nil
            }
        }
    }
    
    private var carbs: HKQuantity? = nil
    private var glucose: HKQuantity? = nil
    private var bolus: HKQuantity? = nil
    
    var glucoseUnit: HKUnit { return delegate.preferredGlucoseUnit }
    
    var suspendThreshold: HKQuantity { return delegate.suspendThreshold }

    private var recommendation: Double? = nil {
        didSet {
            if let recommendation = recommendation, let recommendationString = Self.doseAmountFormatter.string(from: recommendation) {
                recommendedBolus = recommendationString
                enteredBolusAmount = recommendationString
            } else {
                recommendedBolus = NSLocalizedString("-", comment: "String denoting lack of a recommended bolus amount in the simple bolus calculator")
                enteredBolusAmount = Self.doseAmountFormatter.string(from: 0.0)!
            }
        }
    }

    private static let doseAmountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()
    
    private static let carbAmountFormatter: NumberFormatter = {
        let quantityFormatter = QuantityFormatter()
        quantityFormatter.setPreferredNumberFormatter(for: .gram())
        return quantityFormatter.numberFormatter
    }()

    enum ActionButtonAction {
        case saveWithoutBolusing
        case saveAndDeliver
        case enterBolus
        case deliver
    }
    
    var hasDataToSave: Bool {
        return glucose != nil || carbs != nil
    }
    
    var hasBolusEntryReadyToDeliver: Bool {
        return bolus != nil
    }
    
    var actionButtonAction: ActionButtonAction {
        switch (hasDataToSave, hasBolusEntryReadyToDeliver) {
        case (true, true): return .saveAndDeliver
        case (true, false): return .saveWithoutBolusing
        case (false, true): return .deliver
        case (false, false): return .enterBolus
        }
    }
    
    var carbPlaceholder: String {
        Self.carbAmountFormatter.string(from: 0.0)!
    }

    private let glucoseAmountFormatter: NumberFormatter
    private let delegate: SimpleBolusViewModelDelegate
    private let log = OSLog(category: "SimpleBolusViewModel")
    
    private lazy var bolusVolumeFormatter = QuantityFormatter(for: .internationalUnit())

    var maximumBolusAmountString: String? {
        return bolusVolumeFormatter.numberFormatter.string(from: delegate.maximumBolus) ?? String(delegate.maximumBolus)
    }

    init(delegate: SimpleBolusViewModelDelegate) {
        self.delegate = delegate
        let glucoseQuantityFormatter = QuantityFormatter()
        glucoseQuantityFormatter.setPreferredNumberFormatter(for: delegate.preferredGlucoseUnit)
        glucoseAmountFormatter = glucoseQuantityFormatter.numberFormatter
        enteredBolusAmount = Self.doseAmountFormatter.string(from: 0.0)!
        updateRecommendation()
    }
    
    func updateRecommendation() {
        if carbs != nil || glucose != nil {
            recommendation = delegate.computeSimpleBolusRecommendation(carbs: carbs, glucose: glucose)?.doubleValue(for: .internationalUnit())
        } else {
            recommendation = nil
        }
    }
    
    func saveAndDeliver(onSuccess didSave: @escaping () -> Void) {
        if let bolus = bolus {
            guard bolus.doubleValue(for: .internationalUnit()) <= delegate.maximumBolus else {
                presentAlert(.maxBolusExceeded)
                return
            }
        }

        if let glucose = glucose {
            guard LoopConstants.validManualGlucoseEntryRange.contains(glucose) else {
                presentAlert(.manualGlucoseEntryOutOfAcceptableRange)
                return
            }
        }
        
        if let carbs = carbs {
            guard carbs <= LoopConstants.maxCarbEntryQuantity else {
                presentAlert(.carbEntrySizeTooLarge)
                return
            }
        }
        
        let saveDate = Date()

        // Authenticate the bolus before saving anything
        func authenticateIfNeeded(_ completion: @escaping () -> Void) {
            if let bolus = bolus, bolus.doubleValue(for: .internationalUnit()) > 0 {
                let message = String(format: NSLocalizedString("Authenticate to Bolus %@ Units", comment: "The message displayed during a device authentication prompt for bolus specification"), enteredBolusAmount)
                authenticate(message) {
                    switch $0 {
                    case .success:
                        completion()
                    case .failure:
                        break
                    }
                }
            } else {
                completion()
            }
        }
        
        func saveManualGlucose(_ completion: @escaping () -> Void) {
            if let glucose = glucose {
                let manualGlucoseSample = NewGlucoseSample(date: saveDate, quantity: glucose, isDisplayOnly: false, wasUserEntered: true, syncIdentifier: UUID().uuidString)
                delegate.addGlucose([manualGlucoseSample]) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.presentAlert(.manualGlucoseEntryPersistenceFailure)
                            self.log.error("Failed to add manual glucose entry: %{public}@", String(describing: error))
                        } else {
                            completion()
                        }
                    }
                }
            } else {
                completion()
            }
        }
        
        func saveCarbs(_ completion: @escaping () -> Void) {
            if let carbs = carbs {
                
                let interaction = INInteraction(intent: NewCarbEntryIntent(), response: nil)
                interaction.donate { [weak self] (error) in
                    if let error = error {
                        self?.log.error("Failed to donate intent: %{public}@", String(describing: error))
                    }
                }

                let carbEntry = NewCarbEntry(date: saveDate, quantity: carbs, startDate: saveDate, foodType: nil, absorptionTime: nil)
                delegate.addCarbEntry(carbEntry) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.presentAlert(.carbEntryPersistenceFailure)
                            self.log.error("Failed to add carb entry: %{public}@", String(describing: error))
                        } else {
                            completion()
                        }
                    }
                }
            } else {
                completion()
            }
        }
        
        func enactBolus() {
            if let bolusVolume = bolus?.doubleValue(for: .internationalUnit()), bolusVolume > 0 {
                delegate.enactBolus(units: bolusVolume, at: saveDate)
            }
            didSave()
        }
        
        authenticateIfNeeded {
            saveManualGlucose {
                saveCarbs {
                    enactBolus()
                }
            }
        }
    }
    
    private func presentAlert(_ alert: Alert) {
        dispatchPrecondition(condition: .onQueue(.main))

        // As of iOS 13.6 / Xcode 11.6, swapping out an alert while one is active crashes SwiftUI.
        guard activeAlert == nil else {
            return
        }

        activeAlert = alert
    }
    
    func restoreUserActivityState(_ activity: NSUserActivity) {
        if let entry = activity.newCarbEntry {
            carbs = entry.quantity
        }
    }
}

extension SimpleBolusViewModel.Alert: Identifiable {
    var id: Self { self }
}
