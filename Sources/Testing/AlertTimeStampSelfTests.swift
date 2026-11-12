import Foundation

// 提醒时间戳：固定时区与固定日期验证格式、跨日年份规则和「电脑本地时间」语义。
public enum AlertTimeStampSelfTests {
    public static var cases: [SelfTestCase] {
        [SelfTestCase(name: "提醒本地时间戳与跨日年份", run: run)]
    }
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SelfTestFailure(description: message) }
    }
    private static func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
                             _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }
    private static func run() throws {
        let beijing = TimeZone(secondsFromGMT: 8 * 3600)!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = beijing
        let now = date(calendar, 2026, 11, 10, 20, 15, 30)
        try check(AlertTimeStamp.day(now, timeZone: beijing) == "2026-11-10", "本地日期键")
        try check(AlertTimeStamp.text(now, includeYear: false, timeZone: beijing) == "11-10 20:15:30", "当天后续不带年份")
        try check(AlertTimeStamp.text(now, includeYear: true, timeZone: beijing) == "2026-11-10 20:15:30", "当天第一条带年份")
        // 同一绝对时刻换成本机另一个时区，日期与时间都应跟着本地走。
        try check(AlertTimeStamp.text(now, includeYear: true, timeZone: TimeZone(secondsFromGMT: 0)!) == "2026-11-10 12:15:30", "按电脑本地时区")
        let padded = date(calendar, 2026, 1, 2, 3, 4, 5)
        try check(AlertTimeStamp.text(padded, includeYear: false, timeZone: beijing) == "01-02 03:04:05", "补零与分隔符")
        try check(AlertTimeStamp.text(padded, includeYear: true, timeZone: beijing) == "2026-01-02 03:04:05", "带年份同样补零")
        // 日期仍是短横线，时分秒必须是半角冒号，防止回退到旧格式。
        let shortText = AlertTimeStamp.text(padded, includeYear: false, timeZone: beijing)
        try check(shortText.hasPrefix("01-02 ") && shortText.contains("03:04:05") && !shortText.contains("03-04-05"), "日期短横线、时分秒半角冒号")
        // 当天第一条：没有记录、或记录的日期不是今天（含过 0 点）都要带年份。
        try check(AlertTimeStamp.includesYear(lastDay: nil, now: now, timeZone: beijing), "首次提醒带年份")
        try check(!AlertTimeStamp.includesYear(lastDay: "2026-11-10", now: now, timeZone: beijing), "同一天后续不带年份")
        try check(AlertTimeStamp.includesYear(lastDay: "2026-11-09", now: now, timeZone: beijing), "跨日后带年份")
        let afterMidnight = date(calendar, 2026, 11, 11, 0, 0, 1)
        try check(AlertTimeStamp.day(afterMidnight, timeZone: beijing) == "2026-11-11", "过 0 点换新的一天")
        try check(AlertTimeStamp.includesYear(lastDay: "2026-11-10", now: afterMidnight, timeZone: beijing), "过 0 点第一条带年份")
        try check(AlertTimeStamp.text(afterMidnight, includeYear: true, timeZone: beijing) == "2026-11-11 00:00:01", "过 0 点时间格式")
        let later = date(calendar, 2026, 11, 11, 9, 30, 0)
        try check(!AlertTimeStamp.includesYear(lastDay: "2026-11-11", now: later, timeZone: beijing), "新的一天第二条不带年份")
    }
}
