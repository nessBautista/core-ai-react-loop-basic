import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ReActView()
        }
    }
}

struct ReActView: View {
    @State private var vm = ReActViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch vm.phase {
                case .failed(let message):
                    ContentUnavailableView("Something went wrong", systemImage: "exclamationmark.triangle", description: Text(message))
                default:
                    loop
                }
            }
            .padding()
            .navigationTitle("ReAct loop")
        }
    }

    private var loop: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Question + Ask
            HStack {
                TextField("Ask a question", text: $vm.question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { ask() }
                Button("Ask", action: ask)
                    .disabled(vm.phase == .running || vm.question.isEmpty)
            }

            // Live trajectory — the agent thinking, step by step
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(vm.steps.enumerated()), id: \.offset) { _, step in
                        StepRow(step: step)
                    }
                }
            }

            if vm.phase == .running {
                HStack(spacing: 8) { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
            }

            // Final answer
            if let answer = vm.answer {
                Divider()
                Text("Answer").font(.headline)
                Text(answer).font(.body)
            }
        }
    }

    private func ask() {
        Task { await vm.ask() }
    }
}

/// One trajectory step, color-coded by kind so the think → act → observe rhythm
/// is visible at a glance.
struct StepRow: View {
    let step: Step

    var body: some View {
        switch step {
        case .thought(let text):
            row("Thought", text, .purple)
        case .action(let action):
            row("Action", "\(action.kind.rawValue)[\(action.argument)]", .blue)
        case .observation(let text):
            row("Observation", text, .green)
        }
    }

    private func row(_ title: String, _ body: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).bold().foregroundStyle(color)
            Text(body).font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    ReActView()
}
