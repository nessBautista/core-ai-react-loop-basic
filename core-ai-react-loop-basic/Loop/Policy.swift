//  Policy.swift
//  core-ai-react-loop-basic
//
//  The policy seam — the paper's π(aₜ | cₜ).
//
//  In ReAct the policy is the agent's decision rule: given the context so far,
//  decide what to do next. The context cₜ is our trajectory (inside ReActState),
//  and "what to do next" is a Decision (a thought + the next action).
//
//  This is the one seam the rest of the loop is built around: the loop never
//  changes, only the policy does. A cloud model (OpenRouterPolicy) conforms to
//  this, and a scripted stub conforms to it too so the loop can be tested
//  headless, with no model at all.

/// The agent's decision rule — the paper's policy π(aₜ | cₜ).
///
/// Given the current state (which carries the trajectory, i.e. the context cₜ),
/// produce the next `Decision`. Async + throwing because the real implementation
/// runs a language model: it may suspend, and it may fail.
protocol Policy {
    func decide(_ state: ReActState) async throws -> Decision
}
