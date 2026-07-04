# AuraLink AI — Implementation Roadmap

Six phases from blank project to App Store-ready. Each phase ends with a **hard verification
gate** — a numeric threshold or an automated test, not a vibe. You do not proceed until the gate
is green. Weeks are aggressive targets; the gates are the real deliverables.

Locked design decisions (see also project memory):
- **Device baseline:** support A14 → A17 via a quality ladder (`CapabilityTier`); dual-ceiling gates.
- **Sign model:** pose-only + rule/LM gloss (DTW template match → tiny LM → grammar rules), NOT a trained transformer. Seam: the `SignRecognizing` protocol, so DTW can later be swapped for a learned encoder.
- **Vocabulary:** ASL, ~200-sign "Everyday Needs" v1. Confidence-gated: out-of-vocab → `.unknown`, never fabricated.

---

## Phase 0 — Concurrency skeleton  ✅ DONE
- **Built:** actor-graph seam (`CaptionProducing`), `LatestSlot<T>`, `FrameToken` plan,
  `CapabilityProbe` + `CapabilityTier`, `Signposts`, `MockCaptionPipeline`, `TranslateViewModel`
  + `TranslateScreen`, `AppContainer`. Confidence-aware rendering already stubbed.
- **Gate (met):** Swift 6 strict-concurrency build with **zero warnings**; `LatestSlotTests`
  green (latest-wins, bounded memory, parked-consumer resume, flood-without-growth).
- **Remaining before Phase 1:** Thread Sanitizer clean on a 60 s mock soak (device task).

## Phase 1 — Capture layer  ✅ DONE (device-measured gates pending)
- **Built:** `CaptureActor` (`AVCaptureSession`, video data output 60fps + `alwaysDiscardsLateVideoFrames`,
  custom `DispatchQueueExecutor` serial executor, `.bufferingNewest(1)` frame stream), real
  `FrameToken`, `VideoOutputDelegate` (nonisolated, `autoreleasepool` per callback, drop counting),
  `AudioActor` + lock-free SPSC `AudioRingBuffer`, `CaptureAuthorization` (camera + mic),
  `FrameProducing` seam, `LatestSlot` cancellation support. Info.plist usage strings + portrait lock.
  On-device `CaptureDiagnostics` self-test (fps / delivered / dropped / audio samples).
- **APIs:** AVFoundation, CoreMedia, AVAudioEngine, Synchronization (`Atomic`).
- **Gate — code (met):** zero-warning Swift 6 build; `AudioRingBufferTests` green (round-trip,
  wrap-around, drop-when-full, partial read, total-written); `LatestSlot` cancellation test green.
- **Gate — device (pending, run via the Diagnostics screen + Instruments):** 60fps sustained;
  drop-count rises under artificial consumer stall; Allocations flat over 5 min.
- **Deferred to Phase 2:** `CVPixelBufferPool` for intermediate render targets (only needed once
  the vision stage produces derived buffers; the camera already vends pooled buffers).

## Phase 2 — Pose front-end (LONG POLE)
- **Build:** `VisionActor` — `VNDetectHumanHandPoseRequest` + body pose; Metal preprocessing
  (crop/resize/normalize into pooled tensors); pose normalization (wrist origin, shoulder-width
  scale, canonical rotation → distance/position invariance); `FeatureVector`; rolling pose ring.
- **APIs:** Vision, Metal/MPS.
- **Gate:** joint RMSE vs golden fixtures within tolerance across a lighting/motion/occlusion
  matrix; confidence degrades **monotonically and honestly** (no silent wrong poses);
  capture→feature ≤ 25 ms (A17) / ≤ 40 ms (A14); main-thread CPU < 10%.

## Phase 3 — Segmentation + DTW/LM gloss
- **Build:** motion-energy segmentation (`FusionActor`); `SignLexicon` + exemplars; DTW matcher
  (Accelerate-vectorized, coarse-feature prune first); tiny on-device LM disambiguation;
  `GlossGrammar` rules (gloss → fluent English); `InferenceCoordinator` admission control;
  confidence gating → `.unknown` for out-of-vocab.
- **APIs:** Accelerate, Core ML (LM), Metal.
- **Gate:** top-1 accuracy on labeled segment fixtures; **reliability diagram** (calibration)
  proving confidence bands are meaningful; glass→caption ≤ 220 ms (A17) / ≤ 350 ms (A14) p95;
  OOV → `.unknown`; back-pressure test (throttle ANE → frames dropped, latency bounded).

## Phase 4 — Audio pipeline + cross-modal haptics
- **Build:** `AudioActor` DSP (vDSP VAD/mel/f0); on-device streaming ASR (preserves zero-network
  invariant); sound-event classifier + localization; `ProsodyEnvelope` → `HapticsActor` (Core
  Haptics); directional cues (+LiDAR depth on Pro).
- **APIs:** AVAudioEngine, Accelerate/vDSP, Core ML, Core Haptics.
- **Gate:** WER below threshold on a noisy fixture set; sound-onset→haptic ≤ 100 ms; prosody→haptic
  mapping unit test (monotonic pitch→intensity).

## Phase 5 — Personalization + governor
- **Build:** enrollment (20 phrases → user's own DTW exemplars, few-shot); Secure-Enclave-encrypted
  lexicon delta; full `ThermalGovernor` (device + thermal + battery + memory → effective tier,
  hysteretic); precise `CapabilityProbe` lookup table + ANE micro-benchmark fallback; predictive
  gesture head (a17plus only).
- **APIs:** CryptoKit + Secure Enclave, `ProcessInfo.thermalState`, low-power mode, Core ML.
- **Gate:** per-user accuracy lift on held-out signs vs baseline; governor drop-under-heat holds
  fps (no hitch); adapter ciphertext-at-rest assertion.

## Phase 6 — Hardening + submission
- **Build:** full VoiceOver/Dynamic Type/low-vision HUD; onboarding sensory tutorial; lifecycle /
  interruption / route-change recovery; `PrivacyInfo.xcprivacy` ("Data Not Collected"); App Store kit.
- **APIs:** Accessibility, StoreKit/App Store Connect.
- **Gate:** 30-min soak (flat Allocations, no crash, thermal ≤ `.serious`, battery Wh/hr documented);
  accessibility audit zero-critical; **network egress = 0 proven with the Network Instrument**
  (the marquee claim); cold-launch → first caption < 2 s (A17) / < 3 s (A14).

> Note: no Apple Developer membership until **August 2026**. Phase 6 prepares everything for a
> mechanical launch with no paid-account dependency until then (mirrors the prior portfolio project).
