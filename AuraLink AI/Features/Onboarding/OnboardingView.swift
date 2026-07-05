//
//  OnboardingView.swift
//  AuraLink AI
//
//  First-launch introduction to the four modalities and the privacy stance, ending by priming the
//  camera/microphone/speech permissions. Fully VoiceOver-labelled and Dynamic Type-friendly.
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let systemImage: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(systemImage: "hand.wave.fill",
             title: "Sign to speech",
             body: "AuraLink recognizes American Sign Language and turns it into text — on device, in real time. Record a few examples of each sign in Enroll to teach it your signing."),
        Page(systemImage: "ear.fill",
             title: "Hear the room",
             body: "Listen mode captions nearby speech, flags important sounds like alarms and doorbells, and lets you feel a speaker's emphasis and pitch through haptics."),
        Page(systemImage: "gauge.with.needle.fill",
             title: "Fast and adaptive",
             body: "Everything runs on the Neural Engine with a hard latency budget. Under heat or low battery it gracefully lowers quality instead of stuttering."),
        Page(systemImage: "lock.fill",
             title: "Private by design",
             body: "No account, no network, no data collection. Your camera and microphone never leave this device — it's not a policy, it's how the app is built.")
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    pageView(page).tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(action: advance) {
                Text(page == pages.count - 1 ? "Get started" : "Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .accessibilityHint(page == pages.count - 1 ? "Finishes setup" : "Shows the next screen")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func pageView(_ page: Page) -> some View {
        VStack(spacing: 24) {
            Image(systemName: page.systemImage)
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(page.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(page.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title). \(page.body)")
    }

    private func advance() {
        if page < pages.count - 1 {
            withAnimation { page += 1 }
        } else {
            Task { await primePermissions(); onFinish() }
        }
    }

    /// Prime permissions up front so the first real use is friction-free. Declining is fine — the
    /// app degrades honestly per feature.
    private func primePermissions() async {
        _ = await CaptureAuthorization.ensureVideo()
        _ = await CaptureAuthorization.ensureMicrophone()
        _ = await CaptureAuthorization.ensureSpeech()
    }
}
