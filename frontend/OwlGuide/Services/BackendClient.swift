import Foundation
import CommonCrypto

enum BackendClientError: LocalizedError {
    case sampleFileMissing
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case decodingFailed(String)
    case networkFailure(String)

    var errorDescription: String? {
        switch self {
        case .sampleFileMissing:
            return "The bundled local sample response could not be found."
        case .invalidResponse:
            return "The backend returned an invalid response."
        case .httpError(let statusCode, let body):
            return "Backend request failed with HTTP \(statusCode). \(body)"
        case .decodingFailed(let message):
            return "Backend response decoding failed. \(message)"
        case .networkFailure(let message):
            return "Backend request failed. \(message)"
        }
    }
}

struct BackendHTTPResponse<Value> {
    let value: Value
    let rawBody: String
    let statusCode: Int?
}

struct BackendClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    /// API签名密钥，从环境变量读取，编译时注入
    private let apiSignSecret: String = {
        ProcessInfo.processInfo.environment["API_SIGN_SECRET"] ?? "CHANGE_THIS_IN_PRODUCTION"
    }()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration)
        }

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func health(mode: BackendDataSourceMode) async throws -> BackendHTTPResponse<BackendHealthResponse> {
        switch mode {
        case .localSample:
            return BackendHTTPResponse(
                value: BackendHealthResponse(ok: true),
                rawBody: "{\"ok\":true}",
                statusCode: 200
            )
        case .localBackend, .cloudBackend:
            let url = resolvedBaseURL(for: mode).appendingPathComponent("health")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            return try await execute(request, as: BackendHealthResponse.self)
        }
    }

    func analyzeScreen(
        request payload: AnalyzeScreenRequest,
        mode: BackendDataSourceMode
    ) async throws -> BackendHTTPResponse<AnalyzeScreenResponse> {
        switch mode {
        case .localSample:
            let data = try sampleAnalyzeScreenData()
            let response = try decode(AnalyzeScreenResponse.self, from: data)
            let raw = String(data: data, encoding: .utf8) ?? ""
            return BackendHTTPResponse(value: response, rawBody: raw, statusCode: 200)
        case .localBackend, .cloudBackend:
            let url = resolvedBaseURL(for: mode).appendingPathComponent("analyze-screen")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(payload)
            return try await execute(request, as: AnalyzeScreenResponse.self)
        }
    }

    /// 生成SHA256哈希
    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// 给请求添加签名头
    private func addSignatureHeaders(to request: inout URLRequest) {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = sha256("\(timestamp)\(apiSignSecret)")
        request.setValue(timestamp, forHTTPHeaderField: "X-Sign-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-Sign")
        
        // 添加设备唯一标识头，用于后端限流
        request.setValue(AppSettings.shared.anonymousDeviceIdentifier, forHTTPHeaderField: "X-Device-ID")
    }

    private func execute<Value: Decodable>(_ request: URLRequest, as type: Value.Type) async throws -> BackendHTTPResponse<Value> {
        var signedRequest = request
        addSignatureHeaders(to: &signedRequest)
        
        print("[BackendClient] \(signedRequest.httpMethod ?? "GET") \(signedRequest.url?.absoluteString ?? "unknown")")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendClientError.networkFailure(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }

        let rawBody = String(data: data, encoding: .utf8) ?? ""

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BackendClientError.httpError(statusCode: httpResponse.statusCode, body: rawBody)
        }

        let decoded = try decode(type, from: data)
        return BackendHTTPResponse(value: decoded, rawBody: rawBody, statusCode: httpResponse.statusCode)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw BackendClientError.decodingFailed(error.localizedDescription)
        }
    }

    private func resolvedBaseURL(for mode: BackendDataSourceMode) -> URL {
        switch mode {
        case .localSample:
            return BackendEnvironment.localBackendBaseURL
        case .localBackend:
            return BackendEnvironment.localBackendBaseURL
        case .cloudBackend:
            return BackendEnvironment.cloudBackendBaseURL
        }
    }

    private func sampleAnalyzeScreenData() throws -> Data {
        guard let url = Bundle.main.url(forResource: BackendEnvironment.sampleResponseResourceName, withExtension: "json") else {
            throw BackendClientError.sampleFileMissing
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            throw BackendClientError.sampleFileMissing
        }
    }
}
