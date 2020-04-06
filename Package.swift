// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "XCDYouTubeKit",
    platforms: [
        .iOS(.v8),
        .tvOS(.v9),
        .macOS(.v10_10)
    ],
    products: [
        .library(name: "XCDYouTubeKit" , targets: ["XCDYouTubeKit"])
    ],
    targets: [
        .target(
            name: "XCDYouTubeKit",
            path: ".",
			exclude:[
				"XCDYouTubeKit/AppledocSettings.plist",
				"XCDYouTubeKit/Configuration.plist",
				"XCDYouTubeKit/Info.plist",
			],
            sources: ["XCDYouTubeKit"],
            publicHeadersPath: "XCDYouTubeKit"
        )
    ]
)
