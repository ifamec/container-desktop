import AppKit
import SwiftUI

struct RunContainerView: View {
    private enum Field: Hashable { case image, name, command, cpu, memory, environment, ports, mounts }

    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var config: RunConfiguration
    @State private var saved = SavedConfigurationStore.load()
    @FocusState private var focusedField: Field?

    init(store: AppStore, initialImage: String = "") {
        self.store = store
        _config = State(initialValue: RunConfiguration(image: initialImage))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Run Container").font(.title.bold())
            Form {
                TextField("Image", text: $config.image, prompt: Text("alpine:latest")).focused($focusedField, equals: .image)
                TextField("Name", text: $config.name).focused($focusedField, equals: .name)
                TextField("Command", text: $config.command, prompt: Text("Optional arguments")).focused($focusedField, equals: .command)
                TextField("CPU", text: $config.cpu, prompt: Text("2")).focused($focusedField, equals: .cpu)
                TextField("Memory", text: $config.memory, prompt: Text("2G")).focused($focusedField, equals: .memory)
                TextField("Environment (one KEY=value per line)", text: $config.environment, axis: .vertical).focused($focusedField, equals: .environment).lineLimit(2...5)
                TextField("Ports (one host:container per line)", text: $config.ports, axis: .vertical).focused($focusedField, equals: .ports).lineLimit(2...4)
                TextField("Mounts (one type=…,source=…,target=… per line)", text: $config.mounts, axis: .vertical).focused($focusedField, equals: .mounts).lineLimit(2...4)
                Toggle("Remove automatically when stopped", isOn: $config.autoRemove)
                Section("Command preview") { Text(CommandLineFormatter.format("container", config.arguments)).font(.caption.monospaced()).textSelection(.enabled) }
            }.formStyle(.grouped)
            HStack {
                Menu("Saved") { ForEach(saved) { item in Button(item.name.isEmpty ? item.image : item.name) { config = item } } }
                Button("Save Configuration") { saved.append(config); try? SavedConfigurationStore.save(saved) }.disabled(config.image.isEmpty)
                Spacer(); Button("Cancel") { dismiss() }; Button("Run") { store.run(config); dismiss() }.buttonStyle(.borderedProminent).disabled(config.image.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620, height: 690)
        .onAppear { focusedField = config.image.isEmpty ? .image : .name }
    }
}

struct ImageListView: View {
    @ObservedObject var store: AppStore
    @State private var showPull = false
    @State private var imageName = ""
    var body: some View {
        VStack(spacing: 0) {
            PageHeader("Images", subtitle: "OCI images available on this Mac") {
                Button("Pull", systemImage: "square.and.arrow.down") { showPull = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(AppLayout.panelPadding)
            Divider()
            List(store.images, selection: $store.selectedImageID) { image in
                VStack(alignment: .leading, spacing: 4) {
                    Text(image.displayName).fontWeight(.medium)
                    Text(image.digest).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets(top: 8, leading: AppLayout.panelPadding, bottom: 8, trailing: AppLayout.panelPadding))
                .tag(image.id)
            }
            .listStyle(.plain)
            .overlay { if store.images.isEmpty { ContentUnavailableView("No images", systemImage: "square.stack.3d.up", description: Text("Pull an OCI image to get started.")) } }
        }
        .sheet(isPresented: $showPull) {
            VStack(alignment: .leading, spacing: 18) { Text("Pull Image").font(.title.bold()); TextField("Image reference", text: $imageName, prompt: Text("docker.io/library/alpine:latest")); HStack { Spacer(); Button("Cancel") { showPull = false }; Button("Pull") { store.pull(imageName); showPull = false }.buttonStyle(.borderedProminent).disabled(imageName.isEmpty) } }.padding(24).frame(width: 480)
        }
    }
}

struct ImageDetailView: View {
    @ObservedObject var store: AppStore
    @State private var showTag = false
    @State private var destination = ""
    @State private var confirmDelete = false
    @State private var showRun = false
    var body: some View {
        if let image = store.selectedImage {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(image.displayName)
                        .font(.title.bold())
                        .textSelection(.enabled)
                    Text(image.digest)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    Button("Run", systemImage: "play.fill") { showRun = true }
                        .buttonStyle(.borderedProminent)
                    Button("Tag") { showTag = true }
                    Button("Push") { store.pushImage(image) }
                    Button("Delete", role: .destructive) { confirmDelete = true }
                    Spacer()
                }
                Divider()
                Form { LabeledContent("Reference", value: image.reference); LabeledContent("Tag", value: image.tag.isEmpty ? "—" : image.tag); LabeledContent("Size", value: image.size.isEmpty ? "—" : image.size); LabeledContent("Created", value: image.createdAt.isEmpty ? "—" : image.createdAt) }.formStyle(.grouped)
                Spacer()
            }.padding(AppLayout.panelPadding)
                .sheet(isPresented: $showRun) { RunContainerView(store: store, initialImage: image.displayName) }
                .sheet(isPresented: $showTag) { VStack(alignment: .leading, spacing: 16) { Text("Tag Image").font(.title.bold()); TextField("New reference", text: $destination); HStack { Spacer(); Button("Cancel") { showTag = false }; Button("Tag") { store.tagImage(image, destination: destination); showTag = false }.buttonStyle(.borderedProminent).disabled(destination.isEmpty) } }.padding(24).frame(width: 480) }
                .confirmationDialog("Delete \(image.displayName)? Containers using it may stop working.", isPresented: $confirmDelete) { Button("Delete Image", role: .destructive) { store.deleteImage(image) } }
        } else { ContentUnavailableView("Select an image", systemImage: "square.stack.3d.up") }
    }
}

struct BuildsView: View {
    @ObservedObject var store: AppStore
    @State private var context = ""
    @State private var dockerfile = ""
    @State private var tag = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader("Build Image", subtitle: "Build an OCI image from a Dockerfile and local context")
                GroupBox("Build configuration") {
                    VStack(alignment: .leading, spacing: 18) {
                        BuildPathField(
                            title: "Build context",
                            help: "Directory containing your Dockerfile and source files",
                            placeholder: "/path/to/project",
                            value: $context,
                            choose: chooseContext
                        )
                        BuildPathField(
                            title: "Dockerfile",
                            help: "Optional — defaults to Dockerfile inside the build context",
                            placeholder: "Use the context default",
                            value: $dockerfile,
                            choose: chooseDockerfile
                        )
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Image tag").fontWeight(.medium)
                            TextField("my-image:latest", text: $tag)
                                .textFieldStyle(.roundedBorder)
                            Text("Name and optional tag for the finished image.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Command preview", systemImage: "terminal")
                                .fontWeight(.medium)
                            Text(CommandLineFormatter.format("container", buildArguments))
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                        HStack {
                            Spacer()
                            Button("Build Image", systemImage: "hammer.fill") {
                                store.build(context: context, dockerfile: dockerfile, tag: tag)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(context.isEmpty)
                        }
                    }.padding(8)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Build activity").font(.title2.bold())
                    if buildOperations.isEmpty {
                        ContentUnavailableView("No builds yet", systemImage: "hammer", description: Text("Completed and running builds will appear here."))
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        ForEach(buildOperations) { operation in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        OperationRow(operation: operation)
                                        if operation.status == .running { Button("Cancel", role: .destructive) { store.cancel(operation) } }
                                    }
                                    if !operation.output.isEmpty {
                                        Divider()
                                        Text(operation.output)
                                            .font(.system(.callout, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(12)
                                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }.padding(6)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(AppLayout.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var buildOperations: [Operation] { store.operations.filter { $0.kind.hasPrefix("Build") } }
    private var buildArguments: [String] { var a = ["build", "--progress", "plain"]; if !dockerfile.isEmpty { a += ["--file", dockerfile] }; if !tag.isEmpty { a += ["--tag", tag] }; a.append(context.isEmpty ? "." : context); return a }
    private func chooseContext() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; if panel.runModal() == .OK { context = panel.url?.path ?? context } }
    private func chooseDockerfile() { let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; if panel.runModal() == .OK { dockerfile = panel.url?.path ?? dockerfile } }
}

private struct BuildPathField: View {
    let title: String
    let help: String
    let placeholder: String
    @Binding var value: String
    let choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fontWeight(.medium)
            HStack(spacing: 10) {
                TextField(placeholder, text: $value)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…", action: choose)
            }
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @AppStorage("cliPath") private var cliPath = ""
    @AppStorage("pollingInterval") private var pollingInterval = 2.0
    @AppStorage("shellCommand") private var shellCommand = "sh"
    @AppStorage("outputRetention") private var outputRetention = 25
    @State private var confirmStop = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("Settings", subtitle: "Configure the CLI, refresh behavior, and diagnostics")

                GroupBox("Apple container") {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("CLI path") {
                            TextField("/usr/local/bin/container", text: $cliPath)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 320)
                        }
                        LabeledContent("Status", value: store.status.title)
                        Divider()
                        HStack {
                            Button("Start Service") { store.startService() }
                            Button("Stop Service", role: .destructive) { confirmStop = true }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Behavior") {
                    VStack(alignment: .leading, spacing: 14) {
                        Stepper("Refresh every \(pollingInterval, specifier: "%.0f") seconds", value: $pollingInterval, in: 1...60)
                        LabeledContent("Container shell") {
                            TextField("sh", text: $shellCommand)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 220)
                        }
                        Stepper("Keep \(outputRetention) operation outputs", value: $outputRetention, in: 5...200)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Support") {
                    HStack(spacing: 14) {
                        Button("Export Diagnostics…") { exportDiagnostics() }
                        Link("Apple container documentation", destination: URL(string: "https://apple.github.io/container/documentation/")!)
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(AppLayout.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Stop the service? Running containers will be stopped.", isPresented: $confirmStop) { Button("Stop Service", role: .destructive) { store.stopService() } }
    }
    private func exportDiagnostics() { let panel = NSSavePanel(); panel.nameFieldStringValue = "container-desktop-diagnostics.txt"; guard panel.runModal() == .OK, let url = panel.url else { return }; try? store.diagnostics().write(to: url, atomically: true, encoding: .utf8) }
}
