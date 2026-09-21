import SwiftUI
import Combine

/// 2026-09-21 (#53): 설정의 "개인 사전" — 변환 추가·변환 금지·최근 되돌린 변환.
///
/// 2026-09-21 (#60): 절 3개를 세로로 쌓던 것을 **절 1개 + 세그먼트 3칸**으로 바꿨다.
/// 세로로 쌓으면 `캡션+입력+목록120` × 2 + `캡션+목록150+버튼` ≈ 700pt라 탭 안에서 또 스크롤이
/// 생겼다. 한 번에 목록 하나만 보이므로 높이를 **220**으로 키울 수 있고(한 화면에 7~8행),
/// 세 목록의 높이가 모두 같아 세그먼트를 눌러도 화면이 위아래로 흔들리지 않는다.
/// 저장 로직·헬퍼(`load`/`addForce`/`addBlock`/`blockRecent`/…)는 **그대로**이고 화면만 바뀌었다.
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
    /// 세그먼트 3칸 — 한 번에 하나만 보인다. (2026-09-21, #60)
    enum ListKind: Hashable {
        case force, block, recent
    }

    /// IME 도메인 — 이유는 `EnglishConversionSettingsTab.imeDefaults` 주석 참조.
    private static let imeDefaults = UserDefaults(suiteName: "com.hyunjincho.inputmethod.haneul")

    @State private var listKind: ListKind = .force
    @State private var force: [String] = []
    @State private var block: [String] = []
    @State private var recent: [RecentReverts.Entry] = []
    @State private var forceInput = ""
    @State private var blockInput = ""
    @State private var forceError: String?
    @State private var blockError: String?

    var body: some View {
        Group {
            Section("개인 사전") {
                Picker("개인 사전 목록", selection: $listKind) {
                    Text("변환 추가").tag(ListKind.force)
                    Text("변환 금지").tag(ListKind.block)
                    Text("최근 되돌림").tag(ListKind.recent)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("개인 사전 목록 선택")

                switch listKind {
                case .force: forceRows
                case .block: blockRows
                case .recent: recentRows
                }
            }
        }
        .onAppear(perform: load)
        // 되돌리기는 다른 앱에서 일어난다 — 설정 창으로 돌아온 순간 다시 읽어 최신을 보여준다.
        // (UserDefaults.didChangeNotification은 다른 프로세스의 변경에는 오지 않는다.)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            load()
        }
        // 2026-09-21 (#60): 탭을 옮겨 다니는 동안에도 최신 기록을 보여준다 — 창이 이미 활성인
        // 상태에서 탭만 바꾸면 didBecomeActive가 오지 않는다.
        .onChange(of: listKind) { _, _ in load() }
    }

    // MARK: - 세그먼트별 본문

    @ViewBuilder
    private var forceRows: some View {
        Text("여기 적은 영어 단어는 사전에 없거나 한국어와 겹쳐도 **항상** 영어로 바꿉니다. (예: 사내 용어·이름)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(Self.captionLines, reservesSpace: true)
        addRow(
            text: $forceInput, prompt: "영어 소문자 (예: vismo)", error: forceError,
            fieldLabel: "변환 추가할 영어 단어",
            addLabel: "변환 추가 목록에 단어 추가", action: addForce)
        wordList(force, emptyText: "추가한 단어가 없습니다.", remove: removeForce)
    }

    @ViewBuilder
    private var blockRows: some View {
        Text("여기 적은 단어는 **절대** 영어로 바꾸지 않습니다. 영어(apple)로 적어도, 한글 모드 표기(메ㅔㅣㄷ)로 적어도 됩니다. 양쪽에 다 있으면 금지가 이깁니다.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(Self.captionLines, reservesSpace: true)
        addRow(
            text: $blockInput, prompt: "영어 또는 한글 표기 (예: apple, 메ㅔㅣㄷ)", error: blockError,
            fieldLabel: "변환 금지할 단어",
            addLabel: "변환 금지 목록에 단어 추가", action: addBlock)
        wordList(block, emptyText: "금지한 단어가 없습니다.", remove: removeBlock)
    }

    @ViewBuilder
    private var recentRows: some View {
        Text("되돌리기 키로 한글로 되돌린 변환입니다. 이 기기에만 최근 \(RecentReverts.maxCount)개까지 남고 어디로도 보내지 않습니다. \"금지\"를 누르면 변환 금지 목록으로 옮깁니다.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(Self.captionLines, reservesSpace: true)

        List {
            if recent.isEmpty {
                Text("되돌린 변환이 없습니다.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recent, id: \.self) { entry in
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
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: Self.listHeight)

        HStack {
            Spacer()
            Button("최근 기록 지우기", role: .destructive, action: clearRecent)
                .controlSize(.small)
                .disabled(recent.isEmpty)
        }
    }

    // MARK: - 조각

    /// 세 목록의 높이는 **같아야 한다** — 세그먼트를 눌러도 아래 경계가 움직이지 않게. (#60)
    private static let listHeight: CGFloat = 220
    /// 2026-09-21 (#60): 캡션 줄 수도 고정한다. 목록 높이만 맞춰 놔도 캡션이 1줄·2줄로 갈리면
    /// 절 전체가 10pt씩 들썩인다(실측). 세 문구 모두 640pt 폭에서 2줄 안에 들어간다.
    private static let captionLines = 2

    private func addRow(
        text: Binding<String>, prompt: String, error: String?, fieldLabel: String,
        addLabel: String, action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // 2026-09-21 (#60): `Form` 안에서 `TextField("...", text:)`의 첫 인자는
                // **왼쪽 라벨**로 붙어 입력칸을 반으로 줄인다. 시안 와이어프레임대로 안내 문구를
                // 칸 안 placeholder로 내리고, 이름은 접근성 라벨로 남긴다.
                TextField("", text: text, prompt: Text(prompt))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(action)
                    .accessibilityLabel(fieldLabel)
                Button("추가", action: action)
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(addLabel)
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
        // 2026-09-21 (#60): 빈 상태도 테두리 안 — 비었다고 높이가 줄면 세그먼트 전환에서 덜컥거린다.
        // 빈 상태 색은 `.tertiary` → `.secondary`(다크 모드 + 교대 행 배경에서 대비가 안 남았다).
        List {
            if words.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(words, id: \.self) { word in
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
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: Self.listHeight)
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
            forceError = "영어 소문자(a–z)와 아포스트로피(')만 쓸 수 있습니다."
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
            blockError = "영어 단어 하나(apple) 또는 한글 표기 하나(메ㅔㅣㄷ)만 적어 주세요."
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
