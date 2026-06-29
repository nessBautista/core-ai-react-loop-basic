//  OpenRouterPolicy.swift
//  core-ai-react-loop-basic
//
//  A cloud policy π: it conforms to `Policy` (one `decide` → one `Decision`),
//  backed by a hosted OpenRouter model. The loop, tool, state, and UI don't
//  change at all; only this conformer does.
//
//  Same Era II shape: we ask for STRUCTURED output (response_format json_schema)
//  and decode it into our Decision — no regex, no free-text parsing.

import Foundation

enum PolicyError: LocalizedError {
    case missingAPIKey(String)
    case http(status: Int, body: String)
    case emptyResponse
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let name):
            return "Environment variable \(name) is not set. Add it to the Run scheme " +
                   "(Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables)."
        case .http(let status, let body):
            return "OpenRouter HTTP \(status): \(body)"
        case .emptyResponse:
            return "OpenRouter returned no choices."
        case .unknownAction(let raw):
            return "Model returned an unknown action: '\(raw)'."
        }
    }
}

struct OpenRouterPolicy: Policy {
    let apiKey: String
    let model: String
    let session: URLSession

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    /// Build from the `OPENROUTER_API_KEY` environment variable (set in the Run
    /// scheme). `model` is the OpenRouter model id, e.g. "openai/gpt-4o-mini".
    static func fromEnvironment(model: String, session: URLSession = .shared) throws -> OpenRouterPolicy {
        let name = "OPENROUTER_API_KEY"
        guard let key = ProcessInfo.processInfo.environment[name], !key.isEmpty else {
            throw PolicyError.missingAPIKey(name)
        }
        return OpenRouterPolicy(apiKey: key, model: model, session: session)
    }

    // MARK: - Policy

    func decide(_ state: ReActState) async throws -> Decision {
        let userMessage = Self.userMessage(for: state)

        print("🧩 [OpenRouter] step \(state.stepCount): asking \(model)…")
        print("———— prompt ————\n\(userMessage)\n————————————————")

        let start = Date()
        let content = try await complete(system: Self.systemPrompt, user: userMessage)
        let elapsed = Date().timeIntervalSince(start)

        let decision = try Self.decode(content)
        print(String(format: "✅ [OpenRouter] step %d: %.1fs → thought=%@ | action=%@[%@]",
                     state.stepCount, elapsed, decision.thought,
                     decision.action.kind.rawValue, decision.action.argument))
        return decision
    }

    // MARK: - HTTP (POST /chat/completions with json_schema structured output)

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Returns the model's message content — a JSON string matching our schema.
    private func complete(system: String, user: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0,
            "response_format": Self.responseFormat,
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("core-ai-react-loop-basic", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            throw PolicyError.http(status: http.statusCode,
                                   body: String(data: data, encoding: .utf8) ?? "<non-utf8>")
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw PolicyError.emptyResponse
        }
        return content
    }

    /// The json_schema enforcing our Decision shape: thought first, a constrained
    /// action_type, and the argument. `strict` makes the model conform exactly.
    private static let responseFormat: [String: Any] = [
        "type": "json_schema",
        "json_schema": [
            "name": "react_decision",
            "strict": true,
            "schema": [
                "type": "object",
                "properties": [
                    "thought": [
                        "type": "string",
                        "description": "Your brief reasoning about what you know so far and what to do next.",
                    ],
                    "action_type": [
                        "type": "string",
                        "enum": ["search", "lookup", "finish"],
                        "description": "The single action to take next.",
                    ],
                    "argument": [
                        "type": "string",
                        "description": "The action's argument: a search query, a lookup string, or — for finish — the final answer.",
                    ],
                ],
                "required": ["thought", "action_type", "argument"],
                "additionalProperties": false,
            ],
        ],
    ]

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        let choices: [Choice]
    }

    // MARK: - Decode the JSON content into our Decision

    private struct DecisionDTO: Decodable {
        let thought: String
        let action_type: String
        let argument: String
    }

    private static func decode(_ jsonContent: String) throws -> Decision {
        let dto = try JSONDecoder().decode(DecisionDTO.self, from: Data(jsonContent.utf8))
        guard let kind = ActionKind(rawValue: dto.action_type) else {
            throw PolicyError.unknownAction(dto.action_type)
        }
        return Decision(thought: dto.thought, action: Action(kind: kind, argument: dto.argument))
    }

    // MARK: - Prompt building (the context cₜ)

    static let systemPrompt = """
    You are a ReAct agent that answers questions by interleaving Thought and Action steps, \
    observing the result of each action before continuing.

    Each turn, produce a thought (your reasoning about what you know so far and what to do \
    next) and exactly one action.

    Available actions:
    - search: search the web for information about a query.
    - lookup: find more detail about a string within the most recent search result.
    - finish: give a concise final answer (a sentence or two) and stop.

    Guidelines:
    - Begin by reasoning about how to break down the question.
    - Ground every claim in what you actually observed — do not invent facts.
    - As soon as you can answer reasonably, finish. You don't need exhaustive detail.
    """

    static func userMessage(for state: ReActState) -> String {
        var text = "Question: \(state.query)"
        let transcript = state.trajectory.map(transcriptLine).joined(separator: "\n")
        if !transcript.isEmpty {
            text += "\n\n\(transcript)"
        }
        text += "\n\nWhat is your next thought and action?"
        return text
    }

    private static func transcriptLine(_ step: Step) -> String {
        switch step {
        case .thought(let t):     return "Thought: \(t)"
        case .action(let a):      return "Action: \(a.kind.rawValue)[\(a.argument)]"
        case .observation(let o): return "Observation: \(o)"
        }
    }
}
