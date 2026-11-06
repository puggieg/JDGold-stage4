import Foundation

// 本地文件 I/O 放在 actor 内，不阻塞 AppKit 主线程；规则 UserDefaults 不受影响。
public actor TodayHistoryStore {
    private struct Archive: Codable {
        let version: Int
        let timeZone: String
        let day: String
        let prices: [String: [MinutePriceSample]]
    }
    private let fileURL: URL
    private let log: @Sendable (String, String) -> Void
    private var cached: TodayPriceHistory?
    private var writesBlocked = false
    private var dirty = false
    private var lastSavedMinute: Date?
    public init(fileURL: URL, log: @escaping @Sendable (String, String) -> Void = { _, _ in }) {
        self.fileURL = fileURL; self.log = log
    }
    private func restore(now: Date) -> TodayPriceHistory {
        if let cached = cached { return cached }
        let empty = TodayPriceHistory(day: MarketDay.key(now))
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return empty }
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
            guard archive.version == 1, archive.timeZone == MarketDay.timeZoneIdentifier else { throw PriceError.invalidPayload }
            // 把旧日标识交给 recording 清空并写回，不能只清内存却留下昨日文件。
            guard archive.day == empty.day else { return TodayPriceHistory(day: archive.day) }
            var values: [Instrument: [MinutePriceSample]] = [:]
            for (key, samples) in archive.prices {
                guard let instrument = Instrument(rawValue: key), samples.count <= 1440,
                      samples.allSatisfy({ $0.isValid && MarketDay.key($0.observedAt) == archive.day }),
                      Set(samples.map { $0.minute }).count == samples.count else { throw PriceError.invalidPayload }
                values[instrument] = samples.filter { $0.observedAt <= now }.sorted { $0.minute < $1.minute }
            }
            return TodayPriceHistory(day: archive.day, values: values)
        } catch {
            log("今日走势", "本地记录无法读取，已保留原文件并使用空记录")
            // 保留损坏/未知版本文件，避免下一轮正常采样静默覆盖它。
            let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(UUID().uuidString).json")
            do { try FileManager.default.moveItem(at: fileURL, to: backup) }
            catch { writesBlocked = true; log("今日走势", "无法备份原记录，暂停写入以保留原文件") }
            return empty
        }
    }
    public func snapshot(now: Date) -> TodayPriceHistory {
        let restored = restore(now: now)
        let changed = TodayPriceHistory.recording(GoldPrices(), in: restored, now: now)
        if changed != restored { dirty = true; _ = persist(changed, now: now) }
        cached = changed; return changed
    }
    public func record(_ prices: GoldPrices, now: Date) -> TodayPriceHistory {
        let old = restore(now: now)
        let changed = TodayPriceHistory.recording(prices, in: old, now: now)
        if changed != old {
            dirty = true
            // 每分钟至多做一次常规文件写入；下一分钟也带上前一分钟的最终高低值。
            if lastSavedMinute != MarketDay.minute(now) || changed.day != old.day { _ = persist(changed, now: now) }
        }
        cached = changed; return changed
    }
    public func flush(now: Date) {
        let history = snapshot(now: now)
        if dirty { _ = persist(history, now: now) }
    }
    @discardableResult private func persist(_ history: TodayPriceHistory, now: Date) -> Bool {
        guard !writesBlocked else { return false }
        let archive = Archive(version: 1, timeZone: MarketDay.timeZoneIdentifier, day: history.day,
                              prices: Dictionary(uniqueKeysWithValues: history.values.map { ($0.key.rawValue, $0.value) }))
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(archive)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            dirty = false; lastSavedMinute = MarketDay.minute(now); return true
        } catch { log("今日走势", "本地保存失败，仍显示内存采样；重启后可能丢失今日记录"); return false }
    }
}
