//  Actions.swift
//  core-ai-react-loop-basic
//
//  The "what the agent can do" half of the ReAct vocabulary: the augmented
//  action space (invariant 1) and the per-turn Decision that pairs a thought
//  with the next action.
//
//  Pure Swift — no model, no I/O — so the loop's logic can be reasoned about
//  (and tested) on its own. The other half — the trajectory and agent state
//  (invariants 2–4) — lives in State.swift.

import Foundation

// MARK: - Action space (invariant 1)

/// The augmented action space: the three things the agent can *do*. The language
/// action (a "thought") is not here — it lives in `Step.thought` (in State.swift),
/// because a thought is reasoning, not an action against the world.
///
/// - `search` / `lookup` reach out and return an observation.
/// - `finish` is not a tool: it's the loop's exit, carrying the final answer.
///
/// String-backed so it round-trips cleanly through the model's structured output.
enum ActionKind: String, CaseIterable, Sendable, Equatable {
    case search
    case lookup
    case finish
}

/// One concrete action: what to do, plus the single string argument the action
/// space uses — `search[query]`, `lookup[string]`, `finish[answer]`.
struct Action: Sendable, Equatable {
    let kind: ActionKind
    let argument: String
}

// MARK: - Decision (one reasoning cycle)

/// The output of one reasoning turn. We generate the thought and the next action
/// *together* in a single structured call — the thought is required first, so the
/// model reasons before it commits to an action.
struct Decision: Sendable, Equatable {
    let thought: String
    let action: Action
}
