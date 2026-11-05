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
    nonisolated(unsafe) static var wordlistPath: String? =
        Bundle.main.path(forResource: "korean_words", ofType: "txt")

    /// True if the string is a known Korean headword. Empty/unloaded
    /// dictionary returns false (veto simply doesn't fire — safe default
    /// is "treat as not-a-known-word", which keeps conversion CONSERVATIVE
    /// only when combined with the English-dict gate).
    static func contains(_ word: String) -> Bool {
        return words.contains(word)
    }

    /// 2026-11-06 (#152): 지금까지 친 글자가 더 긴 표제어로 이어질 수 있는가.
    /// 입력 중 조사 미리보기를 미루는 데만 쓴다. 헷가 → gpt가로 비친 뒤 헷갈리게로 돌아오던 깜빡임을 막는다.
    /// 확정 판정에는 쓰지 않는다 — 헷가를 그대로 끝내면 Space에서 gpt가가 맞다.
    /// 끝 글자는 받침이 더 붙거나(가 → 갈) 다음 글자로 넘어갈 수 있어(은 → 으니) 그 경우까지 본다.
    /// 파일을 읽지 못하면 false — 예전 동작(미리보기)으로 돌아갈 뿐 입력을 막지 않는다.
    static func mayContinue(_ hangul: String) -> Bool {
        guard let last = hangul.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return false }
        let head = Array(String(String.UnicodeScalarView(hangul.unicodeScalars.dropLast())).utf8)
        func key(_ suffix: UInt32...) -> [UInt8] {
            var out = head
            for value in suffix { out += Array(String(UnicodeScalar(value)!).utf8) }
            return out
        }
        let finalIndex = Int((last.value - 0xAC00) % 28)
        let open = last.value - UInt32(finalIndex)
        if finalIndex == 0 { return hasWord(from: key(open), below: key(open + 28)) }
        if hasWord(from: key(last.value), below: key(last.value + 1)) { return true }
        if let compound = compoundFinals[finalIndex],
           hasWord(from: key(open + UInt32(compound.lowerBound)), below: key(open + UInt32(compound.upperBound))) {
            return true
        }
        if let onset = finalToOnset[finalIndex] {
            let first = 0xAC00 + UInt32(onset) * 588
            return hasWord(from: key(open, first), below: key(open, first + 588))
        }
        return false
    }

    /// 겹받침으로 늘어나는 받침 번호 (ㄱ→ㄳ, ㄴ→ㄵㄶ, ㄹ→ㄺ~ㅀ, ㅂ→ㅄ)
    private static let compoundFinals: [Int: Range<Int>] = [1: 3..<4, 4: 5..<7, 8: 9..<16, 17: 18..<19]
    /// 받침 번호 → 다음 글자 첫소리 번호. ㅇ 받침은 첫소리로 넘어가지 않는다.
    private static let finalToOnset: [Int: Int] = [1: 0, 2: 1, 4: 2, 7: 3, 8: 5, 16: 6, 17: 7, 19: 9, 20: 10,
                                                  22: 12, 23: 14, 24: 15, 25: 16, 26: 17, 27: 18]

    /// 표제어 파일은 UTF-8 바이트 순으로 정렬돼 있다(테스트가 지킨다). 메모리를 더 쓰지 않으려고
    /// Set을 복제하지 않고 파일을 필요할 때 매핑해 이진 탐색한다. 미리보기 후보가 있을 때만 불린다.
    private static let sortedFile: Data? = wordlistPath.flatMap {
        try? Data(contentsOf: URL(fileURLWithPath: $0), options: .mappedIfSafe)
    }

    private static func hasWord(from lower: [UInt8], below upper: [UInt8]) -> Bool {
        guard let sortedFile else { return false }
        return sortedFile.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let bytes = raw.bindMemory(to: UInt8.self)
            let newline = UInt8(ascii: "\n"), hash = UInt8(ascii: "#")
            func lineEnd(_ start: Int) -> Int {
                var end = start
                while end < bytes.count, bytes[end] != newline { end += 1 }
                return end
            }
            var lo = 0
            while lo < bytes.count, bytes[lo] == hash { lo = lineEnd(lo) + 1 }   // 머리 주석은 정렬 대상이 아니다
            let floor = lo
            var hi = bytes.count
            while lo < hi {
                var mid = (lo + hi) / 2
                while mid > floor, bytes[mid - 1] != newline { mid -= 1 }
                let end = lineEnd(mid)
                if bytes[mid..<end].lexicographicallyPrecedes(lower) { lo = end + 1 } else { hi = mid }
            }
            guard lo < bytes.count else { return false }
            return bytes[lo..<lineEnd(lo)].lexicographicallyPrecedes(upper)
        }
    }

    /// (H-10/H-04) 사전이 **온전히** 로드됐는지. EnglishDetector가 이 값으로
    /// fail-closed(사전이 정상이 아니면 자동변환 자체를 끔)를 판단한다.
    /// - 빈 Set → 로딩 실패(번들 누락·읽기 실패).
    /// - 헤더에 `# count: N`이 있으면 실제 로드 수와 **정확히 일치**해야 한다
    ///   (부분 손상/절반 패키징/생성 중단을 잡는다). 매직넘버를 하드코딩하지
    ///   않고 파일 자신이 선언한 값과 대조한다.
    /// - 헤더가 없으면 로드 실패로 본다. production 사전은 count 헤더가 필수다.
    static var isLoaded: Bool {
        let n = words.count        // 로드 트리거 — declaredCount도 이때 채워진다
        guard n > 0 else { return false }
        if declaredCount >= 0 {
            return n == declaredCount
        }
        return false
    }

    /// Call early, off the typing path (main.swift), so the ~0.5s load
    /// never lands on a keystroke.
    static func preload() {
        DispatchQueue.global(qos: .utility).async { _ = words }
    }

    /// 사전 헤더 `# count: N`에 선언된 기대 표제어 수 (헤더 없으면 -1).
    /// words 로드와 함께 채워지며, isLoaded가 실제 로드 수와 대조해 부분 손상을
    /// fail-closed로 잡는 데 쓴다. (H-04)
    nonisolated(unsafe) private static var declaredCount: Int = -1

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
                        } else if let s = String(bytes: bytes[start..<i], encoding: .utf8) {
                            set.insert(s)   // (위생-2) 깨진 UTF-8 줄은 스킵
                        }
                    }
                    start = i + 1
                }
            }
            if start < bytes.count {
                if bytes[start] == hash {
                    if let n = parseCountHeader(bytes[start..<bytes.count]) { declared = n }
                } else if let s = String(bytes: bytes[start..<bytes.count], encoding: .utf8) {
                    set.insert(s)   // (위생-2) 깨진 UTF-8 줄은 스킵
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
