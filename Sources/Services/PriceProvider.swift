import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MarketSource: String, Sendable { case minsheng, icbc, zheshang, sina, eastmoney }
public struct ProviderResult: Sendable {
    public var prices: [Instrument: PriceInfo]
    public init(prices: [Instrument: PriceInfo]) { self.prices = prices }
}
public protocol PriceProvider: Sendable {
    var source: MarketSource { get }
    var instruments: [Instrument] { get }
    func makeRequest() throws -> URLRequest
    func parse(_ data: Data) throws -> ProviderResult
}
public enum PriceError: Error { case invalidURL, invalidHTTP, invalidPayload }
public protocol PriceHTTPClient: Sendable { func data(for request: URLRequest) async throws -> Data }
public final class HTTPClient: PriceHTTPClient, @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        if let session = session { self.session = session }
        else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: config)
        }
    }
    public func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PriceError.invalidHTTP }
        return data
    }
}
public enum PriceParsing {
    public static func decodeJSON<T: Decodable>(_ type: T.Type, data: Data) throws -> T { try JSONDecoder().decode(type, from: data) }
    public static func url(_ value: String) throws -> URL {
        guard let url = URL(string: value) else { throw PriceError.invalidURL }; return url
    }
    public static func number(_ value: Double, precision: Int = 2) -> String { String(format: "%.*f", precision, value) }
}
public enum RetryPolicy {
    public static func delay(failures: Int) -> TimeInterval { min(60, pow(2, Double(min(max(failures, 1), 6)))) }
}
