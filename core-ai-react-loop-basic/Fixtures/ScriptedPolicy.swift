//  ScriptedPolicy.swift
//  core-ai-react-loop-basic
//
//  Test fixtures for running the loop headless — no model, no network. The point
//  is to prove the control flow (think → act → observe → finish) is correct while
//  it's still trivial to debug, *before* we wire in a real model.

import Foundation

// MARK: - A policy that just replays canned decisions

/// A `Policy` that returns pre-written decisions in order — one per turn. It
/// ignores the state entirely except to index by `stepCount`. This stands in for
/// the real model so the loop can be exercised deterministically.
struct ScriptedPolicy: Policy {
    let script: [Decision]

    func decide(_ state: ReActState) async throws -> Decision {
        // If the script runs out, finish defensively so the loop can't spin.
        guard state.stepCount < script.count else {
            return Decision(
                thought: "Script exhausted — finishing.",
                action: Action(kind: .finish, argument: "")
            )
        }
        return script[state.stepCount]
    }
}

// MARK: - A tool that returns canned observations

/// A `Tool` that fabricates an observation instead of hitting the network — just
/// enough for the loop to have something to feed back in.
struct CannedTool: Tool {
    func run(_ action: Action) async throws -> String {
        switch action.kind {
        case .search: return "Search result for \"\(action.argument)\""
        case .lookup: return "Lookup of \"\(action.argument)\""
        case .finish: return ""   // never reached — the loop handles finish itself
        }
    }
}

// MARK: - Pretty-print a step in the paper's transcript shape

/// Render one step as `Thought:` / `Action: kind[arg]` / `Observation:` — the
/// canonical ReAct transcript line. Useful for watching a headless run.
func render(_ step: Step) -> String {
    switch step {
    case .thought(let text):     return "Thought: \(text)"
    case .action(let action):    return "Action: \(action.kind.rawValue)[\(action.argument)]"
    case .observation(let text): return "Observation: \(text)"
    }
}
