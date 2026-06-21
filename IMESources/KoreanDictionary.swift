import Foundation

/// 우리말샘 표제어 목록(국립국어원, CC-BY-SA 2.0 KR) — "이 한글이 실제
/// 한국어 단어인가"를 답하는 읽기 전용 veto 사전.
///
/// 역할: 영타 자동 변환이 멀쩡히 조합된 한글(clean Hangul)을 영어로
/// 바꾸기 전의 최후 안전망. 사전에 있으면(모든/랙/내) 절대 변환하지 않고,
/// 없으면(며새) 영어 후보가 된다. 67.7만 단어(1~6음절), 약 8MB.
///
/// 데이터는 읽기 전용이며 어떤 입력도 기록하지 않는다 (PRIVACY.md).
enum KoreanDictionary {
    /// Overridable for tests — set before first lookup (lazy load).
    static var wordlistPath: String? =
        Bundle.main.path(forResource: "korean_words", ofType: "txt")

    /// True if the string is a known Korean headword. Empty/unloaded
    /// dictionary returns false (veto simply doesn't fire — safe default
    /// is "treat as not-a-known-word", which keeps conversion CONSERVATIVE
    /// only when combined with the English-dict gate).
    static func contains(_ word: String) -> Bool {
        return words.contains(word)
    }

    /// (H-10/H-04) 사전이 **온전히** 로드됐는지. EnglishDetector가 이 값으로
    /// fail-closed(사전이 정상이 아니면 자동변환 자체를 끔)를 판단한다.
    /// - 빈 Set → 로딩 실패(번들 누락·읽기 실패).
    /// - 헤더에 `# count: N`이 있으면 실제 로드 수와 **정확히 일치**해야 한다
    ///   (부분 손상/절반 패키징/생성 중단을 잡는다). 매직넘버를 하드코딩하지
    ///   않고 파일 자신이 선언한 값과 대조한다.
    /// - 헤더가 없는 구버전 파일은 "심하게 잘림/빈 파일"만 거른다(낮은 floor).
    static var isLoaded: Bool {
        let n = words.count        // 로드 트리거 — declaredCount도 이때 채워진다
        guard n > 0 else { return false }
        if declaredCount >= 0 {
            return n == declaredCount
        }
        return n >= 1000
    }

    /// Call early, off the typing path (main.swift), so the ~0.5s load
    /// never lands on a keystroke.
    static func preload() {
        DispatchQueue.global(qos: .utility).async { _ = words }
    }

    /// 사전 헤더 `# count: N`에 선언된 기대 표제어 수 (헤더 없으면 -1).
    /// words 로드와 함께 채워지며, isLoaded가 실제 로드 수와 대조해 부분 손상을
    /// fail-closed로 잡는 데 쓴다. (H-04)
    private static var declaredCount: Int = -1

    /// mmap + 단일 패스 바이트 스캔 로더. String(contentsOfFile)+split은
    /// 임시 버퍼(파일 String + 67만 Substring 배열)가 malloc 캐시에 갇혀
    /// 상주 82MB를 만들었다(리뷰 실측) — mmap은 파일 페이지가 클린이라
    /// 상주 ~22MB(Set 실데이터)로 끝나고 로드도 ~2.5배 빠르다.
    private static let words: Set<String> = {
        guard let path = wordlistPath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
            return []
        }
        var set = Set<String>()
        set.reserveCapacity(700_000)
        var declared = -1
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let bytes = buf.bindMemory(to: UInt8.self)
            let newline = UInt8(ascii: "\n")
            let hash = UInt8(ascii: "#")
            var start = 0
            for i in 0..<bytes.count {
                if bytes[i] == newline {
                    if i > start {
                        if bytes[start] == hash {
                            if let n = parseCountHeader(bytes[start..<i]) { declared = n }
                        } else {
                            set.insert(String(decoding: bytes[start..<i], as: UTF8.self))
                        }
                    }
                    start = i + 1
                }
            }
            if start < bytes.count {
                if bytes[start] == hash {
                    if let n = parseCountHeader(bytes[start..<bytes.count]) { declared = n }
                } else {
                    set.insert(String(decoding: bytes[start...], as: UTF8.self))
                }
            }
        }
        declaredCount = declared
        return set
    }()

    /// `# count: N` 주석 줄에서 N을 파싱한다. 아니면 nil. (H-04)
    private static func parseCountHeader<C: Collection>(_ bytes: C) -> Int?
    where C.Element == UInt8 {
        let line = String(decoding: bytes, as: UTF8.self)
        guard let r = line.range(of: "count:") else { return nil }
        return Int(line[r.upperBound...].trimmingCharacters(in: .whitespaces))
    }
}
