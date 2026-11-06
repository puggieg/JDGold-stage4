import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
public struct SinaProvider: PriceProvider {
    public init() {}
    public let source = MarketSource.sina
    public let instruments: [Instrument] = [.london, .newyork]
    public func makeRequest() throws -> URLRequest {
        var request = URLRequest(url: try PriceParsing.url("https://hq.sinajs.cn/list=hf_XAU,hf_GC"))
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        return request
    }
    public func parse(_ data: Data) throws -> ProviderResult {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb) else { throw PriceError.invalidPayload }
        var values: [Instrument: PriceInfo] = [:]
        for line in text.components(separatedBy: ";") {
            if line.contains("hf_XAU") { values[.london] = parseSinaLine(line) }
            else if line.contains("hf_GC") { values[.newyork] = parseSinaLine(line) }
        }
        return ProviderResult(prices: values)
    }
}

// 2026-10-14 真实 curl（未更改接口 URL 或参数）：
// curl -H 'Referer: https://finance.sina.com.cn' 'https://hq.sinajs.cn/list=hf_XAU,hf_GC'
// GB18030 响应样例：
// var hq_str_hf_XAU="4149.30,4161.000,4149.30,4149.65,4170.25,4143.26,15:54:00,4161.00,4161.97,0,0,0,2026-10-14,伦敦金（现货黄金）";
// var hq_str_hf_GC="4171.890,,4172.300,4172.600,4193.500,4165.500,15:54:39,4177.300,4184.200,0,3,2,2026-10-14,纽约黄金,0";
// 核对结论：parts[7] 是昨收，parts[8] 是今开；parts[1] 对 GC 为空，不能用于昨收回退。
// 另核对新浪自己的 stockhq.js：拆分数组先 unshift(code)，因此显示层索引比原响应大 1。
// stock20220424.js 的外盘映射：yestoday-price=arr[8]、open-price=arr[9]，对应原始 parts[7]/parts[8]。
// https://stock2.finance.sina.com.cn/futures/page2012/js/stockhq.js
// https://n.sinaimg.cn/finance/futures/stock20220424.js
// 本次 XAU 的 parts[1] 与昨收恰好相等，不能据此认定第二字段就是昨收。
// 阶段三 2026-10-14 本次真实 curl（同 URL/Referer）来源时间核对：
// var hq_str_hf_XAU="4098.19,4161.000,4098.19,4098.54,4170.25,4079.56,22:37:00,4161.00,4161.97,0,0,0,2026-10-14,伦敦金（现货黄金）";
// var hq_str_hf_GC="4119.908,,4121.200,4121.500,4193.500,4101.600,22:38:32,4177.300,4184.200,0,3,1,2026-10-14,纽约黄金,0";
// parts[6] 时间 + parts[12] 日期，均按北京时间解析；昨收继续为 parts[7]。
public func parseSinaLine(_ line: String) -> PriceInfo {
    var info = PriceInfo()
    guard let start = line.firstIndex(of: "\""), let end = line.lastIndex(of: "\""), start < end else { return info }
    let parts = String(line[line.index(after: start)..<end]).components(separatedBy: ",")
    guard parts.count > 7, let currentPrice = Double(parts[0]), currentPrice.isFinite, currentPrice > 0,
          let yesterdayPrice = Double(parts[7]), yesterdayPrice.isFinite, yesterdayPrice > 0 else { return info }
    info.price = String(format: "%.2f", currentPrice)
    info.yesterdayPrice = String(format: "%.2f", yesterdayPrice)
    let change = currentPrice - yesterdayPrice
    let percent = change / yesterdayPrice * 100
    let sign = change > 0 ? "+" : ""
    info.changeAmount = "\(sign)\(String(format: "%.2f", change))"
    info.changeRate = "\(sign)\(String(format: "%.2f", percent))%"
    // 来源北京时间：原始 parts[6] 是时间，parts[12] 是日期。
    if parts.count > 12 { info.sourceUpdatedAt = SourceTimestamp.sina(date: parts[12], time: parts[6]) }
    return info
}

