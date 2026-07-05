//
//  PosePreviewScreen.swift
//  AuraLink AI
//
//  Live hand-skeleton overlay for on-device Phase 2 verification. Draws detected joints and
//  bones on a dark canvas with a capture→pose latency HUD.
//
//  Coordinate handling: Vision points are image-normalized with a bottom-left origin, and the
//  front camera is unmirrored — so the view flips Y (screen origin is top-left) and mirrors X
//  (so the preview behaves like a mirror, which is what a user facing the camera expects).
//

import SwiftUI

struct PosePreviewScreen: View {
    @State private var model: PosePreviewViewModel

    init(model: PosePreviewViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                skeleton
                overlay
            }
            .navigationTitle("Pose preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var skeleton: some View {
        Canvas { context, size in
            guard let pose = model.pose else { return }
            // A lone hand is always drawn as the (stable) right-hand color to match how it's slotted
            // for recognition; two hands keep their per-chirality colors.
            let single = pose.hands.count == 1
            for hand in pose.hands {
                let color: Color = single ? .orange : (hand.chirality == .left ? .cyan : .orange)
                draw(hand: hand, color: color, in: &context, size: size)
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var overlay: some View {
        VStack {
            Spacer()
            Button {
                model.cycleOrientation()
            } label: {
                Label("Orientation: \(model.orientationName)", systemImage: "rotate.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.blue.opacity(0.6), in: Capsule())
            }
            .padding(.bottom, 10)
            .accessibilityHint("Cycles the camera orientation until the skeleton looks upright")

            HStack(spacing: 16) {
                statChip("hand.raised", "\(model.pose?.hands.count ?? 0)")
                if let stats = model.stats {
                    statChip("gauge.with.needle",
                             String(format: "p50 %.0f · p95 %.0f ms", stats.latencyP50Ms, stats.latencyP95Ms))
                    statChip("percent", String(format: "%.0f%% hands", stats.detectionRate * 100))
                }
            }
            .padding(.bottom, 12)

            if let errorText = model.errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding()
            } else if model.pose == nil, model.isRunning {
                Text("Show a hand to the front camera…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
    }

    private func statChip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.15), in: Capsule())
    }

    private var accessibilitySummary: String {
        let count = model.pose?.hands.count ?? 0
        return count == 0 ? "No hands detected" : "\(count) hand\(count == 1 ? "" : "s") tracked"
    }

    // MARK: - Drawing

    private func draw(hand: HandPose, color: Color, in context: inout GraphicsContext, size: CGSize) {
        let minConfidence: Float = 0.3

        func screenPoint(_ joint: HandJoint) -> CGPoint? {
            guard hand.confidences[joint.rawValue] >= minConfidence else { return nil }
            let p = hand.points[joint.rawValue]
            // Orientation/mirroring is handled in Vision; here only flip Y (Vision's bottom-left
            // origin → SwiftUI's top-left).
            return CGPoint(x: CGFloat(p.x) * size.width,
                           y: (1 - CGFloat(p.y)) * size.height)
        }

        var bonePath = Path()
        for (a, b) in HandSkeleton.bones {
            guard let pa = screenPoint(a), let pb = screenPoint(b) else { continue }
            bonePath.move(to: pa)
            bonePath.addLine(to: pb)
        }
        context.stroke(bonePath, with: .color(color.opacity(0.7)), lineWidth: 3)

        for joint in HandJoint.allCases {
            guard let p = screenPoint(joint) else { continue }
            let radius: CGFloat = joint == .wrist ? 7 : 4.5
            let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}
