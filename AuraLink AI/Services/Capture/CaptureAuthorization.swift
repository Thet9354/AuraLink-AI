//
//  CaptureAuthorization.swift
//  AuraLink AI
//
//  Camera and microphone permission gates. All processing is on-device; the usage descriptions
//  (in the generated Info.plist) state that captured media never leaves the device.
//

import AVFoundation
import Speech

nonisolated enum CaptureAuthorization {

    /// Ensures speech-recognition access, prompting once if undetermined. On-device recognition is
    /// forced at request time; this only governs whether the app may transcribe at all.
    static func ensureSpeech() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }


    /// Ensures camera access, prompting once if undetermined. Returns whether access is granted.
    static func ensureVideo() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// Ensures microphone access, prompting once if undetermined. Returns whether access is granted.
    static func ensureMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
}
