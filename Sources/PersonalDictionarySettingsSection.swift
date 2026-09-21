import SwiftUI
import Combine

/// 2026-09-21 (#53): 설정 창의 "개인 사전" 절 — 변환 추가·변환 금지·최근 되돌린 변환.
/// `SettingsView`의 Form 안에 Section 3개로 들어간다. 본문을 이 파일에 두는 이유:
/// `SettingsView.swift`는 다른 작업과 동시에 편집되므로 그쪽 삽입은 한 줄로 최소화한다.
///
/// 저장 규약(정본은 `IMESources/PersonalDictionary.swift` — 이 파일은 메인 앱 타겟에도
/// 컴파일돼 키 이름·정규화 규칙을 공유한다):
///   - force/block: 설정 앱이 쓰고 IME가 활성 경계마다 읽는다(`haneul.autoEnglishEnabled`
///     패턴). 저장 즉시 IME의 다음 단어부터 반영 — 재시작 불필요.
///   - recentReverts: **IME가 쓴다.** 설정 앱은 읽기와 삭제만 — "금지" 버튼의 항목 제거와
///     "최근 기록 지우기". "금지" 버튼이 두 프로세스가 같은 키를 쓰는 유일한 경우인데,
///     그 순간 IME가 새 기록을 얹으면 한쪽이 덮인다. 잃는 것은 설정값이 아니라 참고 기록
///     한 줄이라 허용한다(정합성 장치를 두면 IME 입력 경로가 무거워진다).
struct PersonalDictionarySettingsSection: View {
    /// IME 도메인 — `SettingsView.imeDefaults`와 같은 suite(주석도 거기 참조).
    private static let imeDefaults = UserDefaults(suiteName: "com.hyunjincho.inputmethod.haneul")

    @State private var force: [String] = []
    @State private var block: [String] = []
    @State private var recent: [RecentReverts.Entry] = []
    @State private var forceInput = ""
    @State private var blockInput = ""
    @State private var forceError: String?
    @State private var blockError: String?

    var body: some View {
        Group {
            Section("개인 사전 — 변환 추가") {
                Text("여기 적힌 영어 단어는 사전에 없거나 한국어 단어와 겹쳐도 **항상** 영어로 바꿉니다 (예: 사내 용어·이름). 한글 모드에서 그 단어를 그대로 쳤을 때만 적용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                addRow(
                    text: $forceInput, prompt: "영어 소문자 (예: vismo)", error: forceError,
                    action: addForce)
                wordList(force, emptyText: "추가한 단어가 없어요.", remove: removeForce)
            }

            Section("개인 사전 — 변환 금지") {
                Text("여기 적힌 단어는 **절대** 영어로 바꾸지 않습니다. 영어 단어(apple)나 한글 모드에서 보이는 표기(메ㅔㅣㄷ) 어느 쪽으로 적어도 됩니다. 양쪽에 다 있으면 금지가 이깁니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                addRow(
                    text: $blockInput, prompt: "영어 또는 한글 표기 (예: apple, 메ㅔㅣㄷ)", error: blockError,
                    action: addBlock)
                wordList(block, emptyText: "금지한 단어가 없어요.", remove: removeBlock)
            }

            Section("최근 되돌린 변환") {
                Text("Shift+Space로 영어를 다시 한글로 되돌린 변환입니다. 이 기기 안에만 최근 \(RecentReverts.maxCount)개까지 남고, 어디로도 보내지 않습니다. 잘못 바뀐 단어는 \"금지\"를 눌러 변환 금지 목록으로 옮기세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if recent.isEmpty {
                    Text("되돌린 변환이 없어요.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    List(recent, id: \.self) { entry in
                        HStack {
                            Text(entry.hangul)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                            Text(entry.english)
                            Spacer()
                            Button("금지") { blockRecent(entry) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("\(entry.english) 변환 금지")
                            Button("제안") { suggestRecent(entry) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("\(entry.english) 변환 금지 제안하기")
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    .frame(height: 150)
                    HStack {
                        Spacer()
                        Button("최근 기록 지우기", role: .destructive, action: clearRecent)
                            .controlSize(.small)
                    }
                }
            }
        }
        .onAppear(perform: load)
        // 되돌리기는 다른 앱에서 일어난다 — 설정 창으로 돌아온 순간 다시 읽어 최신을 보여준다.
        // (UserDefaults.didChangeNotification은 다른 프로세스의 변경에는 오지 않는다.)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            load()
        }
    }

    // MARK: - 조각

    private func addRow(
        text: Binding<String>, prompt: String, error: String?, action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(prompt, text: text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(action)
                Button("추가", action: action)
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func wordList(
        _ words: [String], emptyText: String, remove: @escaping (String) -> Void
    ) -> some View {
        Group {
            if words.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                List(words, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button {
                            remove(word)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(word) 삭제")
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(height: 120)
            }
        }
    }

    // MARK: - 읽기

    private func load() {
        guard let defaults = Self.imeDefaults else { return }
        let dict = PersonalDictionary.load(from: defaults)
        force = dict.force.sorted()
        block = dict.block.sorted()
        recent = RecentReverts.load(from: defaults).entries
    }

    // MARK: - 변환 추가

    private func addForce() {
        guard let word = PersonalDictionary.normalizedForceEntry(forceInput) else {
            forceError = "영어 소문자(a–z)와 '만 쓸 수 있어요. 공백·숫자·한글은 안 돼요."
            return
        }
        forceError = nil
        forceInput = ""
        guard !force.contains(word) else { return }
        force = (force + [word]).sorted()
        Self.imeDefaults?.set(force, forKey: PersonalDictionary.Keys.force)
    }

    private func removeForce(_ word: String) {
        force.removeAll { $0 == word }
        Self.imeDefaults?.set(force, forKey: PersonalDictionary.Keys.force)
    }

    // MARK: - 변환 금지

    private func addBlock() {
        guard let word = PersonalDictionary.normalizedBlockEntry(blockInput) else {
            blockError = "영어 단어 하나(apple) 또는 한글 표기 하나(메ㅔㅣㄷ)만 적어주세요."
            return
        }
        blockError = nil
        blockInput = ""
        insertBlock(word)
    }

    private func insertBlock(_ word: String) {
        guard !block.contains(word) else { return }
        block = (block + [word]).sorted()
        Self.imeDefaults?.set(block, forKey: PersonalDictionary.Keys.block)
    }

    private func removeBlock(_ word: String) {
        block.removeAll { $0 == word }
        Self.imeDefaults?.set(block, forKey: PersonalDictionary.Keys.block)
    }

    // MARK: - 최근 되돌린 변환

    /// "금지": 그 영어 단어를 변환 금지에 넣고 목록에서 뺀다 — 설정 앱이 recentReverts 키를
    /// 쓰는 유일한 자리(파일 상단 주석의 경쟁 허용 근거 참조).
    private func blockRecent(_ entry: RecentReverts.Entry) {
        if let word = PersonalDictionary.normalizedBlockEntry(entry.english) {
            insertBlock(word)
        }
        guard let defaults = Self.imeDefaults else { return }
        let updated = RecentReverts.load(from: defaults).removing(english: entry.english)
        updated.save(to: defaults)
        recent = updated.entries
    }

    /// 2026-09-21 (#55): "제안" — 이 항목의 (한글 표기, 영어)를 채운 GitHub 이슈 작성 화면을
    /// 브라우저로 연다. 되돌렸다는 것은 "이 단어는 바뀌면 안 된다"는 뜻이라 종류는 `block` 고정.
    /// 앱은 창을 열 뿐 아무것도 전송하지 않는다(PRIVACY.md 8번).
    private func suggestRecent(_ entry: RecentReverts.Entry) {
        WordSuggestionSettingsSection.openIssue(
            typed: entry.hangul, expected: entry.english, kind: .block)
    }

    private func clearRecent() {
        Self.imeDefaults?.removeObject(forKey: RecentReverts.key)
        recent = []
    }
}
