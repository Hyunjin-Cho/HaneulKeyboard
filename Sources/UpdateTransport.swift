import Foundation
import Darwin

/// #66: JSON과 ZIP 모두 받는 도중 상한을 검사한다. ZIP은 메모리에 모으지 않는다.
/// 상태는 URLSession delegate와 시작/취소가 공유하는 직렬 큐에서만 접근한다.
final class UpdateTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.hyunjincho.haneul.update-transfer")
    private let limit: Int
    private let destination: URL?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var received = 0
    private var file: FileHandle?
    private var ownsFile = false
    private var cancelled = false

    private init(limit: Int, destination: URL?) {
        self.limit = limit
        self.destination = destination
    }

    static func receive(_ request: URLRequest, configuration: URLSessionConfiguration,
                        limit: Int, destination: URL? = nil) async throws -> (Data, HTTPURLResponse) {
        let transfer = UpdateTransport(limit: limit, destination: destination)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transfer.queue.async {
                    transfer.start(request, configuration: configuration, continuation: continuation)
                }
            }
        } onCancel: {
            transfer.queue.async {
                transfer.cancelled = true
                transfer.finish(.failure(CancellationError()))
            }
        }
    }

    private func start(_ request: URLRequest, configuration: URLSessionConfiguration,
                       continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) {
        self.continuation = continuation
        if cancelled { finish(.failure(CancellationError())); return }
        guard limit > 0, let url = request.url, UpdateDecision.isAllowedURL(url) else {
            finish(.failure(UpdateError.redirectBlocked(request.url?.absoluteString ?? "?")))
            return
        }
        if let destination {
            // 이미 존재하는 파일이나 심볼릭 링크를 덮어쓰지 않는다.
            let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else {
                finish(.failure(NSError(domain: NSPOSIXErrorDomain, code: Int(errno))))
                return
            }
            ownsFile = true
            file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        }
        let delegates = OperationQueue()
        delegates.maxConcurrentOperationCount = 1
        delegates.underlyingQueue = queue
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegates)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard continuation != nil else { completionHandler(.cancel); return }
        guard let http = response as? HTTPURLResponse, let url = http.url,
              UpdateDecision.isAllowedURL(url) else {
            completionHandler(.cancel)
            finish(.failure(UpdateError.malformedResponse))
            return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel)
            finish(.failure(UpdateError.responseTooLarge(limit)))
            return
        }
        self.response = http
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard continuation != nil else { return }
        // Content-Length가 없거나 거짓이어도 실제 받은 바이트를 별도로 제한한다.
        guard chunk.count <= limit - received else {
            finish(.failure(UpdateError.responseTooLarge(limit)))
            return
        }
        do {
            if let file { try file.write(contentsOf: chunk) }
            else { data.append(chunk) }
            received += chunk.count
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard continuation != nil, let url = request.url, UpdateDecision.isAllowedURL(url) else {
            completionHandler(nil)
            finish(.failure(UpdateError.redirectBlocked(request.url?.absoluteString ?? "?")))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        else if let response { finish(.success((data, response))) }
        else { finish(.failure(UpdateError.malformedResponse)) }
    }

    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        guard let continuation else { return } // 취소/완료 중복 시 한 번만 재개한다.
        self.continuation = nil
        var result = result
        do { try file?.close() } catch { result = .failure(error) }
        file = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        if case .failure = result, ownsFile, let destination {
            try? FileManager.default.removeItem(at: destination)
        }
        data = Data()
        continuation.resume(with: result)
    }
}
