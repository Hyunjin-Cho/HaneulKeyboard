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

    /// Call early, off the typing path (main.swift), so the ~0.5s load
    /// never lands on a keystroke.
    static func preload() {
        DispatchQueue.global(qos: .utility).async { _ = words }
    }

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
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let bytes = buf.bindMemory(to: UInt8.self)
            let newline = UInt8(ascii: "\n")
            let hash = UInt8(ascii: "#")
            var start = 0
            for i in 0..<bytes.count {
                if bytes[i] == newline {
                    if i > start, bytes[start] != hash {
                        set.insert(String(decoding: bytes[start..<i], as: UTF8.self))
                    }
                    start = i + 1
                }
            }
            if start < bytes.count, bytes[start] != hash {
                set.insert(String(decoding: bytes[start...], as: UTF8.self))
            }
        }
        return set
    }()
}
