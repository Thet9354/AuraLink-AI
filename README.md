# AuraLink AI

**A fully offline, on-device, real-time multimodal accessibility engine for iOS.**

AuraLink is a *sensory transcoder*: it ingests camera and microphone streams and re-projects
meaning across sensory modalities a user cannot access — American Sign Language → text/speech,
ambient speech → live captions + haptic prosody, and environmental sound → directional cues.
Everything runs on device. No network. No data leaves the phone — by architecture, not by policy.

> Status: **All 6 phases complete — submission-ready** (device measurement + Aug 2026 launch
> pending). Four working modalities: sign→text, speech→captions, sound→alerts, voice→haptics.
> See [`docs/ROADMAP.md`](docs/ROADMAP.md).

## The engineering claim

Not "it runs a model." The claim is a **provably data-race-free, back-pressured stream graph that
holds a hard latency budget under thermal and battery stress, on device, with zero network
dependency.**

- **Compile-time race safety** — Swift 6 language mode, strict concurrency *complete*, a strict DAG
  of actors with exactly one `@MainActor` boundary at the UI sink.
- **Bounded real-time latency** — a single-slot `LatestSlot<T>` channel gives implicit
  back-pressure: the pipeline always processes the *freshest* frame and drops stale ones, capping
  staleness at one frame interval instead of growing an unbounded queue.
- **Allocation-free hot loop** — pre-allocated pixel-buffer and tensor pools + ring buffers →
  zero steady-state heap growth (verified by a flat Instruments Allocations graph).
- **Quality ladder A14 → A17** — a device-capability tier plus a thermal/battery/memory governor
  that *visibly, gracefully* degrades model quality under stress rather than hitching.
- **Zero egress, provable** — no networking entitlement, no `URLSession` in the target; proven with
  the Network Instrument.

## Recognition approach

ASL v1 is a ~200-sign "Everyday Needs" vocabulary via a **pose-only + rule/LM gloss** pipeline:
Vision hand/body pose → normalized feature vectors → motion-energy segmentation → DTW template
match → tiny on-device LM → grammar rules → fluent text. DTW handles signing-speed variation for
free, needs few exemplars, and yields *calibrated* confidence. Out-of-vocabulary signs are shown
honestly as `…`, never fabricated. The `SignRecognizing` protocol is the seam for a learned
encoder later.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — concurrency, actor contracts, memory strategy.
- [`docs/DESIGN.md`](docs/DESIGN.md) — features, recognition pipeline, capability model, failure modes.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — six phases, each with a hard verification gate.
- [`docs/PERF.md`](docs/PERF.md) — latency/memory/thermal budget table (dual A14/A17 ceilings).

## Requirements

- Xcode 26, iOS 18.0+ (A14-class device or newer).
- App target builds in **Swift 6 language mode**; test target in Swift 5 mode.

## Tech

Swift 6 concurrency · SwiftUI + Observation · AVFoundation · Vision · Metal/MPS · Accelerate ·
Core ML (ANE) · Core Haptics · CryptoKit + Secure Enclave · OSSignposter.
