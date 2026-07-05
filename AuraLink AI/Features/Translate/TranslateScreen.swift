//
//  TranslateScreen.swift
//  AuraLink AI
//
//  The primary screen: live sign→text caption with confidence-aware styling, a glass-to-caption
//  latency HUD, and a live capability badge. Secondary modes (Listen, Enroll, previews, Settings)
//  live behind a single menu to keep the surface calm. Fully VoiceOver-labelled and Dynamic
//  Type-friendly; captures stop when the app leaves the foreground.
//

import SwiftUI

struct TranslateScreen: View {
    @State private var model: TranslateViewModel
    @State private var showingDiagnostics = false
    @State private var showingPosePreview = false
    @State private var showingEnroll = false
    @State private var showingRecall = false
    @State private var showingListen = false
    @State private var showingGovernor = false
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    private let diagnostics: CaptureDiagnosticsViewModel
    private let posePreview: PosePreviewViewModel
    private let enroll: EnrollViewModel
    private let recall: SignRecallViewModel
    private let listen: ListenViewModel
    private let governor: GovernorController
    private let settings: AppSettings

    init(model: TranslateViewModel,
         diagnostics: CaptureDiagnosticsViewModel,
         posePreview: PosePreviewViewModel,
         enroll: EnrollViewModel,
         recall: SignRecallViewModel,
         listen: ListenViewModel,
         governor: GovernorController,
         settings: AppSettings) {
        _model = State(initialValue: model)
        self.diagnostics = diagnostics
        self.posePreview = posePreview
        self.enroll = enroll
        self.recall = recall
        self.listen = listen
        self.governor = governor
        self.settings = settings
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            Spacer()
            caption
            Spacer()
            latencyHUD
            controlButton
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onDisappear { model.stop() }
        // Lifecycle: release the camera + ANE whenever we leave the foreground.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.stop() }
        }
        .sheet(isPresented: $showingDiagnostics) { CaptureDiagnosticsView(model: diagnostics) }
        .sheet(isPresented: $showingPosePreview) { PosePreviewScreen(model: posePreview) }
        .sheet(isPresented: $showingEnroll) { EnrollView(model: enroll) }
        .sheet(isPresented: $showingRecall) { SignRecallScreen(model: recall) }
        .sheet(isPresented: $showingListen) { ListenScreen(model: listen) }
        .sheet(isPresented: $showingGovernor) { GovernorView(controller: governor) }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings) {
                showingSettings = false
                settings.hasOnboarded = false   // App re-presents onboarding
            }
        }
    }

    private var header: some View {
        HStack {
            Label("AuraLink", systemImage: "hand.wave")
                .font(.headline)
            Spacer()
            capabilityBadge
            menu
        }
    }

    private var capabilityBadge: some View {
        Button {
            showingGovernor = true
        } label: {
            Text(governor.resolved.badge)
                .font(.caption.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(tierBadgeColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .accessibilityLabel("Capability \(governor.resolved.badge). Opens the governor.")
    }

    private var menu: some View {
        Menu {
            Button { showingListen = true } label: { Label("Listen", systemImage: "ear") }
            Button { showingEnroll = true } label: { Label("Enroll signs", systemImage: "plus.rectangle.on.folder") }
            Button { showingRecall = true } label: { Label("My signs", systemImage: "hand.raised.square") }
            Divider()
            Button { showingPosePreview = true } label: { Label("Pose preview", systemImage: "hand.raised") }
            Button { showingDiagnostics = true } label: { Label("Diagnostics", systemImage: "stethoscope") }
            Divider()
            Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
        }
        .accessibilityLabel("More")
    }

    private var tierBadgeColor: Color {
        switch governor.resolved.reason {
        case .nominal: Color(.quaternarySystemFill)
        case .thermal: .red.opacity(0.25)
        case .lowPower: .orange.opacity(0.25)
        case .memory: .yellow.opacity(0.25)
        }
    }

    @ViewBuilder
    private var caption: some View {
        if let caption = model.caption {
            VStack(spacing: 12) {
                FlowText(spans: caption.spans, large: settings.largeCaptions)
                    .animation(.easeInOut(duration: 0.15), value: caption.id)
                confidenceLabel(caption.band)
                if let alternative = caption.alternative {
                    Text("did you mean “\(alternative)”?")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(caption.plainText)
            .accessibilityValue(caption.alternative.map { "\(confidenceWord(caption.band)). Did you mean \($0)?" }
                                ?? confidenceWord(caption.band))
        } else {
            Text(model.isRunning ? "Signing…" : "Tap Start, then sign to the camera")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func confidenceLabel(_ band: ConfidenceBand) -> some View {
        let (text, color): (String, Color) = switch band {
        case .high: ("High confidence", .green)
        case .medium: ("Medium confidence", .yellow)
        case .low: ("Low confidence — verify", .orange)
        }
        return Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private func confidenceWord(_ band: ConfidenceBand) -> String {
        switch band {
        case .high: "high confidence"
        case .medium: "medium confidence"
        case .low: "low confidence, please verify"
        }
    }

    @ViewBuilder
    private var latencyHUD: some View {
        if let caption = model.caption {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.needle")
                Text("\(caption.latencyMs) ms")
                    .monospacedDigit()
            }
            // `.primary` (not `.secondary`): small text must clear the 4.5:1 contrast bar.
            .font(.caption)
            .foregroundStyle(.primary)
            .accessibilityHidden(true)
        }
    }

    private var controlButton: some View {
        Button {
            model.isRunning ? model.stop() : model.start()
        } label: {
            // Large text (20 pt) qualifies for the relaxed 3:1 contrast threshold on the tinted fill.
            Text(model.isRunning ? "Stop" : "Start")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.isRunning ? .red : .accentColor)
        .accessibilityHint(model.isRunning ? "Stops translating" : "Starts the camera and translates your signing")
    }
}

/// Renders styled caption spans as wrapping text, applying confidence-aware styling. Uses a Dynamic
/// Type text style (scales with the user's preferred size) rather than a fixed point size.
private struct FlowText: View {
    let spans: [StyledSpan]
    var large: Bool = false

    var body: some View {
        Text(attributed)
            .font(.system(large ? .largeTitle : .title, design: .rounded).weight(.semibold))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .minimumScaleFactor(0.6)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for (index, span) in spans.enumerated() {
            var piece = AttributedString(span.text)
            switch span.weight {
            case .confident:
                piece.foregroundColor = .primary
            case .tentative:
                piece.foregroundColor = .secondary
                piece.underlineStyle = .single
            case .unknown:
                piece.foregroundColor = .orange
            }
            result += piece
            if index < spans.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }
}

#Preview {
    let tier = CapabilityTier.baseline(for: .a17plus)
    let settings = AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard)
    let vm = TranslateViewModel(pipeline: MockCaptionPipeline(tier: tier), tier: tier,
                                speech: SpeechSynthesizer(), settings: settings)
    let capture = CaptureActor()
    let vision = VisionActor()
    let store = ExemplarFileStore()
    let phraseStore = CustomPhraseFileStore()
    let lexicon = SignLexicon(entries: [])
    let diagnostics = CaptureDiagnosticsViewModel(capture: capture, audio: AudioActor(), vision: vision)
    let posePreview = PosePreviewViewModel(capture: capture, vision: vision)
    let recorder = EnrollmentRecorder(capture: capture, vision: vision, store: store)
    let enroll = EnrollViewModel(lexicon: lexicon, recorder: recorder, store: store, phraseStore: phraseStore)
    let recall = SignRecallViewModel(catalog: lexicon, store: store, phraseStore: phraseStore)
    let listen = ListenViewModel(listener: AudioListener(haptics: HapticsActor()), settings: settings)
    let governor = GovernorController(baseRung: .a17plus)
    return TranslateScreen(model: vm, diagnostics: diagnostics, posePreview: posePreview,
                           enroll: enroll, recall: recall, listen: listen, governor: governor, settings: settings)
}
