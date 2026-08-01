// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pynkaro",
    platforms: [
        .macOS("13.1") // exigido pelo runtime da Rive
    ],
    dependencies: [
        // Rig 2D animado do avatar (arquivo avatar.riv na raiz do projeto).
        .package(url: "https://github.com/rive-app/rive-ios", from: "6.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Pynkaro",
            dependencies: [
                .product(name: "RiveRuntime", package: "rive-ios")
            ],
            path: "Sources/Pynkaro",
            linkerSettings: [
                // `swift run` gera um executável sem bundle. Embutir o plist no
                // binário permite que o macOS encontre as descrições de uso do
                // microfone e do reconhecimento de fala exigidas pelo TCC.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        )
    ]
)
