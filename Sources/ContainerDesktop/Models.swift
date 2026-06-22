import Foundation

struct ContainerSummary: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var image: String
    var state: String
    var address: String
    var architecture: String
    var createdAt: String

    var isRunning: Bool { state.lowercased() == "running" }
}

struct ContainerDetails: Codable, Hashable, Sendable {
    var summary: ContainerSummary
    var command: [String] = []
    var environment: [String] = []
    var mounts: [String] = []
    var publishedPorts: [String] = []
    var resourceLimits: [String: String] = [:]
    var rawJSON = ""
}

struct ImageSummary: Identifiable, Codable, Hashable, Sendable {
    var id: String { digest.isEmpty ? reference : digest }
    var reference: String
    var tag: String
    var digest: String
    var size: String
    var createdAt: String
    var displayName: String { tag.isEmpty ? reference : "\(reference):\(tag)" }
}

struct ContainerStats: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var cpu: String
    var memory: String
    var network: String
    var blockIO: String
    var processes: String
}

enum ContainerAction: String, Sendable {
    case start, stop, restart, kill, delete

    var title: String { rawValue.capitalized }
    func arguments(for containerID: String) -> [String] { [rawValue, containerID] }
}

struct RunConfiguration: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    var image = ""
    var command = ""
    var environment = ""
    var ports = ""
    var mounts = ""
    var cpu = ""
    var memory = ""
    var autoRemove = false

    var arguments: [String] {
        var result = ["run", "--detach"]
        if !name.isEmpty { result += ["--name", name] }
        result += Self.repeatedOption("--env", values: environment)
        result += Self.repeatedOption("--publish", values: ports)
        result += Self.repeatedOption("--mount", values: mounts)
        if !cpu.isEmpty { result += ["--cpus", cpu] }
        if !memory.isEmpty { result += ["--memory", memory] }
        if autoRemove { result.append("--rm") }
        result.append(image)
        result += Self.shellWords(command)
        return result
    }

    private static func lines(_ value: String) -> [String] {
        value.split(whereSeparator: \Character.isNewline).map(String.init)
    }

    private static func repeatedOption(_ option: String, values: String) -> [String] {
        lines(values).flatMap { [option, $0] }
    }

    static func shellWords(_ input: String) -> [String] {
        var words: [String] = [], current = ""
        var quote: Character?
        var escaped = false
        for character in input {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { words.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        if !current.isEmpty { words.append(current) }
        return words
    }
}

enum CLIStatus: Equatable, Sendable {
    case checking, missing, incompatible(String), serviceStopped, starting, ready(String), failed(String)

    var title: String {
        switch self {
        case .checking: "Checking"
        case .missing: "Not installed"
        case .incompatible: "Incompatible"
        case .serviceStopped: "Service stopped"
        case .starting: "Starting"
        case .ready: "Ready"
        case .failed: "Error"
        }
    }
}

struct Operation: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable { case running, succeeded, failed, cancelled }
    var id = UUID()
    var kind: String
    var progress: Double?
    var command: String
    var startedAt = Date()
    var endedAt: Date?
    var status: Status = .running
    var output = ""
}

struct CommandResult: Sendable {
    var command: String
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

struct CLIError: LocalizedError, Sendable {
    var command: String
    var exitCode: Int32
    var output: String
    var errorDescription: String? { "\(command) failed (exit \(exitCode)): \(output)" }
}
