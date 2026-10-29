import Foundation
import CoreGraphics

public enum SidebarEdge: String { case left, right }

/// Screen coordinates stay in AppKit's global coordinate space, including negative monitor origins.
public enum SidebarGeometry {
    public static let quickControlsSize = CGSize(width: 240, height: 210)

    public static func nearbyEdge(frame: CGRect, screen: CGRect, threshold: CGFloat = 24) -> SidebarEdge? {
        let left = abs(frame.minX - screen.minX)
        let right = abs(frame.maxX - screen.maxX)
        guard min(left, right) <= threshold else { return nil }
        return left <= right ? .left : .right
    }

    public static func nearestEdge(frame: CGRect, screen: CGRect) -> SidebarEdge {
        abs(frame.minX - screen.minX) <= abs(frame.maxX - screen.maxX) ? .left : .right
    }

    public static func dockedFrame(_ frame: CGRect, screen: CGRect, edge: SidebarEdge) -> CGRect {
        let width = min(frame.width, screen.width)
        let height = min(frame.height, screen.height)
        return CGRect(x: edge == .left ? screen.minX : screen.maxX - width,
                      y: min(max(frame.minY, screen.minY), screen.maxY - height), width: width, height: height)
    }

    public static func handleFrame(window: CGRect, screen: CGRect, edge: SidebarEdge) -> CGRect {
        let width: CGFloat = 52
        let height = min(164, screen.height)
        return CGRect(x: edge == .left ? screen.minX : screen.maxX - width,
                      y: min(max(window.midY - height / 2, screen.minY), screen.maxY - height), width: width, height: height)
    }
    public static func quickControlsFrame(handle: CGRect, screen: CGRect, edge: SidebarEdge) -> CGRect {
        let width = min(quickControlsSize.width, screen.width - 16)
        let height = min(quickControlsSize.height, screen.height - 16)
        let x = edge == .left ? handle.maxX + 8 : handle.minX - width - 8
        return CGRect(x: min(max(x, screen.minX + 8), screen.maxX - width - 8),
                      y: min(max(handle.midY - height / 2, screen.minY + 8), screen.maxY - height - 8), width: width, height: height)
    }

}
