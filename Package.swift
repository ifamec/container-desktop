// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ContainerDesktop",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "ContainerDesktop", targets: ["ContainerDesktop"])],
    targets: [
        .executableTarget(
            name: "ContainerDesktop",
            path: "Sources/ContainerDesktop"
        )
    ],
    swiftLanguageModes: [.v6]
)
