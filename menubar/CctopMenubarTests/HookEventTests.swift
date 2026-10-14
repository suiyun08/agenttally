import XCTest
@testable import CctopMenubar

final class HookEventTests: XCTestCase {

    // MARK: - HookEvent.parse()

    func testParseSessionStart() {
        XCTAssertEqual(HookEvent.parse(hookName: "SessionStart", notificationType: nil), .sessionStart)
    }

    func testParseUserPromptSubmit() {
        XCTAssertEqual(HookEvent.parse(hookName: "UserPromptSubmit", notificationType: nil), .userPromptSubmit)
    }

    func testParsePreToolUse() {
        XCTAssertEqual(HookEvent.parse(hookName: "PreToolUse", notificationType: nil), .preToolUse)
    }

    func testParsePostToolUse() {
        XCTAssertEqual(HookEvent.parse(hookName: "PostToolUse", notificationType: nil), .postToolUse)
    }

    func testParsePostToolUseFailure() {
        XCTAssertEqual(HookEvent.parse(hookName: "PostToolUseFailure", notificationType: nil), .postToolUseFailure)
    }

    func testParseStop() {
        XCTAssertEqual(HookEvent.parse(hookName: "Stop", notificationType: nil), .stop)
    }

    func testParseStopWithBackgroundWork() {
        XCTAssertEqual(
            HookEvent.parse(hookName: "Stop", notificationType: nil, hasBackgroundWork: true),
            .stopWithBackgroundWork
        )
    }

    func testParseStopFailure() {
        XCTAssertEqual(HookEvent.parse(hookName: "StopFailure", notificationType: nil), .stopFailure)
        XCTAssertEqual(
            HookEvent.parse(hookName: "StopFailure", notificationType: nil, hasBackgroundWork: true),
            .stopFailure
        )
    }

    func testParsePreToolUseForBlockingToolsAwaitsUser() {
        for tool in ["AskUserQuestion", "ExitPlanMode"] {
            XCTAssertEqual(
                HookEvent.parse(hookName: "PreToolUse", notificationType: nil, toolName: tool),
                .awaitingUserAnswer, tool
            )
        }
        XCTAssertEqual(HookEvent.parse(hookName: "PreToolUse", notificationType: nil, toolName: "Bash"), .preToolUse)
        // Claude Code also sends PermissionRequest for these tools, a millisecond apart and in either order.
        XCTAssertEqual(
            HookEvent.parse(hookName: "PermissionRequest", notificationType: nil, toolName: "AskUserQuestion"),
            .awaitingUserAnswer
        )
        XCTAssertEqual(
            HookEvent.parse(hookName: "PermissionRequest", notificationType: nil, toolName: "Bash"),
            .permissionRequest
        )
        XCTAssertEqual(
            HookEvent.parse(hookName: "PostToolUse", notificationType: nil, toolName: "AskUserQuestion"),
            .postToolUse
        )
    }

    func testOnlyTurnEndingEventsRestartTheFinishClock() {
        XCTAssertTrue(HookEvent.stop.endsTurn)
        XCTAssertTrue(HookEvent.stopWithBackgroundWork.endsTurn)
        XCTAssertTrue(HookEvent.stopFailure.endsTurn)
        XCTAssertFalse(HookEvent.notificationIdle.endsTurn)
        XCTAssertFalse(HookEvent.subagentStop.endsTurn)
    }

    func testParsePermissionRequest() {
        XCTAssertEqual(HookEvent.parse(hookName: "PermissionRequest", notificationType: nil), .permissionRequest)
    }

    func testParsePreCompact() {
        XCTAssertEqual(HookEvent.parse(hookName: "PreCompact", notificationType: nil), .preCompact)
    }

    func testParsePostCompact() {
        XCTAssertEqual(HookEvent.parse(hookName: "PostCompact", notificationType: nil), .postCompact)
    }

    func testParseSessionError() {
        XCTAssertEqual(HookEvent.parse(hookName: "SessionError", notificationType: nil), .sessionError)
    }

    func testParseSessionEnd() {
        XCTAssertEqual(HookEvent.parse(hookName: "SessionEnd", notificationType: nil), .sessionEnd)
    }

    func testParseUnknownHookName() {
        XCTAssertEqual(HookEvent.parse(hookName: "FutureHook", notificationType: nil), .unknown)
    }

    func testParseNotificationIdlePrompt() {
        XCTAssertEqual(HookEvent.parse(hookName: "Notification", notificationType: "idle_prompt"), .notificationIdle)
    }

    func testParseNotificationElicitationDialog() {
        XCTAssertEqual(
            HookEvent.parse(hookName: "Notification", notificationType: "elicitation_dialog"), .notificationElicitation
        )
        XCTAssertEqual(
            HookEvent.parse(hookName: "Notification", notificationType: "elicitation_url_dialog"), .notificationElicitation
        )
    }

    func testParseNotificationPermissionPrompt() {
        XCTAssertEqual(HookEvent.parse(hookName: "Notification", notificationType: "permission_prompt"), .notificationPermission)
    }

    func testParseNotificationNilType() {
        XCTAssertEqual(HookEvent.parse(hookName: "Notification", notificationType: nil), .notificationOther)
    }

    func testParseNotificationUnknownType() {
        XCTAssertEqual(HookEvent.parse(hookName: "Notification", notificationType: "future_type"), .notificationOther)
    }

    // MARK: - Transition.forEvent() — turn end

    private let allStatuses: [SessionStatus] = [
        .idle, .working, .compacting, .waitingPermission, .waitingInput, .needsAttention, .done, .background
    ]

    func testStopAlwaysTransitionsToDone() {
        for status in allStatuses {
            XCTAssertEqual(Transition.forEvent(status, event: .stop), .done, "Stop from \(status) should -> done")
        }
    }

    func testStopWithBackgroundWorkTransitionsToBackground() {
        for status in allStatuses {
            XCTAssertEqual(Transition.forEvent(status, event: .stopWithBackgroundWork), .background)
        }
    }

    func testStopFailureTransitionsToNeedsAttention() {
        for status in allStatuses {
            XCTAssertEqual(Transition.forEvent(status, event: .stopFailure), .needsAttention)
        }
    }

    func testBlockingToolsAndElicitationWaitForInput() {
        XCTAssertEqual(Transition.forEvent(.working, event: .awaitingUserAnswer), .waitingInput)
        XCTAssertEqual(Transition.forEvent(.working, event: .notificationElicitation), .waitingInput)
        XCTAssertEqual(Transition.forEvent(.done, event: .notificationElicitation), .waitingInput)
    }

    // MARK: - Transition.forEvent() — SessionStart always idles

    func testSessionStartAlwaysTransitionsToIdle() {
        for status in allStatuses {
            XCTAssertEqual(Transition.forEvent(status, event: .sessionStart), .idle, "SessionStart from \(status) should -> idle")
        }
    }

    // MARK: - Transition.forEvent() — Working transitions

    func testUserPromptSubmitTransitionsToWorking() {
        XCTAssertEqual(Transition.forEvent(.idle, event: .userPromptSubmit), .working)
        XCTAssertEqual(Transition.forEvent(.waitingInput, event: .userPromptSubmit), .working)
    }

    func testPreToolUseTransitionsToWorking() {
        XCTAssertEqual(Transition.forEvent(.working, event: .preToolUse), .working)
        XCTAssertEqual(Transition.forEvent(.idle, event: .preToolUse), .working)
    }

    func testPostToolUseTransitionsToWorking() {
        XCTAssertEqual(Transition.forEvent(.working, event: .postToolUse), .working)
    }

    func testPostToolUseFailureTransitionsToWorking() {
        XCTAssertEqual(Transition.forEvent(.working, event: .postToolUseFailure), .working)
        XCTAssertEqual(Transition.forEvent(.idle, event: .postToolUseFailure), .working)
    }

    // MARK: - Transition.forEvent() — Notification transitions

    func testNotificationIdleOnlyRescuesATurnWithoutStop() {
        // idle_prompt follows a finished turn by ~60s; it must not re-flag or re-notify it.
        XCTAssertEqual(Transition.forEvent(.working, event: .notificationIdle), .done)
        XCTAssertEqual(Transition.forEvent(.compacting, event: .notificationIdle), .done)
        for status: SessionStatus in [.idle, .done, .background, .waitingInput, .waitingPermission, .needsAttention] {
            XCTAssertNil(Transition.forEvent(status, event: .notificationIdle), "\(status)")
        }
    }

    func testNotificationPermissionPreservesStatus() {
        // PermissionRequest handles the transition; Notification fires ~6s later and would race with PostToolUse.
        XCTAssertNil(Transition.forEvent(.working, event: .notificationPermission))
        XCTAssertNil(Transition.forEvent(.waitingPermission, event: .notificationPermission))
    }

    func testPermissionRequestTransitionsToWaitingPermission() {
        XCTAssertEqual(Transition.forEvent(.working, event: .permissionRequest), .waitingPermission)
        XCTAssertEqual(Transition.forEvent(.idle, event: .permissionRequest), .waitingPermission)
    }

    func testPreCompactTransitionsToCompacting() {
        XCTAssertEqual(Transition.forEvent(.working, event: .preCompact), .compacting)
    }

    func testPostCompactTransitionsToIdle() {
        XCTAssertEqual(Transition.forEvent(.compacting, event: .postCompact), .idle)
        XCTAssertEqual(Transition.forEvent(.working, event: .postCompact), .idle)
    }

    func testSessionErrorTransitionsToNeedsAttention() {
        XCTAssertEqual(Transition.forEvent(.working, event: .sessionError), .needsAttention)
        XCTAssertEqual(Transition.forEvent(.idle, event: .sessionError), .needsAttention)
    }

    // MARK: - Transition.forEvent() — Preserve status (nil return)

    func testNotificationOtherPreservesStatus() {
        XCTAssertNil(Transition.forEvent(.working, event: .notificationOther))
        XCTAssertNil(Transition.forEvent(.idle, event: .notificationOther))
    }

    func testSessionEndPreservesStatus() {
        XCTAssertNil(Transition.forEvent(.working, event: .sessionEnd))
        XCTAssertNil(Transition.forEvent(.idle, event: .sessionEnd))
    }

    func testUnknownEventPreservesStatus() {
        XCTAssertNil(Transition.forEvent(.working, event: .unknown))
        XCTAssertNil(Transition.forEvent(.idle, event: .unknown))
    }

    // MARK: - Transition.clearsInactiveMarkers()

    func testSubagentHooksDoNotClearInactiveMarkers() {
        XCTAssertFalse(Transition.clearsInactiveMarkers(event: .subagentStart))
        XCTAssertFalse(Transition.clearsInactiveMarkers(event: .subagentStop))
    }

    // MARK: - Exhaustive transition test

    func testAllTransitionsExhaustive() {
        let allEvents: [HookEvent] = [
            .sessionStart, .userPromptSubmit, .preToolUse, .awaitingUserAnswer, .postToolUse,
            .postToolUseFailure, .stop, .stopWithBackgroundWork, .stopFailure, .notificationIdle,
            .notificationElicitation, .notificationPermission, .notificationOther,
            .permissionRequest, .subagentStart, .subagentStop, .preCompact, .postCompact,
            .sessionError, .sessionEnd, .unknown
        ]

        // Every event x status combination should not crash
        for status in allStatuses {
            for event in allEvents {
                // Just verify it doesn't crash — specific values tested above
                _ = Transition.forEvent(status, event: event)
            }
        }

        // Verify expected transition counts:
        // Events that always transition (non-nil): sessionStart, userPromptSubmit, preToolUse,
        //   postToolUse, postToolUseFailure, stop variants, permissionRequest, preCompact
        // notificationIdle depends on the current status (covered above).
        // Events that always preserve (nil): notificationPermission, notificationOther, sessionEnd, unknown
        for status in allStatuses {
            XCTAssertNotNil(Transition.forEvent(status, event: .sessionStart))
            XCTAssertNotNil(Transition.forEvent(status, event: .userPromptSubmit))
            XCTAssertNotNil(Transition.forEvent(status, event: .preToolUse))
            XCTAssertNotNil(Transition.forEvent(status, event: .postToolUse))
            XCTAssertNotNil(Transition.forEvent(status, event: .postToolUseFailure))
            XCTAssertNotNil(Transition.forEvent(status, event: .stop))
            XCTAssertNotNil(Transition.forEvent(status, event: .stopWithBackgroundWork))
            XCTAssertNotNil(Transition.forEvent(status, event: .stopFailure))
            XCTAssertNotNil(Transition.forEvent(status, event: .awaitingUserAnswer))
            XCTAssertNotNil(Transition.forEvent(status, event: .notificationElicitation))
            XCTAssertNotNil(Transition.forEvent(status, event: .permissionRequest))
            XCTAssertNotNil(Transition.forEvent(status, event: .preCompact))
            XCTAssertNotNil(Transition.forEvent(status, event: .postCompact))
            XCTAssertNotNil(Transition.forEvent(status, event: .sessionError))
            XCTAssertNil(Transition.forEvent(status, event: .notificationPermission))
            XCTAssertNil(Transition.forEvent(status, event: .notificationOther))
            XCTAssertNil(Transition.forEvent(status, event: .subagentStart))
            XCTAssertNil(Transition.forEvent(status, event: .subagentStop))
            XCTAssertNil(Transition.forEvent(status, event: .sessionEnd))
            XCTAssertNil(Transition.forEvent(status, event: .unknown))
        }
    }

    // MARK: - sanitizeSessionId

    func testSanitizeRemovesForwardSlash() {
        XCTAssertEqual(SessionData.sanitizeSessionId(raw: "foo/bar"), "foobar")
    }

    func testSanitizeRemovesBackslash() {
        XCTAssertEqual(SessionData.sanitizeSessionId(raw: "foo\\bar"), "foobar")
    }

    func testSanitizeRemovesDoubleDot() {
        XCTAssertEqual(SessionData.sanitizeSessionId(raw: "../../.bashrc"), "bashrc")
    }

    func testSanitizePathTraversal() {
        XCTAssertEqual(SessionData.sanitizeSessionId(raw: "../etc/passwd"), "etcpasswd")
    }

    func testSanitizeDoubleDotOnly() {
        XCTAssertEqual(SessionData.sanitizeSessionId(raw: ".."), "")
    }

    func testSanitizeCapsLength() {
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(SessionData.sanitizeSessionId(raw: long).count, 64)
    }

    func testSanitizeNormalIdUnchanged() {
        XCTAssertEqual(SessionData.sanitizeSessionId(raw: "abc-123-def"), "abc-123-def")
    }

    func testSanitizeUUIDUnchanged() {
        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        XCTAssertEqual(SessionData.sanitizeSessionId(raw: uuid), uuid)
    }
}
