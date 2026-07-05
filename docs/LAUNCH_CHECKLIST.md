# AuraLink AI — Launch Checklist

Mechanical steps for submission once the Apple Developer membership is active (planned August 2026).
Everything else is done and verified.

## Code / project (done unless noted)
- [x] Swift 6 language mode, zero-warning build.
- [x] Full test suite green (unit + accessibility audit).
- [x] `PrivacyInfo.xcprivacy` — Data Not Collected, CA92.1.
- [x] Usage strings: camera, microphone, speech recognition.
- [x] Portrait-only, iOS 18+.
- [ ] Add `ITSAppUsesNonExemptEncryption = NO` to Info (export compliance).
- [ ] App icon (1024²) + accent color finalized.

## Device verification (owner, on hardware)
- [ ] Enroll → translate a few signs; confirm top-1 accuracy on own signing.
- [ ] Glass→caption latency ≤ 220 ms p95 (A17) via `segmentToCaption` signpost (Instruments).
- [ ] Capture→pose ≤ 25 ms p95; 60 fps sustained (Diagnostics + Instruments).
- [ ] Listen: captions, sound-event chips, prosody meter + haptics.
- [ ] Governor: force Serious/Critical → tier drops, pose rate falls, recovers on Auto; no hitch.
- [ ] **Zero network egress** during a full session (Network Instrument) — the marquee proof.
- [ ] 30-minute soak: flat Allocations (no leak), no crash, thermal ≤ serious, battery Wh/hr logged.
- [ ] Accessibility Inspector audit: zero critical; test with VoiceOver + large Dynamic Type.

## App Store Connect (August 2026)
- [ ] Enroll in the Apple Developer Program.
- [ ] Create the app record; fill listing from `docs/APP_STORE_KIT.md`.
- [ ] Privacy: Data Not Collected; policy URL = repo `PRIVACY.md`.
- [ ] Upload 6 screenshots (shot list in the kit) + optional App Preview.
- [ ] TestFlight build; include at least one Deaf / hard-of-hearing tester.
- [ ] Submit with the review notes from the kit.

## Owner tasks before August
- [ ] App icon + demo video + screenshots.
- [ ] Full Instruments campaign (above).
- [ ] On-device regression of every mode.
