// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SkillSet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SkillSetCore", targets: ["SkillSetCore"]),
        // 产品名不能只靠大小写区分，否则大小写不敏感的 macOS 会选错二进制。
        .executable(name: "SkillSetDesktop", targets: ["SkillSetApp"]),
        .executable(name: "skillset", targets: ["SkillSetCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.6.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0"),
        .package(url: "https://github.com/cucumberswift/cucumberswift.git", from: "6.7.0")
    ],
    targets: [
        .target(
            name: "SkillSetCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "SkillSetApp",
            dependencies: ["SkillSetCore", .product(name: "Sparkle", package: "Sparkle"),
                           .product(name: "Markdown", package: "swift-markdown")],
            resources: [.process("Resources")],
            linkerSettings: [
                // SwiftPM 不负责组装 .app，打包后从包内查找更新框架。
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .executableTarget(
            name: "SkillSetCLI",
            dependencies: ["SkillSetCore"]
        ),
        .testTarget(
            name: "SkillSetCoreTests",
            dependencies: ["SkillSetCore"]
        ),
        .testTarget(
            name: "SkillSetAppTests",
            dependencies: ["SkillSetApp"]
        ),
        .testTarget(
            name: "SkillSetBDDTests",
            dependencies: [
                "SkillSetCore",
                "SkillSetApp",
                .product(name: "CucumberSwift", package: "cucumberswift")
            ],
            resources: [
                .copy("Features")
            ]
        )
    ]
)
