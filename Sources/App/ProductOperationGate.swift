import Foundation
import Observation

/// 앱의 설치·활성화·업데이트 교체·제거가 같은 작업권을 공유한다.
@MainActor
@Observable
final class ProductOperationGate {
    enum Operation: Equatable { case installing, activating, updating, removingInputMethod, removingProduct }
    private(set) var operation: Operation?
    private var token: UUID?
    func begin(_ next: Operation) -> UUID? {
        guard operation == nil else { return nil }
        let id = UUID(); token = id; operation = next; return id
    }
    func finish(_ id: UUID) {
        guard token == id else { return }
        token = nil; operation = nil
    }
}

/// Busy를 성공(nil)으로 돌려주지 않는다.
enum ProductOperationError: LocalizedError {
    case busy
    var errorDescription: String? { "설치·업데이트·제거 중인 작업이 있어요. 끝난 뒤 다시 시도해 주세요" }
}
