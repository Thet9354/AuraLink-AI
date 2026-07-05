//
//  SettingsView.swift
//  AuraLink AI
//
//  Accessibility and feedback preferences, plus the privacy statement and an onboarding replay.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let onReplayOnboarding: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Feedback") {
                    Toggle("Speak signs aloud", isOn: $settings.speakAloud)
                        .accessibilityHint("Speaks each recognized sign or phrase with on-device text-to-speech")
                    Toggle("Haptic prosody", isOn: $settings.hapticsEnabled)
                        .accessibilityHint("Feel a speaker's loudness and pitch through vibration in Listen mode")
                    Toggle("Larger captions", isOn: $settings.largeCaptions)
                        .accessibilityHint("Increases caption text size for low vision")
                }

                Section("Privacy") {
                    Label("On-device only", systemImage: "lock.fill")
                        .foregroundStyle(.green)
                    Text("AuraLink has no account and no network access. Your camera and microphone never leave this device — enforced by the app's architecture, not just its policy. Recorded sign examples are encrypted at rest.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Replay intro") { onReplayOnboarding() }
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } footer: {
                    Text("American Sign Language · ~200-sign Everyday Needs vocabulary v1")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
