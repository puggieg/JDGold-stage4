import Foundation

public struct PanelFrame: Codable, Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var valid: Bool { [x,y,width,height].allSatisfy { $0.isFinite } && width > 0 && height > 0 }
}
public struct PanelScreen {
    public var id: String; public var frame: PanelFrame
    public init(id: String, frame: PanelFrame) { self.id = id; self.frame = frame }
}
public enum FloatingGeometry {
    public static func fit(_ saved: PanelFrame, preferredID: String?, screens: [PanelScreen]) -> PanelFrame {
        let available = screens.filter { $0.frame.valid }
        guard saved.valid, !available.isEmpty else { return saved }
        func area(_ frame: PanelFrame) -> Double {
            max(0, min(saved.x + saved.width, frame.x + frame.width) - max(saved.x, frame.x)) *
            max(0, min(saved.y + saved.height, frame.y + frame.height) - max(saved.y, frame.y))
        }
        let screen = available.first { $0.id == preferredID } ?? available.max { area($0.frame) < area($1.frame) }!
        let f = screen.frame; let w = min(saved.width, f.width); let h = min(saved.height, f.height)
        return PanelFrame(x: min(max(saved.x, f.x), f.x + f.width - w), y: min(max(saved.y, f.y), f.y + f.height - h), width: w, height: h)
    }
}
