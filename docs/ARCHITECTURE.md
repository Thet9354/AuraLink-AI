# AuraLink AI — Architecture

Fully offline, on-device, real-time multimodal accessibility engine. This document is the
authoritative description of the concurrency, data-flow, and memory architecture. It is
enforced, not aspirational: every invariant below has a verification path in `PERF.md` / `ROADMAP.md`.

## System thesis

AuraLink is a real-time **sensory transcoder**: it ingests photons (camera) and pressure waves
(microphone) and re-projects meaning across sensory modalities a given user cannot access
(sign → text/speech, speech → captions/haptics, environment → audio/haptic cues). The
engineering claim that makes it portfolio-grade is not "it runs a model" — it is a **provably
data-race-free, back-pressured stream graph that holds a hard latency budget under thermal and
battery stress, on device, with zero network dependency.**

## Non-negotiable invariants

| Invariant | Target | Enforced by |
|---|---|---|
| Glass→caption latency (sign) | ≤ 220 ms p95 (A17) / ≤ 350 ms (A14) | back-pressure + signposts |
| UI frame delivery | 60 fps, never blocked by inference | actor isolation, `@MainActor` only at the sink |
| Data-race safety | compile-time proven | Swift 6 language mode, strict concurrency complete |
| Steady-state hot-loop allocation | zero heap growth | buffer pools + ring buffers |
| Network egress | 0 bytes | no networking entitlement / no `URLSession` in target |
| Thermal ceiling before degrade | `.serious` triggers adaptation | `ThermalGovernor` |

## Concurrency model

A strict **DAG of actors** connected by typed channels, with exactly one `@MainActor` boundary
at the very end. Nothing that isn't a UI value ever touches the main actor. Project setting:
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so Domain types and off-main services are
**explicitly `nonisolated`**; actors define their own isolation.

```
        HARDWARE                 BACKGROUND ISOLATION                       UI
  ┌──────────────┐          ┌──────────────────────────────┐        ┌──────────────┐
  │ AVCapture     │ FrameToken│  CaptureActor (custom exec)  │        │              │
  │ Video 60fps   ├──────────►│  nonisolated delegate→enqueue│        │              │
  └──────────────┘  LatestSlot└──────────┬───────────────────┘        │  @MainActor  │
                               │           │                            │  Translate   │
                    ┌──────────▼─────────┐ │  ┌──────────────────┐      │  ViewModel   │
  ┌──────────────┐ │ VisionActor         │ │  │ FusionActor       │ Caption  (@Observable)│
  │ AVAudioEngine ├─►│ pose/features(Metal├─┼─►│ align + segment   ├─DTO─►│              │
  │ mic           │ │ ANE)                │ │  └────────┬─────────┘      │              │
  └──────────────┘ └────────────────────┘ │           │                └──────┬───────┘
                    ┌────────────────────┐ │  ┌────────▼─────────┐            │
                    │ AudioActor          ├─┘  │ InferenceCoord    │     ┌──────▼───────┐
                    │ DSP + ASR           │    │ ANE sched + BP    │     │ HapticsActor  │
                    └────────────────────┘    └──────────────────┘     └──────────────┘
```

### Actor contracts

| Actor | Isolation / executor | Owns | Drop policy |
|---|---|---|---|
| `CaptureActor` | `actor` + custom `SerialExecutor` (userInteractive queue) | `AVCaptureSession`, `CVPixelBufferPool` | HW discards late frames; slot overwrite |
| `VisionActor` | `actor` | pose ring, Metal pipeline, `TensorPool` | drop before feature extraction when coordinator busy |
| `AudioActor` | `actor` (fed by RT tap) | PCM ring, VAD/ASR decoder state | VAD gates silence; oldest PCM overwritten |
| `FusionActor` | `actor` | open segment, ≤80 ms align jitter buffer | segment-level |
| `InferenceCoordinator` | `actor` | ANE semaphore (1–2), tier, `ModelRegistry` | **the back-pressure authority** (admission control) |
| `HapticsActor` | `actor` | health-checked `CHHapticEngine` | coalesce; latest prosody wins |
| `TranslateViewModel` | `@MainActor @Observable` | caption, tier, latency HUD | terminal |

### `LatestSlot<T>` — the load-bearing primitive

A single-slot, latest-value channel (`Services/Infra/LatestSlot.swift`). Producers never block;
`put` overwrites an un-taken value (intentional drop). A single consumer `take`s the freshest
value, suspending cooperatively (never blocking a thread, including the main thread) when empty.
This gives **implicit back-pressure with bounded latency**: staleness is capped at one production
interval. Queueing frames is how real-time systems die; dropping to the freshest value is the
correct real-time behavior. Verified by `LatestSlotTests`.

## Sendable / pixel-buffer boundary

Every value crossing an actor boundary is `Sendable`. `CVPixelBuffer`/`CMSampleBuffer` are not
`Sendable` and must not be copied (a 1080p frame at 60fps is a memory-bandwidth catastrophe).

There are exactly **three audited `@unchecked Sendable` boundaries** in the system, all at the
hardware edge, each documented in-file with its justification:

1. `FrameToken` — a retained `CVPixelBuffer` with single-ownership-transfer-by-handoff semantics
   (moved via the latest-value channel, never aliased).
2. `VideoOutputDelegate` — an `NSObject` (not `Sendable`) with a `seq` counter confined to the
   single serial capture delegate queue AVFoundation invokes it on.
3. `AudioRingBuffer` — a lock-free SPSC ring over a manually managed buffer; safety rests on the
   single-producer/single-consumer contract plus acquire/release atomics.

Everything else crossing a boundary is a value-type snapshot or an `Atomic`-backed `Sendable` type
(e.g. `CaptureCounters`).

## Memory strategy (allocation-free hot loop)

The failure mode of naïve CV apps: per-frame tensor/array allocation → heap fragmentation →
allocator lock contention → frame hitches → thermal spike. Mitigations:

1. Pre-allocated `CVPixelBufferPool` + custom `TensorPool` (`MLMultiArray` over owned pointers,
   `deallocator: .none`) — **zero `malloc` in steady state**, verified by a flat Allocations graph.
2. Ring buffers for all time-series (pose window, PCM). Fixed capacity, index arithmetic.
3. `Float16` wherever the model permits (halves bandwidth; ANE-friendly).
4. `autoreleasepool` around every capture-callback body (CoreMedia/Vision vend autoreleased objects).
5. `MTLHeap`-suballocated, aliased transient textures.
6. Strict DAG → no retain cycles → dependency injection at init, no `weak` except UI closures.

Budget: peak resident ≤ 400 MB (A17) / ≤ 300 MB (A14); memory-pressure observer drops a tier on `.warning`.

## Layering (module structure)

Single module, MVVM + Domain/Services, `AppContainer` as the sole composition root.
`PBXFileSystemSynchronizedRootGroup` — files on disk auto-join the target; never hand-edit the
pbxproj to add files.

- `Domain/` — pure `nonisolated Sendable` models + service **protocols**. No framework imports.
- `Services/` — concrete framework owners (actors). `Infra/` holds cross-cutting primitives.
- `Features/` — SwiftUI + `@MainActor @Observable` view models. View models see protocols only.
- `App/` — entry point + `AppContainer`.

The `CaptionProducing` protocol is the seam the UI depends on: the Phase 0 `MockCaptionPipeline`
is swapped for the real capture→vision→fusion→inference graph without touching the UI.
