//
//  AuraLink_AIApp.swift
//  AuraLink AI
//
//  Application entry point. Owns the composition root and presents the translation screen.
//

import SwiftUI

@main
struct AuraLink_AIApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            if container.settings.hasOnboarded {
                TranslateScreen(model: container.translateViewModel,
                                diagnostics: container.captureDiagnosticsViewModel,
                                posePreview: container.posePreviewViewModel,
                                enroll: container.enrollViewModel,
                                listen: container.listenViewModel,
                                governor: container.governor,
                                settings: container.settings)
            } else {
                OnboardingView { container.settings.hasOnboarded = true }
            }
        }
    }
}
