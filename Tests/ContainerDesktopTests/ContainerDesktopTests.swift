import Foundation

@main
struct ContainerDesktopTests {
    static func main() async throws {
        try testFullRunArguments()
        try testMinimalRunArguments()
        try testShellWordParsing()
        try testCommandFormatting()
        try testSanitization()
        try testModelHelpers()
        try await testContainerV1Decoding()
        try await testLegacyContainerDecoding()
        try await testImageDecoding()
        try await testRegistryPortWithoutTag()
        try await testStatsDecoding()
        try await testReadyStatus()
        try await testStoppedStatus()
        try await testIncompatibleStatus()
        try await testCommandFailureRedaction()
        try await testMalformedJSON()
        try await testLogCombination()
        try await testProcessExecutor()
        try await testProcessTimeout()
        print("✓ 19 Container Desktop unit tests passed")
    }

    static func testFullRunArguments() throws {
        let config = RunConfiguration(
            name: "web", image: "nginx:latest", command: "nginx -g 'daemon off;'",
            environment: "A=1\nB=two", ports: "8080:80", mounts: "type=bind,source=/tmp,target=/data",
            cpu: "2", memory: "1G", autoRemove: true
        )
        try expectEqual(config.arguments, ["run", "--detach", "--name", "web", "--env", "A=1", "--env", "B=two", "--publish", "8080:80", "--mount", "type=bind,source=/tmp,target=/data", "--cpus", "2", "--memory", "1G", "--rm", "nginx:latest", "nginx", "-g", "daemon off;"], "full run argument generation")
    }

    static func testMinimalRunArguments() throws {
        try expectEqual(RunConfiguration(image: "alpine").arguments, ["run", "--detach", "alpine"], "minimal run arguments")
    }

    static func testShellWordParsing() throws {
        try expectEqual(RunConfiguration.shellWords(#"tool "two words" 'three words' escaped\ value trail\"#), ["tool", "two words", "three words", "escaped value", "trail\\"], "quoted and escaped command parsing")
    }

    static func testCommandFormatting() throws {
        try expectEqual(CommandLineFormatter.format("container", ["run", "hello world", "a'b", ""]), "container run 'hello world' 'a'\\''b' ''", "safe command formatting")
    }

    static func testSanitization() throws {
        let input = "TOKEN=abc password=hunter2 Secret=value safe=yes"
        try expectEqual(ContainerCLIClient.sanitize(input), "TOKEN=•••• password=•••• Secret=•••• safe=yes", "case-insensitive credential sanitization")
    }

    static func testModelHelpers() throws {
        try expect(ContainerSummary(id: "a", name: "a", image: "x", state: "RUNNING", address: "", architecture: "", createdAt: "").isRunning, "running state is case insensitive")
        try expectEqual(ImageSummary(reference: "alpine", tag: "latest", digest: "", size: "", createdAt: "").displayName, "alpine:latest", "tagged image display name")
        try expectEqual(ImageSummary(reference: "alpine", tag: "", digest: "", size: "", createdAt: "").id, "alpine", "image ID falls back to reference")
    }

    static func testContainerV1Decoding() async throws {
        let json = #"[{"configuration":{"creationDate":"today","image":{"reference":"alpine:latest"},"platform":{"architecture":"arm64"}},"id":"demo","status":{"networks":[{"ipv4Address":"192.168.64.2"}],"state":"running"}}]"#
        let containers = try await client(json: json).containers()
        try expectEqual(containers, [ContainerSummary(id: "demo", name: "demo", image: "alpine:latest", state: "running", address: "192.168.64.2", architecture: "arm64", createdAt: "today")], "container 1.0 JSON decoding")
    }

    static func testLegacyContainerDecoding() async throws {
        let json = #"[{"ID":"old","name":"legacy","image":"busybox","state":"stopped","address":"10.0.0.2","architecture":"arm64","createdAt":"yesterday"}]"#
        let container = try await client(json: json).containers().first
        try expectEqual(container?.name, "legacy", "legacy container name")
        try expectEqual(container?.state, "stopped", "legacy container state")
    }

    static func testImageDecoding() async throws {
        let json = #"[{"configuration":{"creationDate":"today","descriptor":{"digest":"sha256:abc","size":9218},"name":"localhost:5000/team/app:dev"},"id":"abc","variants":[{"size":4184689}]}]"#
        let image = try await client(json: json).images().first
        try expectEqual(image?.reference, "localhost:5000/team/app", "registry image reference")
        try expectEqual(image?.tag, "dev", "registry image tag")
        try expectEqual(image?.digest, "sha256:abc", "image digest")
        try expect(image?.size.contains("4.2") == true, "image variant size")
    }

    static func testRegistryPortWithoutTag() async throws {
        let json = #"[{"reference":"localhost:5000/team/app","digest":"sha256:def","sizeBytes":1000}]"#
        let image = try await client(json: json).images().first
        try expectEqual(image?.reference, "localhost:5000/team/app", "registry port is not mistaken for a tag")
        try expectEqual(image?.tag, "", "untagged registry image")
    }

    static func testStatsDecoding() async throws {
        let json = #"[{"id":"demo","cpuUsageUsec":42,"memoryUsageBytes":1000,"memoryLimitBytes":2000,"networkRxBytes":3000,"networkTxBytes":4000,"blockReadBytes":5000,"blockWriteBytes":6000,"numProcesses":7}]"#
        let stat = try await client(json: json).stats().first
        try expectEqual(stat?.cpu, "42 µs", "CPU stats")
        try expectEqual(stat?.processes, "7", "process count stats")
        try expect(stat?.network.contains("↓") == true && stat?.network.contains("↑") == true, "network stats directions")
    }

    static func testReadyStatus() async throws {
        let executor = StubExecutor { arguments in
            if arguments.first == "system" { return .success(#"[{"appName":"container","version":"1.0.0"}]"#) }
            return .success("[]")
        }
        try expectEqual(await ContainerCLIClient(executor: executor, pathOverride: "/usr/bin/true").status(), .ready("1.0.0"), "ready status")
    }

    static func testStoppedStatus() async throws {
        let executor = StubExecutor { arguments in
            if arguments.first == "system" { return .success(#"[{"appName":"container","version":"1.0.0"}]"#) }
            return CommandResult(command: "fake", exitCode: 1, stdout: "", stderr: "stopped")
        }
        try expectEqual(await ContainerCLIClient(executor: executor, pathOverride: "/usr/bin/true").status(), .serviceStopped, "stopped service status")
    }

    static func testIncompatibleStatus() async throws {
        let client = ContainerCLIClient(executor: StubExecutor { _ in .success(#"[{"appName":"other","version":"1"}]"#) }, pathOverride: "/usr/bin/true")
        guard case .incompatible = await client.status() else { throw TestFailure(name: "incompatible version status") }
    }

    static func testCommandFailureRedaction() async throws {
        let client = ContainerCLIClient(executor: StubExecutor { _ in CommandResult(command: "fake", exitCode: 9, stdout: "", stderr: "token=private") }, pathOverride: "/usr/bin/true")
        do {
            _ = try await client.command(["bad"])
            throw TestFailure(name: "nonzero command must throw")
        } catch let error as CLIError {
            try expectEqual(error.exitCode, 9, "nonzero exit code")
            try expectEqual(error.output, "token=••••", "command error redaction")
        }
    }

    static func testMalformedJSON() async throws {
        do {
            _ = try await client(json: "{}").containers()
            throw TestFailure(name: "malformed list JSON must throw")
        } catch let error as CLIError {
            try expectEqual(error.command, "decode", "malformed JSON decode error")
        }
    }

    static func testLogCombination() async throws {
        let executor = StubExecutor { arguments in
            guard arguments == ["logs", "-n", "12", "demo"] else { throw TestFailure(name: "log command arguments") }
            return CommandResult(command: "fake", exitCode: 0, stdout: "out\n", stderr: "err\n")
        }
        let logs = try await ContainerCLIClient(executor: executor, pathOverride: "/usr/bin/true").logs("demo", lines: 12)
        try expectEqual(logs, "out\nerr\n", "stdout and stderr log combination")
    }

    static func testProcessExecutor() async throws {
        let result = try await ProcessExecutor().run("/bin/echo", arguments: ["hello world"], timeout: .seconds(2))
        try expectEqual(result.exitCode, 0, "process exit code")
        try expectEqual(result.stdout, "hello world\n", "process stdout capture")
        try expect(result.command.hasSuffix("'hello world'"), "process command preview")
    }

    static func testProcessTimeout() async throws {
        do {
            _ = try await ProcessExecutor().run("/bin/sleep", arguments: ["1"], timeout: .milliseconds(20))
            throw TestFailure(name: "process timeout must throw")
        } catch let error as CLIError {
            try expectEqual(error.exitCode, -1, "timeout exit code")
        }
    }

    static func client(json: String) -> ContainerCLIClient {
        ContainerCLIClient(executor: StubExecutor { _ in .success(json) }, pathOverride: "/usr/bin/true")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw TestFailure(name: name) }
    }

    static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) throws {
        guard actual == expected else { throw TestFailure(name: "\(name) — expected \(expected), got \(actual)") }
    }
}

private struct TestFailure: Error, CustomStringConvertible, Sendable {
    let name: String
    var description: String { "Test failed: \(name)" }
}

private struct StubExecutor: CommandExecuting {
    let handler: @Sendable ([String]) throws -> CommandResult

    init(_ handler: @escaping @Sendable ([String]) throws -> CommandResult) {
        self.handler = handler
    }

    func run(_ executable: String, arguments: [String], timeout: Duration?, onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        let result = try handler(arguments)
        onOutput?(result.stdout)
        return result
    }
}

private extension CommandResult {
    static func success(_ stdout: String) -> CommandResult {
        CommandResult(command: "fake", exitCode: 0, stdout: stdout, stderr: "")
    }
}
