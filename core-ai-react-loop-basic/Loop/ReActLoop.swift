//  ReActLoop.swift
//  core-ai-react-loop-basic
//
//  The loop itself — the verb that drives the nouns in State.swift. This is the
//  whole idea of ReAct in one place: think → act → observe → re-feed, repeat
//  until done.
//
//  It is deliberately ignorant of *how* decisions are made (that's the Policy)
//  and *how* the world is reached (that's the Tool). It only orchestrates the
//  four invariants:
//
//    1. augmented action space — the Policy may return a thought or an action
//    2. a thought yields no observation — only search/lookup append one
//    3. the whole trajectory is re-fed — the Policy reads the growing state each turn
//    4. terminate — the `while !state.isFinished` condition

/// Drives a ReAct episode: given a question, run the policy/tool cycle until the
/// agent finishes or runs out of budget.
struct ReActLoop {
    /// The decision rule — the paper's π. Swappable: scripted stub now, a real
    /// model later. The loop never changes, only this does.
    let policy: any Policy

    /// The environment — turns search/lookup actions into observations.
    let tool: any Tool

    /// Run one episode to completion.
    ///
    /// - Parameters:
    ///   - query: the question to answer.
    ///   - maxSteps: the cycle budget (the only thing that stops a loop whose
    ///     model never emits `finish`).
    ///   - onStep: optional hook fired as each `Step` is appended — handy for
    ///     printing a headless run, or driving a live UI.
    /// - Returns: the final state. `finalAnswer` is set if the agent finished;
    ///   it stays `nil` if the budget ran out first.
    func run(
        query: String,
        maxSteps: Int = 8,
        onStep: ((Step) -> Void)? = nil
    ) async throws -> ReActState {
        var state = ReActState(query: query, maxSteps: maxSteps)

        while !state.isFinished {
            // The policy reads the whole state (the context cₜ) and returns the
            // next thought + action (invariant 3: it sees the full trajectory).
            let decision = try await policy.decide(state)

            // Record the thought, then the action. A thought produces no
            // observation (invariant 2) — it just grows the context.
            append(.thought(decision.thought), to: &state, onStep)
            append(.action(decision.action), to: &state, onStep)

            switch decision.action.kind {
            case .finish:
                // Termination (invariant 4): carry the answer out and stop.
                state.finalAnswer = decision.action.argument

            case .search, .lookup:
                // Reach the world, observe the result, feed it back in.
                let observation = try await tool.run(decision.action)
                append(.observation(observation), to: &state, onStep)
            }

            state.stepCount += 1
        }

        return state
    }

    /// Append one step to the trajectory and notify the observer.
    private func append(_ step: Step, to state: inout ReActState, _ onStep: ((Step) -> Void)?) {
        state.trajectory.append(step)
        onStep?(step)
    }
}
