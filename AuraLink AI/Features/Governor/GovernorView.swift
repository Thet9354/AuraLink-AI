//
//  GovernorView.swift
//  AuraLink AI
//
//  Shows the live resolved capability and lets the demo force thermal states (the OS won't let you
//  set them), so the A14→A17 quality-ladder adaptation can be shown adapting in real time.
//

import SwiftUI

struct GovernorView: View {
    @Bindable var controller: GovernorController

    var body: some View {
        NavigationStack {
            List {
                Section("Effective capability") {
                    row("Tier", controller.resolved.tier.badge)
                    row("Model", controller.resolved.tier.modelVariant.rawValue.capitalized)
                    row("Pose rate", "\(controller.resolved.tier.fpsCaps.poseSampleHz) Hz")
                    row("Inference rate", "\(controller.resolved.tier.fpsCaps.signInferenceHz) Hz")
                    row("Reason", controller.resolved.reason.rawValue, tint: reasonColor)
                    if controller.resolved.captionsOnly {
                        Label("Captions-only (critical thermal)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("Features enabled") {
                    featureRow("Predictive pre-emption", controller.resolved.tier.features.predictivePreemption)
                    featureRow("LiDAR sound depth", controller.resolved.tier.features.lidarSoundDepth)
                    featureRow("Full haptic prosody", controller.resolved.tier.features.fullHapticProsody)
                }

                Section("Simulate thermal state") {
                    Picker("Thermal", selection: thermalBinding) {
                        Text("Auto (sensor)").tag(ThermalLevel?.none)
                        ForEach(ThermalLevel.allCases, id: \.self) { level in
                            Text(label(for: level)).tag(ThermalLevel?.some(level))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Text("Force a thermal state to watch the tier drop and pose rate fall, then recover.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Governor")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var thermalBinding: Binding<ThermalLevel?> {
        Binding(get: { controller.debugThermalOverride },
                set: { controller.debugThermalOverride = $0 })
    }

    private var reasonColor: Color {
        switch controller.resolved.reason {
        case .nominal: .green
        case .thermal: .red
        case .lowPower: .orange
        case .memory: .yellow
        }
    }

    private func row(_ title: String, _ value: String, tint: Color = .secondary) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(tint).monospacedDigit()
        }
    }

    private func featureRow(_ title: String, _ enabled: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(enabled ? .green : .secondary)
        }
    }

    private func label(for level: ThermalLevel) -> String {
        switch level {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }
}
