# AuraLink AI — Technical Design Specification

Companion to `ARCHITECTURE.md` (concurrency/memory), `ROADMAP.md` (phases/gates), `PERF.md`
(budgets). This document covers features, the sign-recognition pipeline, the capability model,
and failure-mode mitigations.

## 1. Feature architecture

### Tier 0 — core transcoding
- Continuous ASL sign recognition (pose sequence → gloss → fluent text).
- Live ambient captioning (on-device streaming speech-to-text, speaker-change detection).
- Directional sound awareness (classify + localize environmental sounds → on-screen arrows + haptics).

### Tier 1 — cross-modal feedback
- **Haptic prosody** — map audio pitch/energy envelope to Core Haptics transients so a Deaf user
  *feels* emphasis/urgency that captions lose entirely.
- **Confidence-aware rendering** — never present a low-confidence translation as fact. Sub-threshold
  tokens render distinctly (`.tentative`) or as an explicit gap (`.unknown`), and are spoken with a
  rising "uncertain" intonation. Honesty is an accessibility feature. (Already stubbed in Phase 0.)
- **Gaze-stabilized captions** — anchor the caption plane in world space (ARKit) so text doesn't
  jitter with hand-held camera shake; critical for low-vision legibility.

### Tier 2 — innovation
- **On-device signer personalization** — few-shot enrollment adds/replaces the user's own DTW
  exemplars, correcting for individual signing dialect/speed. Zero data leaves the device;
  the exemplar delta is Secure-Enclave-encrypted at rest.
- **Predictive gesture pre-emption** — a small autoregressive head predicts the likely completion
  of an in-progress sign so the UI pre-renders candidates; commit only when the recognizer confirms.
  (a17plus only.)
- **Semantic scene compression** — narrate only what *changed and matters* ("door opened on your
  left"), throttled to human attention bandwidth, instead of naming every object.
- **Thermal-aware quality ladder** — the app visibly, gracefully drops model tiers under heat
  rather than hitching. See the capability model below.

Hardware maximization: ANE (transformer/LM heads), GPU/MPS (pose preprocessing), Accelerate/AMX
(DSP), Secure Enclave (personalization at rest), LiDAR (sound-source depth on Pro), Taptic Engine
(prosody channel).

## 2. Sign recognition — pose-only + rule/LM gloss

Chosen over a trained end-to-end transformer to de-risk data sourcing and make accuracy testable.
Recognition lives in pose robustness + template matching, not an opaque model.

```
FrameToken
  │ Vision: VNDetectHumanHandPose + VNDetectHumanBodyPose
  ▼
PoseObservation ──► normalize (wrist origin, shoulder-width scale, canonical rotation)
  │                 → invariance to camera distance/position
  ▼
FeatureVector (per frame: joint angles, fingertip distances, palm normal, motion velocity)
  │ push into rolling pose ring
  ▼
FusionActor segmentation: motion-energy(t) = Σ‖velocity‖
  OPEN on energy > θ_start ; CLOSE on sustained energy < θ_stop (pause) OR maxLen
  ▼
GestureSegment (variable-length feature window)
  │ InferenceCoordinator — two collaborating stages:
  │   (1) DTW template match vs lexicon exemplars → k-NN candidates + distances
  │        → per-candidate confidence via softmax(-distance)
  │   (2) tiny on-device LM over gloss sequences picks the most fluent path
  ▼
GlossGrammar rule layer: gloss sequence → fluent English (ASL topic-comment order → SVO,
  insert function words)
  ▼
GlossHypothesis → CaptionDTO
  candidate below θ_conf → StyledSpan(.unknown) "…" ; NEVER fabricate a gloss
```

**Why DTW first:** handles signing-speed variation for free, needs only a handful of exemplars per
sign, and yields a *distance* that calibrates into honest confidence (reliability-diagram gate in
Phase 3). It also makes personalization trivial (swap in the user's exemplars — no training loop
for v1). **Upgrade path:** replace the exemplar matcher with a learned sequence encoder behind the
unchanged `SignRecognizing` protocol once labeled data is flowing.

## 3. Vocabulary — ASL "Everyday Needs" (~200 signs) v1

Scoped to highest-utility accessibility interactions: greetings; yes/no/help; basic needs (water,
food, restroom, pain, medicine); places/directions; numbers 0–20; common questions (where/when/
how much); emergency phrases. Small enough that DTW is fast and fixtures are collectable; large
enough to be genuinely useful. Framed honestly: a reliable 200-sign translator with calibrated
confidence beats a leaky open-vocabulary claim. Out-of-vocabulary signs render as `.unknown`.

## 4. Capability model (quality ladder)

`CapabilityProbe` classifies the device into a `DeviceRung` (`a14floor` / `a15` / `a17plus`) at
launch → baseline `CapabilityTier` (model variant, feature flags, fps caps). The governor may only
push the *effective* tier DOWN from baseline.

```
effectiveTier = min(baseRung, thermalCeiling, powerCeiling, memoryCeiling)   [hysteretic]

thermal:  .nominal→base   .fair→cap fps   .serious→drop one rung
          .critical→captions-only (pause haptics/scene/predictive), warn user
power:    lowPowerMode → force ≤ a15 behavior
memory:   .warning → drop one rung + flush pools ; 30 s clean → recover one rung
hysteresis: require stability ≥ 4 s before upgrading; downgrade immediately
```

Feature availability by rung (single source of truth in `CapabilityTier.baseline(for:)`):

| Feature | a17plus | a15 | a14floor |
|---|---|---|---|
| Sign model variant | full | full | distilled |
| Pose sample rate | 60 | 60 | 30 |
| Sign inference rate | 30/s | 20/s | 12/s |
| Predictive pre-emption | ✅ | ❌ | ❌ |
| Haptic prosody | full | full | reduced |
| LiDAR sound-depth | ✅ | ❌ | ❌ |
| Scene-change narration | continuous | continuous | on-demand |

## 5. Failure-mode matrix

| Failure | Detection | Fail-safe |
|---|---|---|
| Thermal `.critical` | thermalState notif | governor → captions-only, warn |
| Memory `.warning` | memory-pressure source | drop tier, flush pools |
| ANE stall > 2× budget | signpost watchdog | cancel task, drop frame, degrade tier |
| Pose confidence collapse | per-frame confidence | honest "conditions poor" UI, no hallucination; torch prompt |
| Audio route change / interruption | `AVAudioSession` notif | pause, restore state, no crash |
| App backgrounded | scene phase | tear down session, release ANE |
| Low battery | `isLowPowerModeEnabled` | force low tier, disable non-essential features |
| Cold ANE first inference slow | — | pre-warm dummy inference during onboarding |

## 6. Privacy / offline guarantee

No networking entitlement requested; no `URLSession` linked in the app target — the strongest
privacy claim is architectural impossibility, not policy. All models bundled; personalization
stays in Secure-Enclave-wrapped storage. `PrivacyInfo.xcprivacy` declares "Data Not Collected".
Egress = 0 is proven with the Network Instrument in Phase 6.
