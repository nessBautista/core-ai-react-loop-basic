//  ReActLoopTests.swift
//  core-ai-react-loop-basicTests
//
//  Headless proof that the loop's control flow is correct — no model, no
//  network. We reuse ScriptedPolicy + CannedTool from the app target to drive
//  the loop deterministically, then assert the trajectory, the answer, and the
//  termination behavior. If these pass, any later weirdness is the model, not
//  the loop.

import Testing
@testable import core_ai_react_loop_basic

// Small helpers to count step kinds without repeating the `if case` dance.
private func thoughts(in t: [Step]) -> Int {
    t.filter { if case .thought = $0 { return true } else { return false } }.count
}
private func observations(in t: [Step]) -> Int {
    t.filter { if case .observation = $0 { return true } else { return false } }.count
}
private func worldActions(in t: [Step]) -> Int {
    t.filter { if case .action(let a) = $0 { return a.kind != .finish } else { return false } }.count
}

@Suite("ReAct loop control flow")
struct ReActLoopTests {

    @Test("search → finish: trajectory, answer, and step count are correct")
    func searchThenFinish() async throws {
        let script = [
            Decision(thought: "I'll look it up.",
                     action: Action(kind: .search, argument: "tallest mountain height")),
            Decision(thought: "Got it — answering.",
                     action: Action(kind: .finish, argument: "Mount Everest, ~8,849 m.")),
        ]
        let loop = ReActLoop(
            policy: ScriptedPolicy(script: script),
            tool: CannedTool()
        )
        let state = try await loop.run(query: "What is the tallest mountain?")
        #expect(state.finalAnswer == "Mount Everest, ~8,849 m.")
        #expect(state.stepCount == 2)
        // thought, action(search), observation, thought, action(finish)
        #expect(state.trajectory.count == 5)
    }

    @Test("a thought never produces an observation (invariant 2)")
    func thoughtsHaveNoObservation() async throws {
        let script = [
            Decision(thought: "search", action: Action(kind: .search, argument: "a")),
            Decision(thought: "lookup", action: Action(kind: .lookup, argument: "b")),
            Decision(thought: "done",   action: Action(kind: .finish, argument: "answer")),
        ]
        let loop = ReActLoop(policy: ScriptedPolicy(script: script), tool: CannedTool())

        let state = try await loop.run(query: "q")

        #expect(thoughts(in: state.trajectory) == 3)          // one per turn
        #expect(observations(in: state.trajectory) == 2)      // only search + lookup
        // exactly one observation per world-action; finish yields none
        #expect(observations(in: state.trajectory) == worldActions(in: state.trajectory))
    }

    @Test("budget stops a loop that never finishes (invariant 4)")
    func budgetStopsRunawayLoop() async throws {
        // All searches, never finishes — and longer than the budget.
        let script = Array(
            repeating: Decision(thought: "keep searching",
                                action: Action(kind: .search, argument: "x")),
            count: 5
        )
        let loop = ReActLoop(policy: ScriptedPolicy(script: script), tool: CannedTool())

        let state = try await loop.run(query: "q", maxSteps: 3)

        #expect(state.finalAnswer == nil)   // never reached finish
        #expect(state.stepCount == 3)       // stopped exactly at the budget
        #expect(state.isFinished)           // finished *because* the budget was spent
    }

    @Test("onStep fires for every appended step, in order")
    func onStepObservesEveryStep() async throws {
        let script = [
            Decision(thought: "t1", action: Action(kind: .search, argument: "a")),
            Decision(thought: "t2", action: Action(kind: .finish, argument: "done")),
        ]
        let loop = ReActLoop(policy: ScriptedPolicy(script: script), tool: CannedTool())

        var seen: [Step] = []
        let state = try await loop.run(query: "q") { seen.append($0) }

        #expect(seen == state.trajectory)   // same steps, same order
    }
}
