import SwiftUI

struct ConfigurationPanel: View {
    @Bindable var model: RecoveryViewModel

    var body: some View {
        DashboardCard(title: "2. Search configuration", systemImage: "slider.horizontal.3") {
            Picker("Recovery method", selection: methodBinding) {
                Text("Wordlist").tag(Method.wordlist)
                Text("Brute Force").tag(Method.bruteForce)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch model.configuration.method {
            case .wordlist(let url): wordlistControls(url: url)
            case .bruteForce(let characters, let minimum, let maximum):
                bruteForceControls(characters: characters, minimum: minimum, maximum: maximum)
            }

            HStack {
                searchSpaceSummary
                Spacer()
                Button("Start Recovery", action: model.start)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!model.canStart)
            }
        }
        .disabled(model.configurationIsBusy)
    }

    private func wordlistControls(url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: url.path.isEmpty ? "doc.text.magnifyingglass" : "doc.text.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.path.isEmpty ? "No wordlist selected" : url.lastPathComponent)
                    .fontWeight(.medium)
                Text(url.path.isEmpty ? "Choose a UTF-8 text file with one candidate per line." : url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Choose Wordlist…") {
                if let selected = FileSelectionService.chooseWordlist() {
                    model.configuration.method = .wordlist(selected)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: .rect(cornerRadius: 10))
    }

    private func bruteForceControls(characters: String, minimum: Int, maximum: Int) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
            GridRow {
                Text("Character set")
                TextField("Characters to test", text: charactersBinding)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel("Brute force character set")
            }
            GridRow {
                Text("Password length")
                HStack {
                    Stepper("Minimum: \(minimum)", value: minimumBinding, in: 1...32)
                    Divider().frame(height: 18)
                    Stepper("Maximum: \(maximum)", value: maximumBinding, in: minimum...32)
                }
            }
        }
    }

    @ViewBuilder private var searchSpaceSummary: some View {
        if let total = try? model.configuration.totalCandidates {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ProgressPresentation.formatCount(total)) candidates")
                    .font(.subheadline.weight(.semibold))
                if total > 1_000_000_000 {
                    Label("Very large search — narrow the character set or length range.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Bounded search space")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Candidate count is calculated when recovery starts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var methodBinding: Binding<Method> {
        Binding {
            if case .wordlist = model.configuration.method { return .wordlist }
            return .bruteForce
        } set: { method in
            switch method {
            case .wordlist:
                model.configuration.method = .wordlist(URL(fileURLWithPath: ""))
            case .bruteForce:
                model.configuration.method = .bruteForce(
                    characterSet: "abcdefghijklmnopqrstuvwxyz0123456789",
                    minimumLength: 1,
                    maximumLength: 6
                )
            }
        }
    }

    private var charactersBinding: Binding<String> {
        Binding {
            guard case .bruteForce(let value, _, _) = model.configuration.method else { return "" }
            return value
        } set: { value in
            guard case .bruteForce(_, let minimum, let maximum) = model.configuration.method else { return }
            model.configuration.method = .bruteForce(characterSet: value, minimumLength: minimum, maximumLength: maximum)
        }
    }

    private var minimumBinding: Binding<Int> {
        Binding {
            guard case .bruteForce(_, let value, _) = model.configuration.method else { return 1 }
            return value
        } set: { value in
            guard case .bruteForce(let characters, _, let maximum) = model.configuration.method else { return }
            model.configuration.method = .bruteForce(characterSet: characters, minimumLength: value, maximumLength: max(value, maximum))
        }
    }

    private var maximumBinding: Binding<Int> {
        Binding {
            guard case .bruteForce(_, _, let value) = model.configuration.method else { return 1 }
            return value
        } set: { value in
            guard case .bruteForce(let characters, let minimum, _) = model.configuration.method else { return }
            model.configuration.method = .bruteForce(characterSet: characters, minimumLength: minimum, maximumLength: value)
        }
    }

    private enum Method: Hashable { case wordlist, bruteForce }
}

private extension RecoveryViewModel {
    var canStart: Bool {
        guard case .ready = state else { return false }
        return (try? configuration.validate()) != nil
    }

    var configurationIsBusy: Bool {
        switch state {
        case .recovering, .paused, .decrypting: true
        default: false
        }
    }
}
