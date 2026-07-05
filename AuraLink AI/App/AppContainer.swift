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
    let enrollViewModel: EnrollViewModel

    init() {
        let rung = CapabilityProbe.detectRung()
        let tier = CapabilityTier.baseline(for: rung)
        self.tier = tier

        // Shared capture + vision front-end, feeding every consumer (translation, enrollment,
        // preview, diagnostics). The actors coordinate on the single AVCaptureSession; only one
        // capture consumer runs at a time (screens are modal and stop capture on dismiss).
        let capture = CaptureActor()   // defaults to the front camera (self-signing)
        let audio = AudioActor()
        let vision = VisionActor()

        let lexicon = LexiconLoader.loadBundled()
        let store = ExemplarFileStore()

        // Phase 3: the real DTW translation graph behind the CaptionProducing seam — no UI change.
        let pipeline = SignTranslationPipeline(capture: capture,
                                               vision: vision,
                                               lexicon: lexicon,
                                               store: store,
                                               tier: tier)
        self.translateViewModel = TranslateViewModel(pipeline: pipeline, tier: tier)

        self.captureDiagnosticsViewModel = CaptureDiagnosticsViewModel(capture: capture,
                                                                       audio: audio,
                                                                       vision: vision)
        self.posePreviewViewModel = PosePreviewViewModel(capture: capture, vision: vision)

        let recorder = EnrollmentRecorder(capture: capture, vision: vision, store: store)
        self.enrollViewModel = EnrollViewModel(lexicon: lexicon, recorder: recorder, store: store)
    }
}
