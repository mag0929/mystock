import Foundation

protocol HTTPClient: Sendable {
    func data(from url: URL, headers: [String: String]) async throws -> Data
}

struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(from url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw QuoteError.httpStatus(http.statusCode)
        }
        return data
    }
}

enum QuoteError: Error {
    case httpStatus(Int)
    case noUsablePrice(symbol: String)
    case malformedResponse(source: String)
}