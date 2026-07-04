//
//  AppContainer.swift
//  AuraLink AI
//
//  The sole composition root. Detects device capability, builds the pipeline, and wires the
//  view model. Nothing else in the app constructs services — dependencies flow from here.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppContainer {

    let tier: CapabilityTier
    let translateViewModel: TranslateViewModel

    init() {
        let rung = CapabilityProbe.detectRung()
        let tier = CapabilityTier.baseline(for: rung)
        self.tier = tier

        // Phase 0: mock pipeline behind the CaptionProducing seam. Phase 3 swaps in the real
        // capture → vision → fusion → inference graph without touching the view/view-model.
        let pipeline = MockCaptionPipeline(tier: tier)
        self.translateViewModel = TranslateViewModel(pipeline: pipeline, tier: tier)
    }
}
