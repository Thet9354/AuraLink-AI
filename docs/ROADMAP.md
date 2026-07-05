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

## Phase 2 — Pose front-end (LONG POLE)  ✅ DONE (device-measured gates pending)
- **Built:** `VisionActor` — hand pose (max 2) + duty-cycled body pose (every 3rd frame) on its own
  `DispatchQueueExecutor` (the synchronous `perform` must not block the cooperative pool); maps
  Vision results into framework-free `PoseObservation`s; lifetime attach-once frame loop
  (`AsyncStream` is single-iteration — cancelling an iterator kills the stream). `PoseNormalizer`
  (wrist origin → palm-axis rotation → palm-length scale; similarity-transform invariance
  unit-proven). `FeatureExtractor` — fixed 178-dim v1 layout: handshape positions + shape
  velocities per hand, signing-space wrist coords (body-relative), raw wrist velocity (movement
  path), validity flags; velocity state resets on hand reappearance (no spikes). Generic
  `RingBuffer` (~3 s feature history for Phase 3 segmentation). Live pose-preview screen
  (skeleton overlay + latency HUD) and capture→pose latency percentiles in the diagnostics
  self-test (`captureToPose` signpost).
- **APIs:** Vision, simd, CoreMedia, os.
- **Architecture note:** the Metal-preprocessing/TensorPool stage from the original sketch is NOT
  built — with pose-only + DTW there is no image-tensor model; Vision consumes camera pixel
  buffers directly. Pooled tensors return only if a learned encoder replaces DTW (the
  `SignRecognizing` seam).
- **Gate — code (met):** zero-warning Swift 6 build; 32 unit tests green, including the core
  invariance property (translation / scale / rotation / combined), canonical-frame assertions,
  honest-failure cases (missing wrist, degenerate palm → `nil`, never garbage), layout freeze,
  velocity semantics, signing-space math.
- **Gate — device (pending):** capture→pose ≤ 25 ms p95 (A17) / ≤ 40 ms (A14) via the Diagnostics
  self-test; smooth skeleton tracking in the pose preview; main-thread CPU < 10% (Instruments).
- **Deferred:** golden-fixture joint-RMSE regression (needs recorded clips — the enrollment
  tooling in Phase 5 produces these as serialized `PoseObservation` arrays).

## Phase 3 — Segmentation + DTW/LM gloss  ✅ DONE (device accuracy pending)
- **Built:** motion-energy `GestureSegmenter` (hysteresis open/close, pre-roll onset, twitch
  reject, max-length force-close); `SignLexicon` + 218-sign v1 ASL catalog (`lexicon_v1.json`);
  `SignExemplar` + layout-versioned `ExemplarFileStore` (one file per exemplar, complete file
  protection); two-stage `SignMatcher` (duration + mean-frame prune → banded `DTW`; absolute
  unknown gate + softmax relative confidence; authored-bigram nudge as the LM stand-in);
  `GlossGrammar` (ME→"I", casing, question "?", honest "…" gaps); `SignTranslationPipeline`
  (the real graph behind `CaptionProducing`, rolling sentence window, `segmentToCaption`
  signpost); `EnrollmentRecorder` + Enroll UI (records the user's own exemplars — the only way
  real DTW data enters, and the Phase 5 personalization foundation); feature multicast on
  `VisionActor` (bounded per-consumer streams).
- **APIs:** Foundation, CoreMedia, simd, os. (No Accelerate/Core ML yet — DTW at ~92-dim slice ×
  ≤64 frames × pruned-to-25 candidates is sub-millisecond in scalar Swift; vectorize only if a
  profile says so.)
- **Design decision:** no separate `InferenceCoordinator` — DTW fires only on segment CLOSE
  (≤ ~2/s by human cadence) and is cheap, so the serial pipeline actor IS the admission gate; a
  coordinator would be machinery guarding a queue that never forms. Revisit with a learned encoder.
- **Gate — code (met):** zero-warning Swift 6 build; 61 unit tests green — segmentation
  (hysteresis/twitch/force-close), DTW (**zero for identical, invariant to 2× time-warp**,
  monotonic in dissimilarity, validity penalty), matcher (correct sign / honest unknown / bigram
  context flip / probability-shaped confidence), grammar, catalog decode, store round-trip +
  layout-version skip.
- **Gate — device (pending):** enroll a handful of signs, then translate them — top-1 accuracy on
  your own exemplars; glass→caption ≤ 220 ms (A17) via the `segmentToCaption` signpost; OOV signs
  render as "…". Reliability-diagram calibration once enough exemplars exist.

## Phase 4 — Audio pipeline + cross-modal haptics  ✅ DONE (device run pending)
- **Built:** `AudioDSP` (energy dB, ZCR, autocorrelation **f0** via vDSP dot-products);
  `VoiceActivityDetector` (adaptive noise floor, hysteretic on/off); `ProsodyMapper`
  (loudness→intensity, pitch→sharpness, monotonic); `HapticsActor` (Core Haptics — a continuous
  prosody event modulated live via dynamic parameters, transient urgency taps, health-checked +
  rebuild-on-reset); `AudioListener` (own engine + executor; single tap fans out via the audited
  `AudioTapProcessor` to ring/DSP, SoundAnalysis, speech); on-device sound events via SoundAnalysis
  built-in classifier (`SoundEventMapper` curates alerting classes by urgency); **on-device**
  streaming captions via `SFSpeechRecognizer` (`requiresOnDeviceRecognition = true` — refuses
  rather than using the network); Listen UI (captions + event chips + live prosody meter).
- **APIs:** AVAudioEngine, Accelerate/vDSP, SoundAnalysis, Speech, Core Haptics, CoreMedia.
- **Deviations from the sketch (documented, deliberate):**
  - **No mel spectrogram** — captions use Apple's on-device recognizer (raw audio in), not a custom
    ASR head, so mel features aren't needed (same "don't build machinery nothing uses" rule).
  - **Sound localization / LiDAR depth deferred** — `SoundEvent.azimuth`/`depth` are modelled but
    nil in v1; multi-mic beamforming is future work.
- **Gate — code (met):** zero-warning Swift 6 build; 79 unit tests green — pitch recovery on
  synthetic sines, silence/noise → unvoiced, energy tracks amplitude, **prosody monotonicity**
  (the explicit gate), VAD latch/release/debounce, sound-event mapping + urgency bars.
- **Gate — device (pending):** open Listen — captions transcribe speech; an alarm/siren/knock
  raises an event chip; the prosody meter (and Taptic engine) track your voice's loudness/pitch;
  sound-onset→haptic ≤ 100 ms; **zero network egress** while captioning (Network Instrument — the
  marquee check, since on-device ASR is the risk point).

## Phase 5 — Personalization + governor  ✅ DONE (device run pending)
- **Built:** `ThermalGovernor` — pure, time-parameterized state machine: effective rung = min
  across thermal/lowPower/memory ceilings (never above baseline); **hysteresis** (downgrade
  immediately, upgrade only after the improved state holds `upgradeStabilitySeconds`); critical
  thermal → captions-only. `GovernorController` (@MainActor @Observable) wires real
  `ProcessInfo` thermal/power + memory-warning notifications + a 1 Hz tick, drives the live HUD
  badge, and retunes `VisionActor` processing Hz (real, visible frame-skip under heat).
  `GovernorView` with a **thermal-state override** so the adaptation can be demoed live on device.
  Exemplar encryption at rest: `ExemplarCryptor` (AES-GCM) + `KeychainKeyProvider` (256-bit key,
  `WhenUnlockedThisDeviceOnly`); `ExemplarFileStore` writes `.sealed` ciphertext. Precise
  `CapabilityProbe` identifier→rung table (Pro-vs-non-Pro aware) + major-version heuristic + RAM
  fallback.
- **APIs:** CryptoKit, Security (Keychain), `ProcessInfo` thermal/power, UIKit memory-warning.
- **Personalization note:** the DTW library is *already* the user's own recorded exemplars
  (Phase 3 enrollment), so recognition is inherently personalized; Phase 5 secures it and adds the
  governor. **Predictive gesture head deferred** (a17plus nicety; an autoregressive predictor is
  its own project — documented, not built, consistent with the honest-deferral pattern).
- **Gate — code (met):** zero-warning Swift 6 build; 94 unit tests green — governor min-across-
  ceilings + never-above-baseline + downgrade-immediate/upgrade-delayed + fluctuation-resets-timer;
  **exemplar ciphertext-at-rest** (raw disk bytes contain no lex id / JSON) + round-trip + wrong-key
  fails; capability table classifies known identifiers.
- **Gate — device (pending):** open the Governor badge → force Serious/Critical and watch the tier
  drop, pose rate fall, and features disable, then Auto → recover after the hysteresis window;
  confirm no hitch during the transition (Instruments).

## Phase 6 — Hardening + submission  ✅ DONE (device verification + Aug 2026 launch pending)
- **Built:** four-page onboarding (modalities + privacy, primes camera/mic/speech permissions);
  `AppSettings` (haptics toggle, larger captions, onboarding state — the only UserDefaults use,
  CA92.1); Settings screen (with a privacy statement and onboarding replay); Dynamic-Type caption
  fonts + VoiceOver labels/hints/values throughout; consolidated the utility screens behind one
  menu; lifecycle recovery (scene-phase teardown releases camera/ANE on background; `AudioListener`
  handles AVAudioSession interruption + route-change → engine restart); `PrivacyInfo.xcprivacy`
  ("Data Not Collected"); usage strings for camera/mic/speech. Docs: `PRIVACY.md`,
  `docs/APP_STORE_KIT.md`, `docs/LAUNCH_CHECKLIST.md`.
- **APIs:** SwiftUI accessibility, Observation, UIKit lifecycle, XCTest accessibility audit.
- **Gate — code (met):** zero-warning Swift 6 build; 94 unit tests green; **zero networking APIs in
  the target** (grep-verified — the architectural basis of the zero-egress claim); accessibility
  audit UI test on the main + onboarding screens.
- **Gate — device / launch (pending, in `docs/LAUNCH_CHECKLIST.md`):** 30-min soak (flat
  Allocations, no crash, thermal ≤ `.serious`, battery Wh/hr); Accessibility Inspector zero-critical
  + VoiceOver/large-type pass; **network egress = 0 proven with the Network Instrument** (marquee);
  cold-launch → first caption < 2 s (A17) / < 3 s (A14). No Apple Developer membership until
  **August 2026** → everything is prepared for a mechanical launch (mirrors the prior project).

---

**Roadmap complete.** Six phases, blank project → submission-ready: a provably data-race-free,
back-pressured, zero-network multimodal accessibility engine with sign→text, speech→captions,
sound→alerts, and voice→haptics, an adaptive A14→A17 quality ladder, and encrypted personalization.
Remaining work is device measurement + the August 2026 launch.
