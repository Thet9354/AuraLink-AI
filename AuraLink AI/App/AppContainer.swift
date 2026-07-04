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
    let captureDiagnosticsViewModel: CaptureDiagnosticsViewModel

    init() {
        let rung = CapabilityProbe.detectRung()
        let tier = CapabilityTier.baseline(for: rung)
        self.tier = tier

        // Phase 0: mock pipeline behind the CaptionProducing seam. Phase 3 swaps in the real
        // capture → vision → fusion → inference graph without touching the view/view-model.
        let pipeline = MockCaptionPipeline(tier: tier)
        self.translateViewModel = TranslateViewModel(pipeline: pipeline, tier: tier)

        // Phase 1: real capture layer, exercised via the on-device diagnostics self-test until the
        // Phase 2 vision front-end consumes these frames for translation.
        let capture = CaptureActor()   // defaults to the front camera (self-signing)
        let audio = AudioActor()
        self.captureDiagnosticsViewModel = CaptureDiagnosticsViewModel(capture: capture, audio: audio)
    }
}
