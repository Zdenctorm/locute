import XCTest
@testable import Dictator

final class AccessibilityAuditReportTests: XCTestCase {
    func testBuildReport_containsSummaryAndInventory() {
        let context = AccessibilityAuditEngine.AuditContext(
            openWindowTitles: ["Nastavení"],
            axTrusted: true,
            appVersion: "1.0",
            bundlePath: "/Applications/Dictator.app"
        )
        let finding = AccessibilityAuditFinding(
            severity: .critical,
            surface: "Menu bar",
            path: "Menu > položka 0",
            issue: "Chybí label",
            suggestion: "Doplň title"
        )
        let snapshot = AccessibilityReferenceSnapshot(
            application: AccessibilityAuditEngine.referenceApplications[0],
            status: .sampled,
            metrics: AccessibilityReferenceMetrics(
                visitedNodes: 100,
                accessibilityElements: 40,
                labeledElements: 35,
                withHelp: 10,
                interactiveRoles: 12
            ),
            samplePaths: ["Nastavení > child[0]"]
        )

        let markdown = AccessibilityAuditReportBuilder.build(
            context: context,
            inventory: AccessibilitySurfaceInventory.current(),
            dictatorFindings: [finding],
            referenceSnapshots: [snapshot]
        )

        XCTAssertTrue(markdown.contains("# Dictator — analýza zpřístupnění"))
        XCTAssertTrue(markdown.contains("Kritické nálezy | 1"))
        XCTAssertTrue(markdown.contains("Menu bar"))
        XCTAssertTrue(markdown.contains("Inventář povrchů"))
        XCTAssertTrue(markdown.contains("Nastavení (System Settings)"))
    }

    func testSummaryParagraph_withoutAXTrust_mentionsTrust() {
        let context = AccessibilityAuditEngine.AuditContext(
            openWindowTitles: [],
            axTrusted: false,
            appVersion: "1.0",
            bundlePath: "/tmp"
        )
        let text = AccessibilityAuditReportBuilder.summaryParagraph(critical: 0, warnings: 0, context: context)
        XCTAssertTrue(text.contains("Zpřístupnění"))
    }

    func testRoadmap_includesCriticalStepWhenNeeded() {
        let critical = [
            AccessibilityAuditFinding(
                severity: .critical,
                surface: "UI",
                path: "x",
                issue: "y",
                suggestion: "z"
            )
        ]
        let context = AccessibilityAuditEngine.AuditContext(
            openWindowTitles: [],
            axTrusted: true,
            appVersion: "1",
            bundlePath: "/tmp"
        )
        let roadmap = AccessibilityAuditReportBuilder.roadmap(critical: critical, warnings: [], context: context)
        XCTAssertTrue(roadmap.contains("kritické"))
    }
}
