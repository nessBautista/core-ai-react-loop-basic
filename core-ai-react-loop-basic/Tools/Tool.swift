//  Tool.swift
//  core-ai-react-loop-basic
//
//  The environment seam — the thing that turns a world-action into an
//  observation. In the paper's terms, this is what produces oₜ from aₜ.
//
//  Only `search` / `lookup` actions reach a tool; a `thought` never does (it
//  yields no observation, invariant 2) and `finish` is the loop's exit, not a
//  tool call. So a Tool only ever has to handle the world-actions.
//
//  Note: this is *our* loop running the tool (Era II — structured output, we
//  decode the action and dispatch it ourselves). It is unrelated to Foundation
//  Models' own `Tool` protocol.

/// Runs a world-action against the outside world and returns the observation.
/// Async + throwing because a real tool does I/O (a web search, a file read)
/// that may suspend and may fail.
protocol Tool {
    func run(_ action: Action) async throws -> String
}
