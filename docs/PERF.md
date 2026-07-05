# AuraLink AI — Performance Budget & Gates

Every metric is a **number**, measured with `OSSignposter` (subsystem `com.thetpine.auralink`) +
Instruments, and logged here as it is achieved. A phase is green only if the device's own ceiling
is met. Dual ceilings reflect the A14→A17 quality-ladder decision.

| Metric | A17 target | A14 floor | Instrument | Status |
|---|---|---|---|---|
| Capture → pose | 25 ms p95 | 40 ms p95 | signpost interval (`latency`) | — |
| Glass → sign caption | 220 ms p95 | 350 ms p95 | signpost interval (`latency`) | — |
| Sound onset → haptic | 100 ms | 150 ms | signpost (`latency`) | — |
| UI frame rate | 60 fps sustained | 60 fps pose / degraded infer | Core Animation FPS | — |
| Steady-state heap growth | 0 | 0 | Allocations (flat) | — |
| Peak resident | ≤ 400 MB | ≤ 300 MB | Allocations | — |
| Cold launch → first caption | < 2 s | < 3 s | signpost | — |
| Network egress | 0 bytes | 0 bytes | Network | — |
| 30-min soak thermal | ≤ `.serious` | ≤ `.serious` | thermalState log | — |
| Battery drain | documented Wh/hr | documented | Energy Log | — |

## Signpost categories

- `latency` — glass→caption and per-stage intervals:
  - `captureToPose` (Phase 2) — camera frame → pose/features.
  - `segmentToCaption` (Phase 3) — segment close → rendered caption (DTW match + grammar).
  - sound onset → haptic (Phase 4) — SoundAnalysis event → Taptic pattern (≤ 100 ms).
- `pipeline` — pipeline lifecycle and per-stage intervals (inference, segmentation).
- `governor` — tier transitions (thermal/battery/memory de-rating), emitted on every change.

## Measurement discipline

- Latency/thermal/battery gates are **device-measured**, not CI-gated (an ANE latency cannot be
  measured on a CI VM). Record results in this table with the device + iOS version.
- Pure-function and fixture tests (DTW distance, segmentation boundaries, governor transitions,
  prosody mapping) run in CI on the simulator.
- The single demo that best sells the systems story: live `ThermalGovernor` tier-drop under heat,
  captured next to a Network Instrument trace showing a flat-zero egress line for a full session.
