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
            for hand in pose.hands {
                draw(hand: hand, in: &context, size: size)
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var overlay: some View {
        VStack {
            Spacer()
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

    /// Bone chains: wrist → each finger, joint to joint.
    private static let bones: [(HandJoint, HandJoint)] = [
        (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
        (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
        (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
        (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
        (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip)
    ]

    private func draw(hand: HandPose, in context: inout GraphicsContext, size: CGSize) {
        let minConfidence: Float = 0.3
        let color: Color = hand.chirality == .left ? .cyan : .orange

        func screenPoint(_ joint: HandJoint) -> CGPoint? {
            guard hand.confidences[joint.rawValue] >= minConfidence else { return nil }
            let p = hand.points[joint.rawValue]
            // Mirror X (front camera), flip Y (Vision is bottom-left origin).
            return CGPoint(x: (1 - CGFloat(p.x)) * size.width,
                           y: (1 - CGFloat(p.y)) * size.height)
        }

        var bonePath = Path()
        for (a, b) in Self.bones {
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
