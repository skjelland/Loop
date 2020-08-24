//
//  ServicesViewModel.swift
//  Loop
//
//  Created by Rick Pasetto on 8/14/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI

public class ServicesViewModel: ObservableObject {
    typealias ServicesSettingsViewControllerFactory = (_ index: Int) -> UIViewController & ServiceSettingsNotifying & CompletionNotifying
    
    
    @Published var showServices: Bool
    @Published var availableServices: [AvailableService]
    @Published var activeServices: [Service]
    let addService: ((_ identifier: String) -> Void)?
    let gotoService: ((_ identifier: String) -> Void)?
    let servicesSettingsViewControllerFactory: ServicesSettingsViewControllerFactory?

    var inactiveServices: [AvailableService] {
        return availableServices.filter { availableService in
            !activeServices.contains { $0.serviceIdentifier == availableService.identifier }
        }
    }
    
    init(showServices: Bool,
         availableServices: [AvailableService],
         activeServices: [Service],
         addService: ((_ identifier: String) -> Void)? = nil,
         gotoService: ((_ identifier: String) -> Void)? = nil,
         serviceSettingsViewControllerFactory: ServicesSettingsViewControllerFactory? = nil) {
        self.showServices = showServices
        self.activeServices = activeServices
        self.availableServices = availableServices
        self.addService = addService
        self.gotoService = gotoService
        self.servicesSettingsViewControllerFactory = serviceSettingsViewControllerFactory
    }
    
    func didTapService(_ index: Int) {
        gotoService?(activeServices[index].serviceIdentifier)
    }
    
    func didTapAddService(_ availableService: AvailableService) {
        addService?(availableService.identifier)
    }
}
