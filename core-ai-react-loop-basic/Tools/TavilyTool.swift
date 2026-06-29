//  TavilyTool.swift
//  core-ai-react-loop-basic
//
//  The real environment — the only part (besides the model) that touches the
//  outside world. An action goes in, an observation comes out.
//
//  Tavily stands in for the paper's Wikipedia tool but keeps the SAME two verbs:
//    - search[query]  : web search → the lead sentences of the top results
//    - lookup[string] : the paper's Ctrl-F — the next sentence containing a
//                       string within the CURRENT search result
//
//  The sentence/cursor state is the tool's PRIVATE memory (kept out of ReActState
//  on purpose — it's the tool's, not the agent's). It's an `actor` because that
//  state is shared across calls within a run.
//
//  Errors are folded INTO the observation rather than thrown: a failed search the
//  model can see and recover from is more ReAct-faithful than a crash.

import Foundation

enum ToolError: LocalizedError {
    case missingAPIKey(String)
    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let name):
            return "Environment variable \(name) is not set. Add it to the Run scheme " +
                   "(Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables)."
        }
    }
}

actor TavilyTool: Tool {
    private let apiKey: String
    private let session: URLSession

    // The current result's sentences + the lookup resume position.
    private var sentences: [String] = []
    private var cursor: Int = 0

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Build a tool from the `TAVILY_API_KEY` environment variable (set in the
    /// Run scheme). Throws a clear error if it's missing.
    static func fromEnvironment(session: URLSession = .shared) throws -> TavilyTool {
        let name = "TAVILY_API_KEY"
        guard let key = ProcessInfo.processInfo.environment[name], !key.isEmpty else {
            throw ToolError.missingAPIKey(name)
        }
        return TavilyTool(apiKey: key, session: session)
    }

    // MARK: - Tool

    func run(_ action: Action) async throws -> String {
        switch action.kind {
        case .search: return await handleSearch(action.argument)
        case .lookup: return handleLookup(action.argument)
        case .finish: return ""   // never reached — the loop handles finish itself
        }
    }

    private func handleSearch(_ query: String) async -> String {
        print("🔎 [Tavily] search: \(query)")
        do {
            let found = try await fetch(query)
            print("🔎 [Tavily] got \(found.count) sentence(s)")
            guard !found.isEmpty else {
                sentences = []; cursor = 0
                return "No results found for '\(query)'."
            }
            sentences = found
            cursor = 0
            let summary = found.prefix(3).joined(separator: " ")
            return "Results for '\(query)': \(summary)"
        } catch {
            print("🔎 [Tavily] search error: \(error.localizedDescription)")
            return "Search error: \(error.localizedDescription)"
        }
    }

    private func handleLookup(_ needle: String) -> String {
        guard !sentences.isEmpty else {
            return "No search results to look up in — use search first."
        }
        let lower = needle.lowercased()
        var i = max(0, cursor)
        while i < sentences.count {
            if sentences[i].lowercased().contains(lower) {
                cursor = i + 1
                return sentences[i]
            }
            i += 1
        }
        return "No more occurrences of '\(needle)'."
    }

    // MARK: - HTTP (POST https://api.tavily.com/search)

    private static let searchURL = URL(string: "https://api.tavily.com/search")!

    private func fetch(_ query: String, maxResults: Int = 5) async throws -> [String] {
        let body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "search_depth": "advanced",
            "max_results": maxResults,
        ]
        var request = URLRequest(url: Self.searchURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw NSError(domain: "Tavily", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(snippet)"])
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        let combined = decoded.results.prefix(3).compactMap(\.content).joined(separator: " ")
        return Self.splitSentences(combined)
    }

    private struct SearchResponse: Decodable {
        struct Result: Decodable { let content: String? }
        let results: [Result]
    }

    /// Break text after sentence-ending punctuation followed by whitespace/end —
    /// the working set for `lookup`. No regex, so it's portable and testable.
    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            if c == "." || c == "!" || c == "?" {
                let atEnd = i + 1 >= chars.count
                if atEnd || chars[i + 1].isWhitespace {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { sentences.append(trimmed) }
                    current = ""
                }
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }
}
