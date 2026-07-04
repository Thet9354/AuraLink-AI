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
    let posePreviewViewModel: PosePreviewViewModel

    init() {
        let rung = CapabilityProbe.detectRung()
        let tier = CapabilityTier.baseline(for: rung)
        self.tier = tier

        // Phase 0: mock pipeline behind the CaptionProducing seam. Phase 3 swaps in the real
        // capture → vision → fusion → inference graph without touching the view/view-model.
        let pipeline = MockCaptionPipeline(tier: tier)
        self.translateViewModel = TranslateViewModel(pipeline: pipeline, tier: tier)

        // Phase 1+2: capture layer feeding the vision front-end. Verified via the diagnostics
        // self-test and the live pose preview until Phase 3 consumes features for translation.
        let capture = CaptureActor()   // defaults to the front camera (self-signing)
        let audio = AudioActor()
        let vision = VisionActor()
        self.captureDiagnosticsViewModel = CaptureDiagnosticsViewModel(capture: capture,
                                                                       audio: audio,
                                                                       vision: vision)
        self.posePreviewViewModel = PosePreviewViewModel(capture: capture, vision: vision)
    }
}
