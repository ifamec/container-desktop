import Foundation

@main
struct ContainerDesktopTests {
    static func main() async throws {
        try expectRunArguments()
        try expectCommandFormatting()
        try expectSanitization()
        try await expectContainerDecoding()
        try await expectImageDecoding()
        print("✓ 5 Container Desktop core tests passed")
    }

    static func expectRunArguments() throws {
        let config = RunConfiguration(
            name: "web", image: "nginx:latest", command: "nginx -g 'daemon off;'",
            environment: "A=1\nB=two", ports: "8080:80", mounts: "type=bind,source=/tmp,target=/data",
            cpu: "2", memory: "1G", autoRemove: true
        )
        try expect(config.arguments == ["run", "--detach", "--name", "web", "--env", "A=1", "--env", "B=two", "--publish", "8080:80", "--mount", "type=bind,source=/tmp,target=/data", "--cpus", "2", "--memory", "1G", "--rm", "nginx:latest", "nginx", "-g", "daemon off;"], "run argument generation")
    }

    static func expectCommandFormatting() throws {
        try expect(CommandLineFormatter.format("container", ["run", "hello world", "a'b"]) == "container run 'hello world' 'a'\\''b'", "safe command formatting")
    }

    static func expectSanitization() throws {
        try expect(ContainerCLIClient.sanitize("token=abc password=hunter2 safe=yes") == "token=•••• password=•••• safe=yes", "credential sanitization")
    }

    static func expectContainerDecoding() async throws {
        let client = ContainerCLIClient(executor: FakeExecutor(kind: .containers), pathOverride: "/usr/bin/true")
        let containers = try await client.containers()
        try expect(containers == [ContainerSummary(id: "demo", name: "demo", image: "alpine:latest", state: "running", address: "192.168.64.2", architecture: "arm64", createdAt: "today")], "flexible JSON decoding")
    }

    static func expectImageDecoding() async throws {
        let client = ContainerCLIClient(executor: FakeExecutor(kind: .images), pathOverride: "/usr/bin/true")
        let images = try await client.images()
        try expect(images.first?.displayName == "docker.io/library/alpine:latest", "1.0 image reference decoding")
        try expect(images.first?.size == "4.2 MB", "1.0 image size decoding")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw TestFailure(name: name) }
    }
}

private struct TestFailure: Error, CustomStringConvertible { let name: String; var description: String { "Test failed: \(name)" } }
private struct FakeExecutor: CommandExecuting {
    enum Kind { case containers, images }
    let kind: Kind
    func run(_ executable: String, arguments: [String], timeout: Duration?, onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        let json = switch kind {
        case .containers: #"[{"configuration":{"creationDate":"today","image":{"reference":"alpine:latest"},"platform":{"architecture":"arm64"}},"id":"demo","status":{"networks":[{"ipv4Address":"192.168.64.2"}],"state":"running"}}]"#
        case .images: #"[{"configuration":{"creationDate":"today","descriptor":{"digest":"sha256:abc","size":9218},"name":"docker.io/library/alpine:latest"},"id":"abc","variants":[{"size":4184689}]}]"#
        }
        onOutput?(json)
        return CommandResult(command: "fake", exitCode: 0, stdout: json, stderr: "")
    }
}
