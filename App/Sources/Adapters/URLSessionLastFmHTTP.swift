import Foundation
import PressingCore

/// Production LastFmHTTP: sends the request the core built and signed, as is.
@MainActor
final class URLSessionLastFmHTTP: LastFmHTTP {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": "Pressing"]
        session = URLSession(configuration: configuration)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if !request.body.isEmpty {
            urlRequest.httpBody = request.body
        }
        let (data, response) = try await session.data(for: urlRequest)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (name, value) in http?.allHeaderFields ?? [:] {
            headers["\(name)"] = "\(value)"
        }
        return HTTPResponse(status: http?.statusCode ?? 0, headers: headers, body: data)
    }
}
