import SwiftUI

enum AppLayout {
    static let pagePadding: CGFloat = 32
    static let panelPadding: CGFloat = 24
}

struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    let actions: Actions

    init(_ title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.largeTitle.bold())
                if let subtitle {
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PageHeader where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

struct LogView: View {
    @Binding var text: String
    @Binding var search: String
    let refresh: () async -> Void
    @State private var paused = false

    var body: some View {
        VStack {
            HStack {
                TextField("Search logs", text: $search)
                Toggle("Pause", isOn: $paused).toggleStyle(.button)
                Button("Clear") { text = "" }
                Button("Reload") { Task { await refresh() } }
            }
            ScrollView([.horizontal, .vertical]) {
                Text(filteredText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var filteredText: String {
        guard !search.isEmpty else { return text }
        return text
            .split(separator: "\n")
            .filter { $0.localizedCaseInsensitiveContains(search) }
            .joined(separator: "\n")
    }
}

struct OperationRow: View {
    let operation: Operation

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading) {
                Text(operation.kind)
                Text(operation.command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(operation.status.rawValue.capitalized).font(.caption)
        }
        .padding(.horizontal, 8)
    }

    private var statusIcon: String {
        switch operation.status {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .running, .cancelled: "clock"
        }
    }

    private var statusColor: Color {
        switch operation.status {
        case .succeeded: .green
        case .failed: .red
        case .running, .cancelled: .orange
        }
    }
}
