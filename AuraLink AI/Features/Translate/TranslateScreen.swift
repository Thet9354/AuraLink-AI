//
//  TranslateScreen.swift
//  AuraLink AI
//
//  Phase 0 UI. Renders the live caption with confidence-aware styling, a device-tier badge, and
//  a glass-to-caption latency HUD. Named `TranslateScreen` (not `TranslateView`) to avoid the
//  SwiftUI `NavigationView` naming-clash convention carried from the portfolio's prior project.
//

import SwiftUI

struct TranslateScreen: View {
    @State private var model: TranslateViewModel
    @State private var showingDiagnostics = false
    @State private var showingPosePreview = false
    private let diagnostics: CaptureDiagnosticsViewModel
    private let posePreview: PosePreviewViewModel

    init(model: TranslateViewModel,
         diagnostics: CaptureDiagnosticsViewModel,
         posePreview: PosePreviewViewModel) {
        _model = State(initialValue: model)
        self.diagnostics = diagnostics
        self.posePreview = posePreview
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
        .sheet(isPresented: $showingDiagnostics) {
            CaptureDiagnosticsView(model: diagnostics)
        }
        .sheet(isPresented: $showingPosePreview) {
            PosePreviewScreen(model: posePreview)
        }
    }

    private var header: some View {
        HStack {
            Label("AuraLink", systemImage: "hand.wave")
                .font(.headline)
            Spacer()
            Text(model.tier.badge)
                .font(.caption.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel("Device capability tier \(model.tier.badge)")
            Button {
                showingPosePreview = true
            } label: {
                Image(systemName: "hand.raised")
            }
            .accessibilityLabel("Live pose preview")
            Button {
                showingDiagnostics = true
            } label: {
                Image(systemName: "stethoscope")
            }
            .accessibilityLabel("Capture diagnostics")
        }
    }

    @ViewBuilder
    private var caption: some View {
        if let caption = model.caption {
            VStack(spacing: 12) {
                FlowText(spans: caption.spans)
                    .animation(.easeInOut(duration: 0.15), value: caption.id)
                confidenceLabel(caption.band)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(caption.plainText)
        } else {
            Text(model.isRunning ? "Listening…" : "Tap Start to translate")
                .font(.title3)
                .foregroundStyle(.secondary)
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
    }

    private var latencyHUD: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.needle")
            Text(model.caption.map { "\($0.latencyMs) ms" } ?? "—")
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private var controlButton: some View {
        Button {
            model.isRunning ? model.stop() : model.start()
        } label: {
            Text(model.isRunning ? "Stop" : "Start")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.isRunning ? .red : .accentColor)
    }
}

/// Renders styled caption spans as wrapping text, applying confidence-aware styling.
private struct FlowText: View {
    let spans: [StyledSpan]

    var body: some View {
        Text(attributed)
            .font(.system(size: 34, weight: .semibold, design: .rounded))
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
    let vm = TranslateViewModel(pipeline: MockCaptionPipeline(tier: tier), tier: tier)
    let capture = CaptureActor()
    let vision = VisionActor()
    let diagnostics = CaptureDiagnosticsViewModel(capture: capture, audio: AudioActor(), vision: vision)
    let posePreview = PosePreviewViewModel(capture: capture, vision: vision)
    return TranslateScreen(model: vm, diagnostics: diagnostics, posePreview: posePreview)
}
