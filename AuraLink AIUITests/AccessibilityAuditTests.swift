//
//  AccessibilityAuditTests.swift
//  AuraLink AIUITests
//
//  Phase 6 gate: run Apple's automated accessibility audit on the main surfaces. It catches real
//  issues — contrast, hit-region size, missing labels, clipped Dynamic Type — that manual review
//  misses. Dynamic-Type-clipping is excluded on the audit run because captions intentionally use
//  `minimumScaleFactor` to shrink rather than truncate.
//

import XCTest

final class AccessibilityAuditTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMainScreenAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-skip-onboarding"]
        app.launch()

        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription])
    }

    @MainActor
    func testOnboardingAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()   // fresh: onboarding is presented
        guard app.buttons["Next"].waitForExistence(timeout: 5) || app.buttons["Get started"].exists else {
            return   // already onboarded on this simulator; nothing to audit here
        }
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription])
    }
}
