import Foundation

public struct QuietHours: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var startMinute: Int
    public var endMinute: Int
    public var timeZoneIdentifier: String
    public init(enabled: Bool = true, startMinute: Int = 1380, endMinute: Int = 480, timeZoneIdentifier: String = "UTC") {
        self.enabled = enabled
        self.startMinute = (0..<1440).contains(startMinute) ? startMinute : 1380
        self.endMinute = (0..<1440).contains(endMinute) ? endMinute : 480
        self.timeZoneIdentifier = timeZoneIdentifier
    }
    public func contains(_ date: Date) -> Bool {
        guard enabled, startMinute != endMinute else { return false }
        var calendar = Calendar(identifier: .gregorian)
        // 时区也来自输入；不读 TimeZone.current，保证结果可复现。
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return startMinute < endMinute ? (minute >= startMinute && minute < endMinute) : (minute >= startMinute || minute < endMinute)
    }
}
public struct RuleRuntime: Equatable, Sendable {
    public var triggered = false
    public var hasFired = false
    public var lastAlertAt: Date?
    public init() {}
}
// 字段和阶段一 QuietNotification 一致，可以直接读取旧的待汇总 JSON。
public struct PendingNotice: Codable, Equatable, Sendable {
    public var title: String
    public var body: String
    public var count: Int
    public var lastRecordedAt: Date
}
public struct AlertState: Equatable, Sendable {
    public var rules: [String: RuleRuntime] = [:]
    public var pending: [String: PendingNotice] = [:]
    public var bufferRatio = 0.001
    public var quietHours = QuietHours()
    public var targetUpdates: [String: Double] = [:]
    public init() {}
    public mutating func reset(ruleID: String) { rules[ruleID] = nil; targetUpdates[ruleID] = nil }
}
public struct AlertEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case breach, targetShift, quietSummary, message }
    public enum Delivery: Equatable, Sendable { case immediate, recordOnly }
    public var kind: Kind
    public var delivery: Delivery
    public var identity: String
    public var title: String
    public var body: String
    public var oldTarget: Double?
    public var newTarget: Double?
    public init(kind: Kind, delivery: Delivery = .immediate, identity: String, title: String, body: String,
                oldTarget: Double? = nil, newTarget: Double? = nil) {
        self.kind = kind; self.delivery = delivery; self.identity = identity; self.title = title; self.body = body
        self.oldTarget = oldTarget; self.newTarget = newTarget
    }
}
