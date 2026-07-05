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
    let listenViewModel: ListenViewModel
    let governor: GovernorController

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
        // Phase 5: exemplars encrypted at rest under a device-only key (biometric-adjacent data).
        let cryptor = (try? KeychainKeyProvider().key()).map(ExemplarCryptor.init(key:))
        let store = ExemplarFileStore(cryptor: cryptor)

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

        // Phase 4: ambient audio → captions + sound events + haptic prosody.
        let haptics = HapticsActor()
        let listener = AudioListener(haptics: haptics)
        self.listenViewModel = ListenViewModel(listener: listener)

        // Phase 5: capability governor. Live thermal/battery/memory signals resolve to an effective
        // tier that drives the HUD badge and retunes the vision front-end's processing rate.
        let governor = GovernorController(baseRung: rung)
        self.governor = governor
        governor.onChange = { resolved in
            Task { await vision.setTargetHz(resolved.tier.fpsCaps.poseSampleHz) }
        }
        governor.start()
    }
}
