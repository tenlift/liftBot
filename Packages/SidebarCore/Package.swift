// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SidebarCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SidebarCore", targets: ["SidebarCore"])],
    targets: [.target(name: "SidebarCore")]
)
