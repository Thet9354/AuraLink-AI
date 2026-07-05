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
