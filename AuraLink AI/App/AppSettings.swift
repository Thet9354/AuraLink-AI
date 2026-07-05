//
//  AppSettings.swift
//  AuraLink AI
//
//  User-facing preferences, persisted in UserDefaults (the app's only `UserDefaults` use, declared
//  as required-reason CA92.1 in PrivacyInfo.xcprivacy). Observable so settings apply live.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {

    /// Whether the cross-modal haptic prosody channel is active in Listen mode.
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }

    /// Larger caption text for low-vision users (on top of Dynamic Type).
    var largeCaptions: Bool {
        didSet { defaults.set(largeCaptions, forKey: Keys.largeCaptions) }
    }

    /// Whether first-launch onboarding has been completed.
    var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Keys.onboarded) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        self.largeCaptions = defaults.bool(forKey: Keys.largeCaptions)
        // UI tests skip onboarding to audit the main screen deterministically.
        if ProcessInfo.processInfo.arguments.contains("--uitest-skip-onboarding") {
            self.hasOnboarded = true
        } else {
            self.hasOnboarded = defaults.bool(forKey: Keys.onboarded)
        }
    }

    private enum Keys {
        static let haptics = "settings.hapticsEnabled"
        static let largeCaptions = "settings.largeCaptions"
        static let onboarded = "settings.hasOnboarded"
    }
}
