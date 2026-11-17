import Foundation

/// 2026-11-06 (#157): 실행 중인 앱 번들을 지켜보다가 휴지통으로 가거나 지워지면 앱을 끝낸다.
/// 아이콘을 꺼 두면 앱이 떠 있는 줄 모르니, 버린 앱이 로그아웃할 때까지 남고 휴지통 비우기도 막힐 수 있었다.
/// 파일 이벤트로만 깨어나므로 평소에는 아무 일도 하지 않는다(주기 확인 없음).
/// 판단은 `AppBundleWatchDecision`이 맡는다. 입력기 쪽 정리(`OrphanWatcher`)와는 별개다.
@MainActor
final class AppBundleWatcher {
    /// 버렸다가 바로 되돌리는 경우(⌘Z, 제자리에 놓기)가 있어 잠깐 기다렸다 다시 본다.
    private static let grace: TimeInterval = 5

    private let path: String
    private let isBusy: () -> Bool
    private let onGone: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var pending: DispatchWorkItem?

    init(path: String, isBusy: @escaping () -> Bool, onGone: @escaping () -> Void) {
        self.path = path
        self.isBusy = isBusy
        self.onGone = onGone
    }

    func start() {
        source?.cancel()
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { source = nil; return }
        descriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleCheck() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func scheduleCheck() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.grace, execute: work)
    }

    private func check() {
        let current = currentPath()
        let exists = FileManager.default.fileExists(atPath: path)
        if AppBundleWatchDecision.shouldQuit(currentPath: current, originalPathExists: exists, busy: isBusy()) {
            onGone()
        } else if current == nil, exists {
            // 제자리에 새 번들이 들어왔다(교체). 지켜보던 파일은 사라졌으니 새 번들을 다시 지켜본다.
            start()
        }
    }

    /// 지켜보는 번들이 지금 있는 곳. 파일 번호로 따라가므로 옮겨도 찾는다. 지워졌으면 nil이다.
    private func currentPath() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else { return nil }
        let found = String(cString: buffer)
        // 지워진 뒤에는 옛 경로를 돌려줄 수 있어 파일 번호까지 맞춰 본다.
        var open = stat(), named = stat()
        guard fstat(descriptor, &open) == 0, stat(found, &named) == 0, open.st_ino == named.st_ino else { return nil }
        return found
    }
}
