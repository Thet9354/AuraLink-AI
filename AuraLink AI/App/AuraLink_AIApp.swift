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
            TranslateScreen(model: container.translateViewModel,
                            diagnostics: container.captureDiagnosticsViewModel)
        }
    }
}
