//
//  GovernorController.swift
//  AuraLink AI
//
//  Bridges live OS signals (thermal state, Low Power Mode, memory warnings) into the pure
//  `ThermalGovernor`, publishes the resolved capability for the UI badge, and pushes the effective
//  pose-processing rate to the vision front-end. A 1 Hz tick re-resolves so hysteretic upgrades
//  eventually apply and a memory warning decays after a cool-off.
//
//  A `debugThermalOverride` lets the demo force thermal states on device (the OS won't let you set
//  them) — so the quality-ladder adaptation can be shown live.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class GovernorController {

    private(set) var resolved: ResolvedCapability

    /// Demo override for the current thermal level; nil = use the real sensor.
    var debugThermalOverride: ThermalLevel? {
        didSet { recompute() }
    }

    private let baseRung: DeviceRung
    private var governor: ThermalGovernor
    private var memoryWarning = false
    private var memoryWarnedAt: Double = 0
    private let memoryCoolOffSeconds: Double = 30

    private var tick: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// Called whenever the effective tier changes (e.g. to retune the vision front-end).
    var onChange: (@MainActor (ResolvedCapability) -> Void)?

    init(baseRung: DeviceRung) {
        self.baseRung = baseRung
        self.governor = ThermalGovernor(baseRung: baseRung)
        self.resolved = ResolvedCapability(tier: .baseline(for: baseRung),
                                           captionsOnly: false, reason: .nominal)
    }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        })
        observers.append(center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        })
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteMemoryWarning() }
        })

        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.recompute()
            }
        }
        recompute()
    }

    func stop() {
        tick?.cancel()
        tick = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func noteMemoryWarning() {
        memoryWarning = true
        memoryWarnedAt = now
        recompute()
    }

    private func recompute() {
        if memoryWarning, now - memoryWarnedAt > memoryCoolOffSeconds {
            memoryWarning = false
        }

        let thermal = debugThermalOverride ?? ThermalLevel(ProcessInfo.processInfo.thermalState)
        let inputs = GovernorInputs(baseRung: baseRung,
                                    thermal: thermal,
                                    lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                    memoryWarning: memoryWarning)
        let newResolved = governor.resolve(inputs, now: now)
        guard newResolved != resolved else { return }
        resolved = newResolved
        onChange?(newResolved)
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }
}

extension ThermalLevel {
    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious   // unknown → conservative
        }
    }
}
