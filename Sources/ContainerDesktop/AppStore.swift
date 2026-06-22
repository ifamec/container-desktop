import AppKit
import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var status: CLIStatus = .checking
    @Published var containers: [ContainerSummary] = []
    @Published var images: [ImageSummary] = []
    @Published var stats: [ContainerStats] = []
    @Published var operations: [Operation] = []
    @Published var selectedContainerID: String?
    @Published var selectedImageID: String?
    @Published var errorMessage: String?
    @Published var isStale = false
    @Published var appIsActive = true

    let client: ContainerCLIClient
    private var pollTask: Task<Void, Never>?
    private var busyContainers: Set<String> = []
    private var operationTasks: [UUID: Task<Void, Never>] = [:]

    init(client: ContainerCLIClient = ContainerCLIClient()) { self.client = client }

    var selectedContainer: ContainerSummary? { containers.first { $0.id == selectedContainerID } }
    var selectedImage: ImageSummary? { images.first { $0.id == selectedImageID } }
    var runningCount: Int { containers.filter(\.isRunning).count }

    func start() {
        pollTask?.cancel()
        pollTask = Task {
            await refresh()
            while !Task.isCancelled {
                let seconds = max(1, UserDefaults.standard.double(forKey: "pollingInterval").nonzero ?? 2)
                try? await Task.sleep(for: .seconds(seconds))
                if appIsActive { await refresh() }
            }
        }
    }

    func refresh() async {
        status = await client.status()
        guard case .ready = status else { return }
        do {
            async let nextContainers = client.containers()
            async let nextImages = client.images()
            async let nextStats = client.stats()
            containers = try await nextContainers
            images = try await nextImages
            stats = (try? await nextStats) ?? stats
            isStale = false
        } catch {
            isStale = true
            errorMessage = error.localizedDescription
        }
    }

    func startService() { perform(kind: "Start service", arguments: ["system", "start"], timeout: .seconds(300)) }
    func stopService() { perform(kind: "Stop service", arguments: ["system", "stop"], timeout: .seconds(120)) }
    func pull(_ image: String) { perform(kind: "Pull \(image)", arguments: ["image", "pull", image], timeout: .seconds(1800)) }
    func deleteImage(_ image: ImageSummary) { perform(kind: "Delete image", arguments: ["image", "delete", image.displayName]) }
    func tagImage(_ source: ImageSummary, destination: String) { perform(kind: "Tag image", arguments: ["image", "tag", source.displayName, destination]) }
    func pushImage(_ image: ImageSummary) { perform(kind: "Push image", arguments: ["image", "push", image.displayName], timeout: .seconds(1800)) }
    func run(_ config: RunConfiguration) { perform(kind: "Run \(config.image)", arguments: config.arguments, timeout: .seconds(1800)) }

    func lifecycle(_ action: String, container: ContainerSummary) {
        guard !busyContainers.contains(container.id) else { return }
        busyContainers.insert(container.id)
        let args: [String]
        switch action {
        case "restart": args = ["stop", container.id, "&&", "start", container.id]
        case "delete": args = ["delete", container.id]
        default: args = [action, container.id]
        }
        if action == "restart" {
            Task {
                defer { busyContainers.remove(container.id) }
                do {
                    _ = try await client.command(["stop", container.id])
                    _ = try await client.command(["start", container.id])
                    await refresh()
                } catch { errorMessage = error.localizedDescription }
            }
        } else {
            perform(kind: "\(action.capitalized) \(container.name)", arguments: args) { [weak self] in self?.busyContainers.remove(container.id) }
        }
    }

    func build(context: String, dockerfile: String, tag: String) {
        var args = ["build", "--progress", "plain"]
        if !dockerfile.isEmpty { args += ["--file", dockerfile] }
        if !tag.isEmpty { args += ["--tag", tag] }
        args.append(context)
        perform(kind: "Build \(tag.isEmpty ? context : tag)", arguments: args, timeout: .seconds(3600))
    }

    func cancel(_ operation: Operation) {
        if let index = operations.firstIndex(where: { $0.id == operation.id }), operations[index].status == .running {
            operationTasks[operation.id]?.cancel()
            operations[index].status = .cancelled
            operations[index].endedAt = Date()
        }
    }

    func openShell(_ container: ContainerSummary) {
        let shell = UserDefaults.standard.string(forKey: "shellCommand").flatMap { $0.isEmpty ? nil : $0 } ?? "sh"
        Task {
            guard let executable = await client.executable() else { errorMessage = "Apple container is not installed"; return }
            let command = CommandLineFormatter.format(executable, ["exec", "--interactive", "--tty", container.id, shell])
            let script = "tell application \"Terminal\" to do script \"\(command.appleScriptEscaped)\"\ntell application \"Terminal\" to activate"
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error { errorMessage = error.description }
        }
    }

    func diagnostics() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
        let commands = operations.suffix(25).map { "[\($0.status.rawValue)] \($0.command)" }.joined(separator: "\n")
        return "Container Desktop: \(version)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nArchitecture: arm64\nCLI: \(status.title)\n\nRecent commands:\n\(commands)"
    }

    private func perform(kind: String, arguments: [String], timeout: Duration? = .seconds(60), completion: (() -> Void)? = nil) {
        let id = UUID()
        let path = UserDefaults.standard.string(forKey: "cliPath").flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/local/bin/container"
        operations.insert(Operation(id: id, kind: kind, progress: nil, command: CommandLineFormatter.format(path, arguments)), at: 0)
        let retention = max(5, UserDefaults.standard.integer(forKey: "outputRetention"))
        if operations.count > retention { operations.removeLast(operations.count - retention) }
        let task = Task {
            let path = await client.executable() ?? "container"
            let command = CommandLineFormatter.format(path, arguments)
            if let index = operations.firstIndex(where: { $0.id == id }) { operations[index].command = command }
            do {
                _ = try await client.command(arguments, timeout: timeout) { [weak self] chunk in
                    Task { @MainActor in self?.append(chunk, to: id) }
                }
                finish(id, status: .succeeded, output: operations.first(where: { $0.id == id })?.output ?? "")
                await refresh()
            } catch is CancellationError {
                finish(id, status: .cancelled, output: "Cancelled")
            } catch {
                finish(id, status: .failed, output: error.localizedDescription)
                errorMessage = error.localizedDescription
            }
            operationTasks[id] = nil
            completion?()
        }
        operationTasks[id] = task
    }

    private func append(_ output: String, to id: UUID) {
        guard let index = operations.firstIndex(where: { $0.id == id }), operations[index].status == .running else { return }
        operations[index].output += ContainerCLIClient.sanitize(output)
    }

    private func finish(_ id: UUID, status: Operation.Status, output: String) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].status = status
        operations[index].output = ContainerCLIClient.sanitize(output)
        operations[index].endedAt = Date()
    }
}

private extension Double { var nonzero: Double? { self == 0 ? nil : self } }
private extension String {
    var appleScriptEscaped: String { replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
}

struct SavedConfigurationStore {
    static var url: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appending(path: "ContainerDesktop/run-configurations.json")
    }

    static func load() -> [RunConfiguration] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([RunConfiguration].self, from: $0) } ?? []
    }

    static func save(_ configurations: [RunConfiguration]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(configurations).write(to: url, options: .atomic)
    }
}
