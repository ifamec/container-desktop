import Foundation

protocol CommandExecuting: Sendable {
    func run(_ executable: String, arguments: [String], timeout: Duration?, onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult
}

extension CommandExecuting {
    func run(_ executable: String, arguments: [String], timeout: Duration? = .seconds(30)) async throws -> CommandResult {
        try await run(executable, arguments: arguments, timeout: timeout, onOutput: nil)
    }
}

struct ProcessExecutor: CommandExecuting {
    func run(_ executable: String, arguments: [String], timeout: Duration? = .seconds(30), onOutput: (@Sendable (String) -> Void)? = nil) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let root = FileManager.default.temporaryDirectory
            let stdoutURL = root.appending(path: "container-desktop-\(UUID()).out")
            let stderrURL = root.appending(path: "container-desktop-\(UUID()).err")
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            let stdout = try FileHandle(forUpdating: stdoutURL)
            let stderr = try FileHandle(forUpdating: stderrURL)
            let stdoutReader = try FileHandle(forReadingFrom: stdoutURL)
            let stderrReader = try FileHandle(forReadingFrom: stderrURL)
            defer {
                try? stdout.close(); try? stderr.close(); try? stdoutReader.close(); try? stderrReader.close()
                try? FileManager.default.removeItem(at: stdoutURL)
                try? FileManager.default.removeItem(at: stderrURL)
            }
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()

            let deadline = timeout.map { ContinuousClock.now.advanced(by: $0) }
            var outData = Data(), errData = Data()
            while process.isRunning {
                if Task.isCancelled { process.terminate(); throw CancellationError() }
                if let deadline, ContinuousClock.now >= deadline {
                    process.terminate()
                    throw CLIError(command: CommandLineFormatter.format(executable, arguments), exitCode: -1, output: "Command timed out")
                }
                if let chunk = try stdoutReader.readToEnd(), !chunk.isEmpty {
                    outData.append(chunk); onOutput?(String(decoding: chunk, as: UTF8.self))
                }
                if let chunk = try stderrReader.readToEnd(), !chunk.isEmpty {
                    errData.append(chunk); onOutput?(String(decoding: chunk, as: UTF8.self))
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            if let chunk = try stdoutReader.readToEnd(), !chunk.isEmpty { outData.append(chunk); onOutput?(String(decoding: chunk, as: UTF8.self)) }
            if let chunk = try stderrReader.readToEnd(), !chunk.isEmpty { errData.append(chunk); onOutput?(String(decoding: chunk, as: UTF8.self)) }
            let out = String(decoding: outData, as: UTF8.self)
            let err = String(decoding: errData, as: UTF8.self)
            return CommandResult(command: CommandLineFormatter.format(executable, arguments), exitCode: process.terminationStatus, stdout: out, stderr: err)
        }.value
    }
}

enum CommandLineFormatter {
    static func format(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments).map { value in
            !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || "-._/:=@,".contains($0) }
                ? value : "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
        }.joined(separator: " ")
    }
}

actor ContainerCLIClient {
    private let executor: any CommandExecuting
    private let pathOverride: String?

    init(executor: any CommandExecuting = ProcessExecutor(), pathOverride: String? = nil) {
        self.executor = executor
        self.pathOverride = pathOverride
    }

    func executable() -> String? {
        let configured = (pathOverride ?? UserDefaults.standard.string(forKey: "cliPath") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [configured, "/usr/local/bin/container", "/opt/homebrew/bin/container"].filter { !$0.isEmpty }
        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return match }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.split(separator: ":").map { "\($0)/container" }.first(where: FileManager.default.isExecutableFile)
    }

    func status() async -> CLIStatus {
        guard let executable = executable() else { return .missing }
        do {
            let version = try await checked(executable, ["system", "version", "--format", "json"])
            let objects = try JSONSerialization.jsonObject(with: Data(version.stdout.utf8)) as? [[String: Any]] ?? []
            let cli = objects.first { ($0["appName"] as? String) == "container" }
            guard let number = cli?["version"] as? String else { return .incompatible("Version JSON is missing the CLI version") }
            let list = try await executor.run(executable, arguments: ["list", "--all", "--format", "json"], timeout: .seconds(10))
            return list.exitCode == 0 ? .ready(number) : .serviceStopped
        } catch { return .failed(Self.sanitize(String(describing: error))) }
    }

    func containers() async throws -> [ContainerSummary] {
        let result = try await command(["list", "--all", "--format", "json"])
        return try Self.decodeArray(result.stdout).map { item in
            let id = item.string("id", "ID", "name")
            return ContainerSummary(id: id, name: item.string("name", "id", "ID"), image: item.string("image", "imageReference", "configuration.image.reference"), state: item.string("state", "status.state", "status"), address: item.string("address", "addr", "ipAddress", "status.networks.ipv4Address"), architecture: item.string("architecture", "arch", "configuration.platform.architecture"), createdAt: item.string("createdAt", "created", "configuration.creationDate"))
        }
    }

    func images() async throws -> [ImageSummary] {
        let result = try await command(["image", "list", "--format", "json"])
        return try Self.decodeArray(result.stdout).map { item in
            let rawReference = item.string("name", "reference", "repository", "configuration.name")
            let split = Self.splitReference(rawReference)
            return ImageSummary(reference: split.name, tag: item.string("tag").isEmpty ? split.tag : item.string("tag"), digest: item.string("digest", "descriptor.digest", "configuration.descriptor.digest", "id"), size: Self.byteString(item.number("size", "sizeBytes", "variants.size", "descriptor.size", "configuration.descriptor.size")), createdAt: item.string("createdAt", "created", "creationDate", "configuration.creationDate"))
        }
    }

    func stats() async throws -> [ContainerStats] {
        let result = try await command(["stats", "--no-stream", "--format", "json"])
        return try Self.decodeArray(result.stdout).map { item in
            let memory = item.string("memory", "memoryUsage")
            let network = item.string("network", "networkIO")
            let block = item.string("blockIO", "blockIo")
            return ContainerStats(
                id: item.string("id", "container", "containerID"),
                cpu: item.string("cpu", "cpuPercent").or("\(item.number("cpuUsageUsec")) µs"),
                memory: memory.or("\(Self.byteString(item.number("memoryUsageBytes"))) / \(Self.byteString(item.number("memoryLimitBytes")))"),
                network: network.or("↓ \(Self.byteString(item.number("networkRxBytes")))  ↑ \(Self.byteString(item.number("networkTxBytes")))"),
                blockIO: block.or("↓ \(Self.byteString(item.number("blockReadBytes")))  ↑ \(Self.byteString(item.number("blockWriteBytes")))"),
                processes: item.string("processes", "pids", "numProcesses")
            )
        }
    }

    func inspect(_ id: String, summary: ContainerSummary) async throws -> ContainerDetails {
        let result = try await command(["inspect", id])
        return ContainerDetails(summary: summary, rawJSON: result.stdout)
    }

    func logs(_ id: String, lines: Int = 500) async throws -> String {
        let result = try await command(["logs", "-n", String(lines), id])
        return result.stdout + result.stderr
    }

    func command(_ arguments: [String], timeout: Duration? = .seconds(60), onOutput: (@Sendable (String) -> Void)? = nil) async throws -> CommandResult {
        guard let executable = executable() else { throw CLIError(command: "container", exitCode: 127, output: "Apple container is not installed") }
        let result = try await executor.run(executable, arguments: arguments, timeout: timeout, onOutput: onOutput)
        guard result.exitCode == 0 else { throw CLIError(command: result.command, exitCode: result.exitCode, output: Self.sanitize(result.stderr.isEmpty ? result.stdout : result.stderr)) }
        return result
    }

    private func checked(_ executable: String, _ arguments: [String], timeout: Duration? = .seconds(30)) async throws -> CommandResult {
        let result = try await executor.run(executable, arguments: arguments, timeout: timeout)
        guard result.exitCode == 0 else { throw CLIError(command: result.command, exitCode: result.exitCode, output: Self.sanitize(result.stderr.isEmpty ? result.stdout : result.stderr)) }
        return result
    }

    static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?i)(password|token|secret)=\S+"#, with: "$1=••••", options: .regularExpression)
    }

    private static func decodeArray(_ json: String) throws -> [JSONItem] {
        let value = try JSONSerialization.jsonObject(with: Data(json.utf8))
        guard let rows = value as? [[String: Any]] else { throw CLIError(command: "decode", exitCode: -1, output: "Expected a JSON array") }
        return rows.map(JSONItem.init)
    }

    private static func splitReference(_ reference: String) -> (name: String, tag: String) {
        guard let colon = reference.lastIndex(of: ":"), !reference[reference.index(after: colon)...].contains("/") else { return (reference, "") }
        return (String(reference[..<colon]), String(reference[reference.index(after: colon)...]))
    }

    private static func byteString(_ value: Int64) -> String {
        guard value > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

private struct JSONItem {
    let value: [String: Any]
    func string(_ keys: String...) -> String {
        for key in keys {
            if let value = nested(key) {
                if let text = value as? String { return text }
                if let number = value as? NSNumber { return number.stringValue }
            }
        }
        return ""
    }

    func number(_ keys: String...) -> Int64 {
        for key in keys { if let number = nested(key) as? NSNumber { return number.int64Value } }
        return 0
    }
    private func nested(_ path: String) -> Any? {
        var current: Any? = value
        for component in path.split(separator: ".").map(String.init) {
            if let array = current as? [Any] { current = array.first }
            current = (current as? [String: Any])?[component]
        }
        return current
    }
}

private extension String { func or(_ fallback: @autoclosure () -> String) -> String { isEmpty ? fallback() : self } }
