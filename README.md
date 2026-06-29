# core-ai-react-loop-basic

A small, native-Swift implementation of the **ReAct loop** (Reason + Act), built from
scratch with no agent framework. It runs a language model in a think → act → observe
loop to answer a question, and streams the trajectory live in a SwiftUI screen.

Companion code for the blog post *The ReAct Loop, in Native Swift*.

## Layout

- **`State/`** — the core value types: the action space (`ActionKind`, `Action`), the
  per-turn `Decision`, and the trajectory + agent state (`Step`, `ReActState`).
- **`Loop/`** — the `Policy` protocol (the decision rule, the paper's π), the
  `ReActLoop` itself, and `OpenRouterPolicy` (a cloud-model conformer that uses
  structured output).
- **`Tools/`** — the `Tool` protocol (the environment) and `TavilyTool` (web search).
- **`Fixtures/`** — `ScriptedPolicy` and `CannedTool` for deterministic, network-free
  tests.
- **`ViewModels/` + `ReActView.swift`** — the SwiftUI screen that streams the
  trajectory as the loop runs.
- **`core-ai-react-loop-basicTests/`** — unit tests that pin the loop's four
  invariants, with no model or network required.

## Setup

The app calls two services and reads their keys from the environment, so no key ever
lives in source:

| Variable | Where to get it |
|---|---|
| `OPENROUTER_API_KEY` | https://openrouter.ai |
| `TAVILY_API_KEY` | https://tavily.com |

In Xcode, set both under **Product → Scheme → Edit Scheme → Run → Arguments →
Environment Variables**.

> **Note:** this repository ships the Swift source only — there is no `.xcodeproj`.
> Create a SwiftUI iOS App target and add these files (or drop them into your own
> project). The `.gitignore` deliberately excludes the Xcode project and schemes,
> because Xcode stores the API keys above *inside the scheme file* in plaintext —
> keep them out of version control.

## Running it

Ask a question (the default is *"What is the tallest mountain on Earth?"*) and watch the
agent think, search, read the result, and finish — step by step, in the UI.

The same loop can run a model fully on-device with Apple's Core AI; that's the subject
of a follow-up post.
