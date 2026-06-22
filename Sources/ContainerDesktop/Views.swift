import AppKit
import SwiftUI

enum AppLayout {
    static let pagePadding: CGFloat = 32
    static let panelPadding: CGFloat = 24
}

struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let actions: Actions

    init(_ title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.largeTitle.bold())
                if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
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

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard", containers = "Containers", images = "Images", builds = "Builds", settings = "Settings"
    var id: Self { self }
    var icon: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .containers: "shippingbox"
        case .images: "square.stack.3d.up"
        case .builds: "hammer"
        case .settings: "gear"
        }
    }
}

struct RootView: View {
    @ObservedObject var store: AppStore
    @State private var section: AppSection? = .dashboard

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()

            if section == .containers || section == .images {
                GeometryReader { geometry in
                    let columnWidth = max(340, (geometry.size.width - 1) / 2)
                    HStack(spacing: 0) {
                        Group {
                            switch section {
                            case .containers: ContainerListView(store: store)
                            case .images: ImageListView(store: store)
                            default: EmptyView()
                            }
                        }
                        .frame(width: columnWidth)
                        .frame(maxHeight: .infinity)

                        Divider()

                        Group {
                            switch section {
                            case .containers: ContainerDetailView(store: store)
                            case .images: ImageDetailView(store: store)
                            default: EmptyView()
                            }
                        }
                        .frame(width: columnWidth)
                        .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .ignoresSafeArea(.container, edges: .top)
            } else {
                Group {
                    switch section ?? .dashboard {
                    case .dashboard: DashboardView(store: store)
                    case .builds: BuildsView(store: store)
                    case .settings: SettingsView(store: store)
                    case .containers: ContainerListView(store: store)
                    case .images: ImageListView(store: store)
                    }
                }
                .ignoresSafeArea(.container, edges: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(AppSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Divider()
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.status.title)
                    if store.isStale { Text("Stale").foregroundStyle(.orange) }
                }
                .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 180)
        .background(.regularMaterial)
    }

    private var statusColor: Color {
        switch store.status { case .ready: .green; case .starting, .checking: .orange; default: .red }
    }
}

struct DashboardView: View {
    @ObservedObject var store: AppStore
    private let columns = [GridItem(.adaptive(minimum: 155))]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("Dashboard", subtitle: "Service health and local container activity")
                if case .missing = store.status { MissingCLIView() }
                else if case .serviceStopped = store.status {
                    GroupBox("Apple container service") {
                        HStack { Text("The service is stopped."); Spacer(); Button("Start Service") { store.startService() }.buttonStyle(.borderedProminent) }.padding(8)
                    }
                }
                LazyVGrid(columns: columns) {
                    MetricCard(title: "Running", value: "\(store.runningCount)", icon: "play.fill", color: .green)
                    MetricCard(title: "Stopped", value: "\(store.containers.count - store.runningCount)", icon: "stop.fill", color: .secondary)
                    MetricCard(title: "Images", value: "\(store.images.count)", icon: "square.stack.3d.up.fill", color: .blue)
                    MetricCard(title: "Operations", value: "\(store.operations.filter { $0.status == .running }.count)", icon: "arrow.triangle.2.circlepath", color: .orange)
                }
                GroupBox("Recent activity") {
                    if store.operations.isEmpty { ContentUnavailableView("No activity yet", systemImage: "clock") }
                    else { ForEach(store.operations.prefix(8)) { OperationRow(operation: $0) }.padding(.vertical, 4) }
                }
            }.padding(AppLayout.pagePadding)
        }
    }
}

struct MetricCard: View {
    let title: String, value: String, icon: String
    let color: Color
    var body: some View {
        GroupBox { HStack { Image(systemName: icon).font(.title).foregroundStyle(color); Spacer(); VStack(alignment: .trailing) { Text(value).font(.title.bold()); Text(title).foregroundStyle(.secondary) } }.padding(8) }
    }
}

struct MissingCLIView: View {
    var body: some View {
        GroupBox("Apple container is not installed") {
            HStack {
                Text("Install Apple’s signed package, then return here and refresh.")
                Spacer()
                Link("Open Releases", destination: URL(string: "https://github.com/apple/container/releases/latest")!)
                    .buttonStyle(.borderedProminent)
            }.padding(8)
        }
    }
}

struct ContainerListView: View {
    @ObservedObject var store: AppStore
    @State private var showRun = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("Containers", subtitle: "Running and stopped containers") {
                Button("Run", systemImage: "plus") { showRun = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(AppLayout.panelPadding)
            Divider()
            List(store.containers, selection: $store.selectedContainerID) { container in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Circle().fill(container.isRunning ? .green : .secondary).frame(width: 8, height: 8); Text(container.name.isEmpty ? container.id : container.name).fontWeight(.medium) }
                    Text(container.image).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets(top: 8, leading: AppLayout.panelPadding, bottom: 8, trailing: AppLayout.panelPadding))
                .tag(container.id)
            }
            .listStyle(.plain)
            .overlay { if store.containers.isEmpty { ContentUnavailableView("No containers", systemImage: "shippingbox", description: Text("Run an image to create your first container.")) } }
        }
        .sheet(isPresented: $showRun) { RunContainerView(store: store) }
    }
}

struct ContainerDetailView: View {
    @ObservedObject var store: AppStore
    @State private var logs = ""
    @State private var inspect = ""
    @State private var search = ""
    @State private var tab = "Overview"
    @State private var confirmDelete = false

    var body: some View {
        if let container = store.selectedContainer {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(container.name.isEmpty ? container.id : container.name)
                        .font(.title.bold())
                    Text(container.image)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    if container.isRunning {
                        Button("Shell", systemImage: "terminal") { store.openShell(container) }
                        Button("Stop", systemImage: "stop.fill") { store.lifecycle("stop", container: container) }
                    } else { Button("Start", systemImage: "play.fill") { store.lifecycle("start", container: container) }.buttonStyle(.borderedProminent) }
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Restart") { store.lifecycle("restart", container: container) }
                        Button("Kill") { store.lifecycle("kill", container: container) }
                        Divider()
                        Button("Delete", role: .destructive) { confirmDelete = true }
                    }
                    Spacer()
                }
                Divider()
                Picker("View", selection: $tab) { Text("Overview").tag("Overview"); Text("Logs").tag("Logs"); Text("Inspect").tag("Inspect") }.pickerStyle(.segmented)
                switch tab {
                case "Logs": LogView(text: $logs, search: $search) { await loadLogs(container) }
                case "Inspect": ScrollView { Text(inspect.isEmpty ? "Loading…" : inspect).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                default: overview(container)
                }
            }.padding(AppLayout.panelPadding)
                .task(id: container.id) { await load(container) }
                .confirmationDialog("Delete \(container.name)?", isPresented: $confirmDelete) { Button("Delete Container", role: .destructive) { store.lifecycle("delete", container: container) } }
        } else { ContentUnavailableView("Select a container", systemImage: "shippingbox") }
    }

    private func overview(_ container: ContainerSummary) -> some View {
        Form {
            LabeledContent("State", value: container.state)
            LabeledContent("Address", value: container.address.isEmpty ? "—" : container.address)
            LabeledContent("Architecture", value: container.architecture.isEmpty ? "—" : container.architecture)
            if let stat = store.stats.first(where: { $0.id == container.id || container.id.hasPrefix($0.id) }) {
                Section("Resources") { LabeledContent("CPU", value: stat.cpu); LabeledContent("Memory", value: stat.memory); LabeledContent("Network", value: stat.network); LabeledContent("Block I/O", value: stat.blockIO); LabeledContent("Processes", value: stat.processes) }
            }
        }.formStyle(.grouped)
    }

    private func load(_ container: ContainerSummary) async {
        await loadLogs(container)
        inspect = (try? await store.client.inspect(container.id, summary: container).rawJSON) ?? "Inspect unavailable"
    }
    private func loadLogs(_ container: ContainerSummary) async { logs = (try? await store.client.logs(container.id)) ?? "Logs unavailable" }
}

struct LogView: View {
    @Binding var text: String
    @Binding var search: String
    let refresh: () async -> Void
    @State private var paused = false
    var body: some View {
        VStack {
            HStack { TextField("Search logs", text: $search); Toggle("Pause", isOn: $paused).toggleStyle(.button); Button("Clear") { text = "" }; Button("Reload") { Task { await refresh() } } }
            ScrollView([.horizontal, .vertical]) { Text(filtered).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }
    private var filtered: String { search.isEmpty ? text : text.split(separator: "\n").filter { $0.localizedCaseInsensitiveContains(search) }.joined(separator: "\n") }
}

struct OperationRow: View {
    let operation: Operation
    var body: some View {
        HStack { Image(systemName: operation.status == .succeeded ? "checkmark.circle.fill" : operation.status == .failed ? "xmark.circle.fill" : "clock").foregroundStyle(operation.status == .failed ? .red : operation.status == .succeeded ? .green : .orange); VStack(alignment: .leading) { Text(operation.kind); Text(operation.command).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Text(operation.status.rawValue.capitalized).font(.caption) }.padding(.horizontal, 8)
    }
}
