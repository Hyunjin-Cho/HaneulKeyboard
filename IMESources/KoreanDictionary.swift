import Foundation

/// 우리말샘 표제어 목록(국립국어원, CC-BY-SA 2.0 KR) — "이 한글이 실제
/// 한국어 단어인가"를 답하는 읽기 전용 veto 사전.
///
/// 역할: 영타 자동 변환이 멀쩡히 조합된 한글(clean Hangul)을 영어로
/// 바꾸기 전의 최후 안전망. 사전에 있으면(모든/랙/내) 절대 변환하지 않고,
/// 없으면(며새) 영어 후보가 된다. 67.7만 단어(1~6음절), 약 8MB.
///
/// 데이터는 읽기 전용이며 어떤 입력도 기록하지 않는다 (PRIVACY.md).
///
/// 2026-11-06 (#162): Set<String>으로 올리던 것을 파일 매핑 + 이진 탐색으로 바꿨다.
/// Set은 해시 표 16MB(100만 칸 × 16B) + 6음절 낱말 8.9만 개의 힙 문자열 ~6MB를 차지했다(실측 22MB).
/// 매핑한 파일 페이지는 깨끗한(clean) 페이지라 phys_footprint에 들지 않고, 메모리가 모자라면 OS가 버렸다가 다시 읽는다.
/// 파일은 UTF-8 바이트 순으로 정렬돼 있어야 한다(테스트가 지킨다) — 정렬이 깨졌으면 로드 실패로 보고 자동 변환을 끈다(fail-closed).
enum KoreanDictionary {
    /// Overridable for tests — set before first lookup (lazy load).
    nonisolated(unsafe) static var wordlistPath: String? =
        Bundle.main.path(forResource: "korean_words", ofType: "txt")

    /// True if the string is a known Korean headword. Empty/unloaded
    /// dictionary returns false (veto simply doesn't fire — safe default
    /// is "treat as not-a-known-word", which keeps conversion CONSERVATIVE
    /// only when combined with the English-dict gate).
    static func contains(_ word: String) -> Bool {
        guard let table else { return false }
        return table.contains(Array(word.utf8))
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

    private static func hasWord(from lower: [UInt8], below upper: [UInt8]) -> Bool {
        guard let table else { return false }
        return table.hasWord(from: lower, below: upper)
    }

    /// (H-10/H-04) 사전이 **온전히** 로드됐는지. EnglishDetector가 이 값으로
    /// fail-closed(사전이 정상이 아니면 자동변환 자체를 끔)를 판단한다.
    /// - 표제어 0개 → 로딩 실패(번들 누락·읽기 실패).
    /// - 헤더에 `# count: N`이 있으면 서로 다른 표제어 수와 **정확히 일치**해야 한다
    ///   (부분 손상/절반 패키징/생성 중단을 잡는다). 매직넘버를 하드코딩하지
    ///   않고 파일 자신이 선언한 값과 대조한다.
    /// - 헤더가 없거나 정렬이 깨졌으면 로드 실패로 본다. production 사전은 count 헤더와 정렬이 필수다.
    static var isLoaded: Bool { table?.isComplete ?? false }

    /// Call early, off the typing path (main.swift), so the file scan
    /// never lands on a keystroke.
    static func preload() {
        DispatchQueue.global(qos: .utility).async { _ = table }
    }

    private static let table: SortedWordTable? = wordlistPath.flatMap { SortedWordTable(path: $0) }
}

/// UTF-8 바이트 순으로 정렬된 "한 줄 = 한 낱말" 바이트열(매핑한 파일 또는 메모리 덩어리) 위의 읽기 전용 이진 탐색 표.
/// 머리의 `#` 주석 줄은 건너뛴다. 매 `anchorStride`번째 줄의 위치만 따로 둔다(67.7만 줄 → 약 40KB)
/// — 조회 한 번이 성긴 색인 안에서 이진 탐색한 뒤 줄 몇 십 개만 훑으므로 파일 페이지를 한두 장만 건드린다.
/// 비교는 바이트 단위다. Set<String>과 달리 NFC·NFD를 같게 보지 않는다. 표제어는 전부 NFC이고 찾는 쪽은 조합기가 만든 완성형이다(2026-11-06 전수 확인).
final class SortedWordTable {
    private static let anchorStride = 64
    private let data: Data
    private let floor: Int
    private let anchors: [UInt32]
    /// 서로 다른 낱말 수(이웃한 같은 줄은 하나로 센다), 헤더의 count, 정렬 여부.
    let uniqueCount: Int
    let declaredCount: Int
    let sorted: Bool
    /// 2026-11-07 (#174): 빈 줄이나 줄 끝 CR이 없는가. CR이 붙은 줄은 어떤 조회와도 맞지 않고, 빈 줄이 색인 자리에 오면 이진 탐색의 단조성이 깨진다.
    /// 재생성·편집 도구가 줄 끝을 바꾸면 자동 변환이 꺼지지 않은 채 veto만 조용히 사라지므로 온전하지 않은 파일로 본다(fail-closed).
    let wellFormed: Bool
    var isComplete: Bool { uniqueCount > 0 && declaredCount >= 0 && uniqueCount == declaredCount && sorted && wellFormed }

    convenience init?(path: String) {
        guard let mapped = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return nil }
        self.init(data: mapped)
    }

    init(data given: Data) {
        // 색인이 UInt32라 4GB를 넘는 파일은 받지 않는다. 비면 isComplete가 false라 자동 변환이 꺼진다.
        let mapped = given.count < Int(UInt32.max) ? given : Data()
        var floor = 0, declared = -1, unique = 0, isSorted = true, isWellFormed = true
        var marks: [UInt32] = []
        mapped.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            let newline = UInt8(ascii: "\n"), hash = UInt8(ascii: "#"), carriageReturn = UInt8(ascii: "\r")
            var start = 0
            // 머리 주석: `# count: N`을 읽고 표제어 시작 위치를 정한다.
            while start < bytes.count, bytes[start] == hash {
                var end = start
                while end < bytes.count, bytes[end] != newline { end += 1 }
                if let n = Self.parseCountHeader(bytes[start..<end]) { declared = n }
                start = end + 1
            }
            floor = min(start, bytes.count)
            marks.reserveCapacity(bytes.count / (13 * Self.anchorStride) + 16)
            // 한 번 훑으며 줄 수·정렬·UTF-8 유효성을 확인하고 성긴 색인을 만든다.
            var previous: Range<Int>? = nil
            var lineIndex = 0
            var cursor = floor
            while cursor < bytes.count {
                var end = cursor
                while end < bytes.count, bytes[end] != newline { end += 1 }
                let line = cursor..<end
                if line.isEmpty || bytes[end - 1] == carriageReturn { isWellFormed = false }
                if !line.isEmpty, Self.isValidUTF8(bytes, line) {
                    if let p = previous {
                        if bytes[line].lexicographicallyPrecedes(bytes[p]) { isSorted = false }
                        if !bytes[line].elementsEqual(bytes[p]) { unique += 1 }
                    } else {
                        unique += 1
                    }
                    previous = line
                }
                if lineIndex % Self.anchorStride == 0 { marks.append(UInt32(cursor)) }
                lineIndex += 1
                cursor = end + 1
            }
        }
        data = mapped
        self.floor = floor
        anchors = marks
        declaredCount = declared
        uniqueCount = unique
        sorted = isSorted
        wellFormed = isWellFormed
    }

    func contains(_ key: [UInt8]) -> Bool {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard let line = lowerBound(bytes, key) else { return false }
            return bytes[line].elementsEqual(key)
        }
    }

    /// `lower` 이상인 첫 낱말이 있고 그것이 `upper`보다 앞서는가 (= [lower, upper) 구간에 낱말이 있는가).
    func hasWord(from lower: [UInt8], below upper: [UInt8]) -> Bool {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard let line = lowerBound(bytes, lower) else { return false }
            return bytes[line].lexicographicallyPrecedes(upper)
        }
    }

    /// `key` 이상인 첫 줄의 범위. 없으면 nil. 성긴 색인에서 이진 탐색한 뒤 그 구간을 앞에서부터 훑는다.
    private func lowerBound(_ bytes: UnsafeBufferPointer<UInt8>, _ key: [UInt8]) -> Range<Int>? {
        let newline = UInt8(ascii: "\n")
        func lineEnd(_ start: Int) -> Int {
            var end = start
            while end < bytes.count, bytes[end] != newline { end += 1 }
            return end
        }
        // anchors[i]의 줄이 key보다 앞서는 마지막 i를 찾는다 → 답은 그 줄부터 다음 anchor 사이에 있다.
        var lo = 0, hi = anchors.count
        while lo < hi {
            let mid = (lo + hi) / 2
            let start = Int(anchors[mid])
            if bytes[start..<lineEnd(start)].lexicographicallyPrecedes(key) { lo = mid + 1 } else { hi = mid }
        }
        var cursor = lo == 0 ? floor : Int(anchors[lo - 1])
        let stop = lo < anchors.count ? Int(anchors[lo]) : bytes.count
        while cursor < stop {
            let end = lineEnd(cursor)
            if !bytes[cursor..<end].lexicographicallyPrecedes(key) { return cursor..<end }
            cursor = end + 1
        }
        return stop < bytes.count ? stop..<lineEnd(stop) : nil
    }

    /// `# count: N` 주석 줄에서 N을 파싱한다. 아니면 nil. (H-04)
    private static func parseCountHeader(_ bytes: Slice<UnsafeBufferPointer<UInt8>>) -> Int? {
        let line = String(decoding: bytes, as: UTF8.self)
        guard let r = line.range(of: "count:") else { return nil }
        return Int(line[r.upperBound...].trimmingCharacters(in: .whitespaces))
    }

    /// (위생-2) 깨진 UTF-8 줄은 표제어로 세지 않는다(예전 Set 로더가 그 줄을 건너뛴 것과 같다).
    private static func isValidUTF8(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Bool {
        var i = range.lowerBound
        while i < range.upperBound {
            let b = bytes[i]
            let need: Int
            if b < 0x80 { i += 1; continue }
            else if b & 0xE0 == 0xC0, b >= 0xC2 { need = 1 }
            else if b & 0xF0 == 0xE0 { need = 2 }
            else if b & 0xF8 == 0xF0, b <= 0xF4 { need = 3 }
            else { return false }
            guard i + need < range.upperBound else { return false }
            for k in 1...need where bytes[i + k] & 0xC0 != 0x80 { return false }
            // 과잉 표현(E0 80..9F, F0 80..8F)과 대리 쌍(ED A0..BF), 범위 밖(F4 90..)은 유효하지 않다.
            let second = bytes[i + 1]
            if (b == 0xE0 && second < 0xA0) || (b == 0xED && second >= 0xA0)
                || (b == 0xF0 && second < 0x90) || (b == 0xF4 && second >= 0x90) { return false }
            i += need + 1
        }
        return true
    }
}
