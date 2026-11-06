// swift-tools-version: 5.7
import PackageDescription

#if os(macOS)
let appSources = ["App", "UI", "Services/macOS", "main.swift"]
let appExcludes = ["Models", "Alerts", "Testing", "Services/PriceProvider.swift", "Services/BankPriceParsing.swift",
                   "Services/MinshengProvider.swift", "Services/ICBCProvider.swift", "Services/ZheshangProvider.swift",
                   "Services/SinaProvider.swift", "Services/EastmoneyProvider.swift", "Services/PriceService.swift",
                   "Services/BarkCredentials.swift", "Services/BarkLinkParser.swift", "Services/SinaExchangeRateProvider.swift", "Services/TodayHistoryStore.swift"]
let frameworks: [LinkerSetting] = [.linkedFramework("Cocoa"), .linkedFramework("Security"), .linkedFramework("SwiftUI"), .linkedFramework("UserNotifications"), .linkedFramework("ServiceManagement")]
#else
let appSources = ["main.swift"]
let appExcludes = ["Models", "Alerts", "Testing", "Services", "UI", "App"]
let frameworks: [LinkerSetting] = []
#endif
let package = Package(
    name: "GoldPrice", platforms: [.macOS(.v12)],
    products: [.executable(name: "GoldPrice", targets: ["GoldPrice"])],
    targets: [
        .target(name: "GoldPriceCore", path: "Sources", exclude: ["UI", "App", "main.swift", "Services/macOS"],
                sources: ["Models", "Alerts", "Services", "Testing"]),
        .executableTarget(name: "GoldPrice", dependencies: ["GoldPriceCore"], path: "Sources", exclude: appExcludes,
                          sources: appSources, swiftSettings: [.unsafeFlags(["-parse-as-library"])], linkerSettings: frameworks),
        .testTarget(name: "GoldPriceCoreTests", dependencies: ["GoldPriceCore"], path: "Tests/GoldPriceCoreTests")
    ], swiftLanguageVersions: [.v5]
)
