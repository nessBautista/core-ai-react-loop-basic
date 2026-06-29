//  ReActViewModel.swift
//  core-ai-react-loop-basic
//
//  The bridge between the loop and the UI. It runs the ReAct loop for a question
//  and exposes the trajectory as it grows so the screen can show the agent
//  thinking step by step.
//
//  It's backed by OpenRouter (cloud): only the Policy implementation differs;
//  the loop, tool, state, and UI are untouched by which model runs.
//
//  The live updates come from the loop's `onStep` hook. One wrinkle: the loop
//  isn't main-actor-isolated, so `onStep` can fire off the main thread (after the
//  tool's network await). We funnel every step through an AsyncStream and drain
//  it on the main actor — that keeps UI mutations on main AND preserves order.

import Foundation
import Observation

@MainActor
@Observable
final class ReActViewModel {

    enum Phase: Equatable {
        case ready
        case running
        case done
        case failed(String)
    }

    var phase: Phase = .ready
    var question: String = "What is the tallest mountain on Earth?"
    var steps: [Step] = []
    var answer: String?

    // Any OpenRouter model id works here; swap it without touching anything else.
    private let modelID = "google/gemma-3-27b-it"

    /// Run one ReAct episode for the current question, streaming steps to the UI.
    func ask() async {
        steps = []
        answer = nil
        phase = .running

        do {
            print("🚀 [vm] ask: \(question)")
            let policy = try OpenRouterPolicy.fromEnvironment(model: modelID)
            let tool = try TavilyTool.fromEnvironment()
            let loop = ReActLoop(policy: policy, tool: tool)

            // Drain the loop's steps on the main actor, in order.
            let (stream, continuation) = AsyncStream<Step>.makeStream()
            let consumer = Task { @MainActor in
                for await step in stream { steps.append(step) }
            }

            let final = try await loop.run(query: question) { step in
                print("📿 [loop] \(render(step))")   // console mirror of the trajectory
                continuation.yield(step)             // safe from any thread; ordered
            }
            continuation.finish()
            await consumer.value              // ensure all steps are drained

            print("🏁 [vm] done — steps=\(final.stepCount), answer=\(final.finalAnswer ?? "nil")")
            answer = final.finalAnswer ?? "(no answer — the step budget ran out)"
            phase = .done
        } catch {
            print("❌ [vm] failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }
}
