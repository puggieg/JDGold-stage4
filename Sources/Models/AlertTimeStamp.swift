import Foundation

// 提醒时间戳：用电脑本地时区的公历，格式 MM-DD hh:mm:ss（日期用短横线、时分秒用半角冒号）。
// 每天第一条（含跨过 0 点后的第一条）带年份 YYYY-MM-DD hh:mm:ss，其余不带。
// 纯函数，日期与时间都由调用方传入，便于固定输入验证，不读系统时钟之外的状态。
public enum AlertTimeStamp {
    // 记录「上次已经提醒过的本地日期」，跨日比较用；写入由 App 层负责。
    public static let lastDayKey = "lastAlertLocalDay"

    public static func calendar(_ timeZone: TimeZone = .current) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        let parts = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    public static func text(_ date: Date, includeYear: Bool, timeZone: TimeZone = .current) -> String {
        let parts = calendar(timeZone).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let short = String(format: "%02d-%02d %02d:%02d:%02d",
                           parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        return includeYear ? String(format: "%04d-", parts.year ?? 0) + short : short
    }
    // 上次提醒日期为空或与今天不同（含过 0 点）时，这一条要带年份。
    public static func includesYear(lastDay: String?, now: Date, timeZone: TimeZone = .current) -> Bool {
        lastDay != day(now, timeZone: timeZone)
    }
}
