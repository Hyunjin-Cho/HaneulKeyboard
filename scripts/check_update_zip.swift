// 2026-11-13 (#226, 좁은 재검토 install P3-5): 배포 스크립트가 만든 ZIP을 앱의 업데이트 목록 검사(`UpdateArchive`)와 **같은 코드**로 본다.
// 앱은 배포 ZIP의 꼴(주석·ZIP64 없음, 모든 항목이 HaneulKeyboard.app/ 아래)에 묶여 있어서, ZIP 만드는 방법이 바뀌면 현장 업데이트가 거부된다.
// 그 어긋남을 빌드에서 멈추게 하는 관문이다. 사용: build_notarize_install.sh가 Sources/UpdateDecisions.swift 등과 함께 컴파일해 돌린다.
// 종료 코드: 0 = 통과, 1 = 거부(이유 출력), 2 = 사용법 오류.
import Foundation

@main
enum CheckUpdateZip {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: check_update_zip <zip>\n".utf8))
            exit(2)
        }
        let path = CommandLine.arguments[1]
        guard let data = FileManager.default.contents(atPath: path) else {
            print("  ✗ update ZIP check: cannot read \(path)")
            exit(1)
        }
        let bytes = [UInt8](data)
        let tail = Array(bytes.suffix(UpdateArchive.tailBytes))
        guard let location = UpdateArchive.directoryLocation(tail: tail, fileSize: bytes.count),
              location.offset + location.size <= bytes.count,
              let entries = UpdateArchive.entries(centralDirectory: Array(bytes[location.offset..<(location.offset + location.size)]),
                                                  expectedCount: location.entries) else {
            print("  ✗ update ZIP check: the in-app updater cannot read this ZIP's directory (comment, ZIP64 or layout changed?)")
            exit(1)
        }
        if let problem = UpdateArchive.problem(entries, limits: .release) {
            print("  ✗ update ZIP check: the in-app updater would refuse this ZIP — \(problem)")
            exit(1)
        }
        print("  ✓ update ZIP check: \(entries.count) entries pass the in-app updater's archive check")
    }
}
