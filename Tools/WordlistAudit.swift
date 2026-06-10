import Foundation
import CoreFoundation

// ═════════════════════════════════════════════════════════════════════════
// WordlistAudit — 영어 사전 후보 검역(스윕) 도구
//
// 실제 IME 코드(KoreanComposer / EnglishDetector / KoreanDictionary)를 그대로
// 컴파일해 쓴다 (파이썬 재구현 금지 원칙). "이 후보 단어를 사전에 넣으면
// 실제로 뭐가 새로 변환되나"는 전부 실코드 shouldConvert()가 답하고,
// 이 파일은 ①두벌식 타이핑 시뮬레이션(실제 KoreanComposer) ②시나리오 호출
// ③결과 비교/CSV만 담당한다. 구조 분류·미도달 진단 "라벨"만 설명용 미러
// (EnglishDetector private 술어와 동일 로직 — 판정에는 미사용, 아래 표시).
//
// EnglishDetector의 사전 Set은 프로세스당 1회 lazy 로드(static let)라서
// "후보 제외 vs 포함" 비교는 프로세스를 나눠 실행한다 — 게이트/로딩 코드
// 무변경 원칙. 오케스트레이션은 scripts/audit_wordlist.sh:
//   1) scan(베이스 사전)   → passA.tsv : 후보가 없을 때의 변환 여부
//   2) scan(베이스+후보)   → passB.tsv : 후보를 넣었을 때의 변환 여부
//   3) merge passA passB  → audit.csv : diff + Tier(A/B/C) + 휴리스틱 note
//
// 서브커맨드 (직접 호출 시):
//   WordlistAudit scan  --candidates F --wordlists p1,p2 --curated p1 \
//                       --korean-dict K
//   WordlistAudit merge passA.tsv passB.tsv --korean-dict K
//   WordlistAudit reach --words F --wordlists p1,p2 --curated p1 \
//                       --korean-dict K
//
// 시나리오 3종 (shouldConvert 인자):
//   standalone — 무맥락               (previousEnglishWord: nil)
//   context    — 일반 영어 문맥        (previousEnglishWord: "the", 비트리거)
//   trigger    — 화이트리스트 트리거 문맥 (previousEnglishWord: "want")
//
// Tier (merge 출력):
//   A — clean + 우리말샘 미등재 + 무맥락 변환이 "신규"(R5 노출, 6키+)
//       → 전수 리뷰 대상 (한국어처럼 생긴 단어가 문맥 없이 영어로 바뀜)
//   B — clean + 미등재 + 문맥 변환만 신규 → note의 휴리스틱(조사결합/활용형
//       의심)을 우선 리뷰
//   C — 깨진 형·veto 등재·변화 없음 = 안전. 단 class=all_jamo(완성음절 0)가
//       신규 변환되면 note에 ⚠️ — names 파일에서 기본 제외 대상(ㅗㅜㅑ류
//       자모 슬랭 보호).
// ═════════════════════════════════════════════════════════════════════════

// MARK: - 실코드 연결

/// 출력 무시 클라이언트 — 타이핑 시뮬레이션용.
final class NullClient: ComposerClient {
    func insertText(_ text: String) {}
    func setMarkedText(_ text: String) {}
}

/// 단어 하나를 실제 KoreanComposer로 두벌식 타이핑해 한글형을 얻는다.
/// commit(convertEnglish: false)는 화면에 보이던 한글 그대로를 반환한다.
func hangulForm(of word: String) -> String? {
    guard word.count <= 24 else { return nil } // maxWordUnits(40) spill 방지
    for ch in word where KeyboardLayout2Set.jamo(for: ch) == nil { return nil }
    let client = NullClient()
    let composer = KoreanComposer()
    composer.autoEnglishEnabled = false
    for ch in word { _ = composer.handleInput(String(ch), client: client) }
    let hangul = composer.commit(to: client) // passive commit = 표시된 한글
    return hangul.isEmpty ? nil : hangul
}

struct Eval {
    let word: String
    let hangul: String
    let cls: String // clean | broken | all_jamo | unmappable
    let inUrimalsaem: Bool
    let standalone: Bool
    let context: Bool
    let trigger: Bool
}

/// 후보 단어 1개 평가 — 변환 판정은 전부 실코드 shouldConvert().
/// 모든 word unit은 정확히 1글자(SyllableBuffer.assembled 불변식)라
/// units = 한글형의 글자 분해와 동일하다.
func evaluate(_ raw: String) -> Eval {
    let word = raw.lowercased()
    guard let hangul = hangulForm(of: word) else {
        return Eval(word: word, hangul: "", cls: "unmappable",
                    inUrimalsaem: false, standalone: false, context: false, trigger: false)
    }
    let units = hangul.map(String.init)
    let keys = Array(word)
    return Eval(
        word: word,
        hangul: hangul,
        cls: classify(hangul),
        inUrimalsaem: KoreanDictionary.contains(hangul),
        standalone: EnglishDetector.shouldConvert(units: units, keys: keys),
        context: EnglishDetector.shouldConvert(units: units, keys: keys,
                                               previousEnglishWord: "the"),
        trigger: EnglishDetector.shouldConvert(units: units, keys: keys,
                                               previousEnglishWord: "want")
    )
}

func configureDetector(wordlists: [String], curated: [String], koreanDict: String) {
    // 첫 lookup 전에 설정해야 함 (lazy 1회 로드) — 테스트 하네스와 동일 패턴.
    EnglishDetector.wordlistPaths = wordlists
    EnglishDetector.curatedPaths = Set(curated)
    KoreanDictionary.wordlistPath = koreanDict
    // 문맥 프로브 단어가 트리거 목록과 어긋나면 시나리오 의미가 깨진다.
    precondition(!EnglishDetector.whitelistTriggers.contains("the"),
                 "문맥 프로브 'the'가 whitelistTriggers에 들어감 — 프로브 교체 필요")
    precondition(EnglishDetector.whitelistTriggers.contains("want"),
                 "트리거 프로브 'want'가 whitelistTriggers에서 빠짐 — 프로브 교체 필요")
}

// MARK: - 구조 분류 (설명용 미러 — EnglishDetector private 술어와 동일 로직)

private let eucKR = String.Encoding(
    rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
    )
)

func isCompatJamo(_ ch: Character) -> Bool {
    ch.unicodeScalars.first.map { (0x3131...0x3163).contains($0.value) } ?? false
}

func isCompleteSyllable(_ ch: Character) -> Bool {
    ch.unicodeScalars.first.map { (0xAC00...0xD7A3).contains($0.value) } ?? false
}

/// clean: 완성 음절만 + 전부 KS X 1001 (detector의 brokenAsKorean=false 미러)
/// broken: 자모 노출 / 모음 시작(자모의 부분집합) / 비완성형 음절 포함
/// all_jamo: 완성 음절 0개 — names 파일 기본 제외 대상 (자모 슬랭 보호)
func classify(_ hangul: String) -> String {
    let chars = Array(hangul)
    if !chars.contains(where: isCompleteSyllable) { return "all_jamo" }
    if chars.contains(where: isCompatJamo) { return "broken" }
    // KS X 1001 밖 음절 (EUC-KR 인코딩 가능 = 멤버십, 햏은 의도 슬랭 예외)
    if chars.contains(where: { isCompleteSyllable($0) && $0 != "햏"
        && String($0).data(using: eucKR) == nil }) {
        return "broken"
    }
    return "clean"
}

// MARK: - 한글 휴리스틱 (Tier B 정렬용)

/// 끝 음절의 받침을 제거한 형태 (했→해) — 활용형 의심 휴리스틱용.
func finalStrippedForm(_ hangul: String) -> String? {
    let scalars = Array(hangul.unicodeScalars)
    guard let last = scalars.last, (0xAC00...0xD7A3).contains(last.value) else { return nil }
    let idx = Int(last.value) - 0xAC00
    guard idx % 28 != 0, let base = UnicodeScalar(0xAC00 + (idx / 28) * 28) else { return nil }
    return String(String.UnicodeScalarView(scalars.dropLast())) + String(Character(base))
}

/// 마지막 음절을 제거한 형태 (학교에→학교) — 조사결합 의심 휴리스틱용.
func lastSyllableRemovedForm(_ hangul: String) -> String? {
    guard hangul.count >= 2 else { return nil }
    let stem = String(hangul.dropLast())
    guard stem.allSatisfy(isCompleteSyllable) else { return nil }
    return stem
}

// MARK: - 입출력 헬퍼

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("오류: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func note(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

func readWords(_ path: String) -> [String] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("파일을 읽을 수 없음: \(path)")
    }
    var seen = Set<String>()
    var out: [String] = []
    for line in content.split(separator: "\n") {
        let w = line.trimmingCharacters(in: .whitespaces).lowercased()
        guard !w.isEmpty, !w.hasPrefix("#"), seen.insert(w).inserted else { continue }
        out.append(w)
    }
    return out
}

/// EnglishDetector.loadWords와 동일 필터의 설명용 미러 — reach 진단 라벨
/// 전용 (변환 판정에는 절대 미사용). exact 멤버십만 (활용형 fallback 없음).
func mirrorLoadWords(_ paths: [String]) -> Set<String> {
    var set = Set<String>()
    for path in paths {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
        for line in content.split(separator: "\n") {
            guard line.count >= 3,
                  let first = line.unicodeScalars.first, (0x61...0x7A).contains(first.value),
                  line.allSatisfy({ $0.isASCII && $0.isLetter }) else { continue }
            set.insert(line.lowercased())
        }
    }
    return set
}

func csvQuote(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

struct Options {
    var positional: [String] = []
    var values: [String: String] = [:]
}

func parseArgs(_ args: [String]) -> Options {
    var opts = Options()
    var i = 0
    while i < args.count {
        let a = args[i]
        if a.hasPrefix("--") {
            guard i + 1 < args.count else { fail("\(a) 값 누락") }
            opts.values[String(a.dropFirst(2))] = args[i + 1]
            i += 2
        } else {
            opts.positional.append(a)
            i += 1
        }
    }
    return opts
}

func requirePaths(_ opts: Options, _ key: String) -> [String] {
    guard let raw = opts.values[key] else { fail("--\(key) 필요") }
    return raw.split(separator: ",").map(String.init)
}

// MARK: - scan

func runScan(_ args: [String]) {
    let opts = parseArgs(args)
    guard let candidates = opts.values["candidates"] else { fail("--candidates 필요") }
    let wordlists = requirePaths(opts, "wordlists")
    let curated = opts.values["curated"].map { $0.split(separator: ",").map(String.init) } ?? []
    guard let koreanDict = opts.values["korean-dict"] else { fail("--korean-dict 필요") }
    configureDetector(wordlists: wordlists, curated: curated, koreanDict: koreanDict)

    // TSV: word, hangul, class, in_urimalsaem, standalone, context, trigger
    for word in readWords(candidates) {
        let e = evaluate(word)
        let row = [e.word, e.hangul, e.cls,
                   e.inUrimalsaem ? "1" : "0",
                   e.standalone ? "1" : "0",
                   e.context ? "1" : "0",
                   e.trigger ? "1" : "0"]
        print(row.joined(separator: "\t"))
    }
}

// MARK: - merge

struct ScanRow {
    let word: String, hangul: String, cls: String
    let veto: Bool, standalone: Bool, context: Bool, trigger: Bool
}

func readScan(_ path: String) -> [String: ScanRow] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("스캔 결과를 읽을 수 없음: \(path)")
    }
    var rows: [String: ScanRow] = [:]
    for line in content.split(separator: "\n") {
        let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 7 else { continue }
        rows[f[0]] = ScanRow(word: f[0], hangul: f[1], cls: f[2],
                             veto: f[3] == "1", standalone: f[4] == "1",
                             context: f[5] == "1", trigger: f[6] == "1")
    }
    return rows
}

func runMerge(_ args: [String]) {
    let opts = parseArgs(args)
    guard opts.positional.count == 2 else { fail("merge passA.tsv passB.tsv 필요") }
    guard let koreanDict = opts.values["korean-dict"] else { fail("--korean-dict 필요") }
    KoreanDictionary.wordlistPath = koreanDict // 휴리스틱(조사/활용 의심)용

    guard let orderSource = try? String(contentsOfFile: opts.positional[0], encoding: .utf8) else {
        fail("스캔 결과를 읽을 수 없음: \(opts.positional[0])")
    }
    let order = orderSource.split(separator: "\n")
        .compactMap { $0.split(separator: "\t").first.map(String.init) }
    let passA = readScan(opts.positional[0])
    let passB = readScan(opts.positional[1])

    struct Out {
        let row: String
        let tier: String
        let suspicious: Bool
    }
    var outs: [Out] = []
    var tierCount: [String: Int] = [:]
    var allJamoNew = 0

    for word in order {
        guard let a = passA[word] else { continue }
        guard let b = passB[word] else {
            outs.append(Out(row: csvRow(a, a, tier: "C", note: "passB 누락 — 재실행 필요"),
                            tier: "C", suspicious: false))
            continue
        }
        let newStandalone = !a.standalone && b.standalone
        let newContext = (!a.context && b.context) || (!a.trigger && b.trigger)

        var tier = "C"
        if a.cls == "clean", !a.veto, newStandalone {
            tier = "A"
        } else if a.cls == "clean", !a.veto, newContext {
            tier = "B"
        }

        var notes: [String] = []
        var suspicious = false
        if a.cls == "unmappable" {
            notes.append("두벌식 시뮬 불가(비알파벳/과장) — 수동 확인")
        }
        if a.veto {
            notes.append("우리말샘 등재(veto) — 구조 룰 변환 불가")
        }
        if a.cls == "all_jamo" {
            notes.append("⚠️ 전부 자모(완성음절 0) — names 기본 제외 권장(ㅗㅜㅑ류 슬랭 보호)")
            if newStandalone || newContext { allJamoNew += 1 }
        }
        if tier == "A" {
            notes.append("무맥락 신규 변환(R5) — 전수 리뷰 대상")
        }
        if tier == "A" || tier == "B" {
            if let stem = lastSyllableRemovedForm(a.hangul), KoreanDictionary.contains(stem) {
                notes.append("조사결합 의심('\(stem)' 등재)")
                suspicious = true
            }
            if let stripped = finalStrippedForm(a.hangul), KoreanDictionary.contains(stripped) {
                notes.append("활용형 의심('\(stripped)' 등재)")
                suspicious = true
            }
        }
        if !newStandalone, !newContext, !a.veto, a.cls != "unmappable" {
            notes.append(a.standalone || a.context || a.trigger
                         ? "변화 없음(베이스에서 이미 변환)" : "변화 없음(여전히 미도달)")
        }

        outs.append(Out(row: csvRow(a, b, tier: tier, note: notes.joined(separator: "; ")),
                        tier: tier, suspicious: suspicious))
        tierCount[tier, default: 0] += 1
    }

    // 리뷰 순서: A 전체 → B(의심 먼저) → C. 그룹 내 입력 순서 유지(stable).
    let rank: [String: Int] = ["A": 0, "B": 1, "C": 2]
    let sorted = outs.enumerated().sorted {
        let l = ($0.element, $0.offset), r = ($1.element, $1.offset)
        let lk = (rank[l.0.tier] ?? 9, l.0.suspicious ? 0 : 1, l.1)
        let rk = (rank[r.0.tier] ?? 9, r.0.suspicious ? 0 : 1, r.1)
        return lk < rk
    }.map(\.element)

    print("word,hangul_form,class,in_urimalsaem,standalone_before,standalone_after,"
        + "context_before,context_after,trigger_before,trigger_after,tier,note")
    for out in sorted { print(out.row) }

    note("─ 검역 요약: Tier A \(tierCount["A", default: 0]) / "
        + "B \(tierCount["B", default: 0]) / C \(tierCount["C", default: 0])"
        + (allJamoNew > 0 ? " / ⚠️ 전부-자모 신규 변환 \(allJamoNew)건 (제외 권장)" : ""))
}

func csvRow(_ a: ScanRow, _ b: ScanRow, tier: String, note: String) -> String {
    [a.word, a.hangul, a.cls, a.veto ? "1" : "0",
     a.standalone ? "1" : "0", b.standalone ? "1" : "0",
     a.context ? "1" : "0", b.context ? "1" : "0",
     a.trigger ? "1" : "0", b.trigger ? "1" : "0",
     tier, csvQuote(note)].joined(separator: ",")
}

// MARK: - reach (도달성 — and-class 구멍 자동 탐지)

func runReach(_ args: [String]) {
    let opts = parseArgs(args)
    guard let wordsFile = opts.values["words"] else { fail("--words 필요") }
    let wordlists = requirePaths(opts, "wordlists")
    let curatedList = opts.values["curated"].map { $0.split(separator: ",").map(String.init) } ?? []
    guard let koreanDict = opts.values["korean-dict"] else { fail("--korean-dict 필요") }
    configureDetector(wordlists: wordlists, curated: curatedList, koreanDict: koreanDict)

    // 진단 라벨 전용 미러 세트 (판정은 위 evaluate의 실코드가 담당)
    let broadMirror = mirrorLoadWords(wordlists)
    let curatedMirror = mirrorLoadWords(curatedList)

    print("word,hangul_form,class,in_urimalsaem,standalone,context,trigger,reached,diagnosis")
    var gaps = 0
    for word in readWords(wordsFile) {
        let e = evaluate(word)
        let reached = e.standalone || e.context || e.trigger
        if !reached { gaps += 1 }
        let row = [e.word, e.hangul, e.cls, e.inUrimalsaem ? "1" : "0",
                   e.standalone ? "1" : "0", e.context ? "1" : "0",
                   e.trigger ? "1" : "0", reached ? "1" : "0",
                   csvQuote(diagnose(e, broad: broadMirror, curated: curatedMirror))]
        print(row.joined(separator: ","))
    }
    note("─ 도달성 요약: 미도달 \(gaps)건 (diagnosis의 ★가 and-class 후보)")
}

func diagnose(_ e: Eval, broad: Set<String>, curated: Set<String>) -> String {
    if e.cls == "unmappable" { return "시뮬 불가(비알파벳/과장)" }
    if e.standalone { return "도달:무맥락(\(standaloneRuleGuess(e)))" }
    if e.context { return "도달:영어문맥(R2/override/화이트리스트)" }
    if e.trigger { return "도달:트리거전용(새→to류 화이트리스트)" }
    // 미도달 — 이유 추정 (라벨은 미러 기반, 참고용)
    if e.inUrimalsaem { return "미도달:veto('\(e.hangul)' 우리말샘 등재)" }
    if EnglishDetector.protectedSlang.contains(e.hangul) { return "미도달:보호 슬랭" }
    let keys = Array(e.word)
    if keys.count >= 2, Set(keys).count == 1 { return "미도달:동일키 가드" }
    if !broad.contains(e.word) { return "미도달:영어 사전 미등재(exact 기준)" }
    if e.cls == "clean" {
        if e.hangul.count == 1 {
            return "★미도달:and-class(clean 1음절 — shortWords 채널만 가능, 불변식 주석 확인)"
        }
        if !curated.contains(e.word) {
            return keys.count >= 6
                ? "미도달:clean 6키+ — curated 등재 시 R5 가능"
                : "미도달:clean 짧음 — curated 등재 시 문맥 변환(R2-clean) 가능"
        }
    }
    return "미도달:기타(수동 확인)"
}

func standaloneRuleGuess(_ e: Eval) -> String {
    if e.cls == "clean" { return "R5 curated 6키+" }
    let consonantOnly = e.hangul.unicodeScalars.allSatisfy { (0x3131...0x314E).contains($0.value) }
    if consonantOnly, e.hangul.count >= 4 { return "자음열4+" }
    if let first = e.hangul.unicodeScalars.first, (0x314F...0x3163).contains(first.value) {
        return "R1/MAIN"
    }
    return "MAIN/R3"
}

// MARK: - main

@main
struct WordlistAudit {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { usage() }
        let cmd = args.removeFirst()
        switch cmd {
        case "scan": runScan(args)
        case "merge": runMerge(args)
        case "reach": runReach(args)
        default: usage()
        }
    }

    static func usage() -> Never {
        note("""
        WordlistAudit — 영어 사전 후보 검역 (scripts/audit_wordlist.sh 경유 권장)
          scan  --candidates F --wordlists p1,p2 --curated p1 --korean-dict K
          merge passA.tsv passB.tsv --korean-dict K
          reach --words F --wordlists p1,p2 --curated p1 --korean-dict K
        """)
        exit(2)
    }
}
