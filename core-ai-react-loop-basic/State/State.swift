//  State.swift
//  core-ai-react-loop-basic
//
//  The "memory + termination" half of the ReAct vocabulary: the trajectory
//  (invariants 2 & 3) and the agent state (invariant 4). The trajectory *is* the
//  agent's memory, and everything the loop needs concentrates into ReActState.
//
//  Pure Swift — no model, no I/O. The action space and the per-turn Decision
//  (invariant 1) live in Actions.swift.

import Foundation

// MARK: - Trajectory (invariants 2 & 3)

/// One entry in the trajectory. A single ordered list of these *is* the agent's
/// memory — and re-feeding the whole list each turn is what keeps reasoning
/// grounded (invariant 3).
///
/// A `thought` is a language action that produces **no** observation (invariant
/// 2); only `search`/`lookup` actions do.
enum Step: Sendable, Equatable {
    case thought(String)
    case action(Action)
    case observation(String)
}



// MARK: - State (invariant 4)

/// The complete agent state: the question, the trajectory (its memory), how many
/// cycles we've taken, the budget, and the final answer once `finish` fires.
///
/// `isFinished` is *derived*, never stored — the loop's exit condition lives in
/// exactly one place.
struct ReActState: Sendable {
    /// The immutable question being answered.
    let query: String

    /// The interleaved thought / action / observation history — re-fed into the
    /// prompt every cycle.
    var trajectory: [Step]

    /// Reasoning cycles taken so far.
    var stepCount: Int

    /// The budget — the only thing that stops a loop whose model never emits
    /// `finish`. Kept modest here: this model's context window is 4096 tokens, and
    /// we re-feed the whole trajectory each turn, so long runs hit the ceiling.
    let maxSteps: Int

    /// The answer carried by the `finish` action; `nil` while the loop runs.
    var finalAnswer: String?

    init(query: String, maxSteps: Int = 8) {
        self.query = query
        self.trajectory = []
        self.stepCount = 0
        self.maxSteps = maxSteps
        self.finalAnswer = nil
    }

    /// Done when `finish` has fired (we have an answer) or the budget is spent.
    var isFinished: Bool {
        finalAnswer != nil || stepCount >= maxSteps
    }
}
