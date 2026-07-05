# AuraLink AI — App Store Submission Kit

Everything needed to submit once an Apple Developer membership is active (planned August 2026).
Nothing here requires a paid account to prepare.

## Listing

**Name:** AuraLink AI
**Subtitle:** On-device sign & sound translator

**Promotional text:**
Understand sign language, captions, and sounds — instantly, privately, entirely on your iPhone. No
account. No network. Nothing leaves your device.

**Description:**
AuraLink AI is a real-time, fully offline accessibility engine.

• Sign to text — recognizes American Sign Language (a ~200-sign "Everyday Needs" vocabulary) and
  turns it into readable English. Teach it your signing by recording a few examples of each sign.
• Live captions — transcribes nearby speech on device, in real time.
• Sound awareness — flags important sounds like alarms, sirens, doorbells, and knocks.
• Feel the voice — a haptic channel lets you feel a speaker's loudness and pitch, the emphasis and
  intonation that plain captions leave out.

Built for speed and privacy: everything runs on the Neural Engine with a strict latency budget, and
adapts gracefully under heat or low battery instead of stuttering. There is no account, no tracking,
and no network access — your camera and microphone never leave your device.

**Keywords:** sign language,ASL,accessibility,deaf,hard of hearing,captions,transcribe,haptics,
offline,privacy,sound

**Category:** Primary — Utilities; Secondary — Education
**Age rating:** 4+

## Privacy (App Store Connect answers)

- **Data collection:** Data Not Collected.
- **Tracking:** No.
- Privacy manifest: `AuraLink AI/PrivacyInfo.xcprivacy` — no collected data types, no tracking,
  UserDefaults required-reason CA92.1.
- Privacy policy URL: the `PRIVACY.md` file in the public repository.

## Export compliance

- Uses only standard Apple encryption (CryptoKit AES-GCM for local exemplar files, Keychain).
- Exempt: `ITSAppUsesNonExemptEncryption = NO` (add to Info before submission).

## Review notes (draft)

> AuraLink is fully on-device and requires no account. To review sign translation: open the menu →
> Enroll, record ~3 examples for a few signs (e.g. "hello", "thank you", "water"), close Enroll, tap
> Start, and perform those signs to the front camera. Listen mode (menu → Listen) captions speech
> and flags sounds; it uses on-device speech recognition only. The capability badge (top of the main
> screen) opens a Governor screen with a thermal-state override that demonstrates the app's live
> quality adaptation. No network is used; the app links no networking APIs.

## Screenshot shot list (6.7" + 6.1")

1. Main screen mid-translation — a caption reading "I need water." with the confidence label.
2. Enroll screen — the vocabulary list with a few signs showing "3/3 ready".
3. Live pose preview — hand skeleton overlay with the latency HUD.
4. Listen screen — a caption plus an "Alarm" event chip and the prosody meter.
5. Governor screen — tier dropped to "A14 · Distilled · thermal" under a forced Serious state.
6. Onboarding "Private by design" page.

## App icon

- 1024×1024, no alpha, no rounded corners.
- Concept: an abstract hand + soundwave merging into a single "aura" ring; high contrast for
  low-vision recognizability.

## Pre-submission checklist

See `docs/LAUNCH_CHECKLIST.md`.
