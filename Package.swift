// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ContainerDesktop",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "ContainerDesktop", targets: ["ContainerDesktop"])],
    targets: [
        .executableTarget(
            name: "ContainerDesktop",
            path: ".",
            exclude: [
                ".gitignore", "README.md", "PONYTAIL_SKILL.md", "Tests", "Example", "scripts", "Packaging",
                "Assets/container-desktop-app-icon-v3-source.png"
            ],
            sources: ["Sources/ContainerDesktop"],
            resources: [.copy("Assets/container-desktop-app-icon-v3.png")]
        )
    ],
    swiftLanguageModes: [.v6]
)
