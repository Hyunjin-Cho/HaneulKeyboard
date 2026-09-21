import AppKit
import SwiftUI

/// 2026-09-21 (#55): 단어 제안 — 사용자가 적은 단어를 미리 채운 **GitHub 이슈 작성 화면**을
/// 브라우저로 연다.
///
/// 2026-09-21 (#60): 설정 창 탭 재편으로 **설정 안의 한 절 → 시트**가 됐다(입구는
/// `PersonalDictionaryTab`의 "단어 제안하기..." 버튼). 입력란 4개짜리 폼이 탭 높이를 혼자
/// 잡아먹었기 때문이다. 타입 이름은 그대로 둔다 — `PersonalDictionarySettingsSection`의
/// "제안" 버튼과 `PRIVACY.md`·`Sources/WordSuggestion.swift` 주석이 이 이름을 가리킨다.
///
/// 🔒 **서버 0 · 전송 0.** 앱이 하는 일은 `NSWorkspace.open(url)` 하나뿐이다. 네트워크로
/// 무언가를 보내는 코드는 없고, 키 입력·문맥을 모으지도 않는다 — URL에 들어가는 값은
/// 사용자가 이 화면에 직접 적은 것(또는 "최근 되돌린 변환"에서 고른 쌍)과 앱·macOS 버전뿐이다.
/// 내용 확인과 실제 등록은 사용자가 GitHub에서 직접 한다(PRIVACY.md 8번).
///
/// URL 생성 규칙(제목·본문·인코딩·길이 상한)의 정본은 `Sources/WordSuggestion.swift`이고,
/// 여기는 화면과 "열기"만 한다.
struct WordSuggestionSettingsSection: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind: WordSuggestion.Kind = .add
    @State private var typed = ""
    @State private var expected = ""
    @State private var note = ""

    private var url: URL? {
        Self.issueURL(typed: typed, expected: expected, kind: kind, note: note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("단어 제안")
                .font(.headline)
            Text("바뀌었으면 하는 단어나, 바뀌면 안 되는 단어를 알려 주시면 다음 버전의 사전에 반영합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 라벨을 왼쪽에 세우는 정렬은 `Form` 기본 스타일이 해 준다 — placeholder만 있으면
            // VoiceOver가 값이 찬 뒤 그 칸의 이름을 잃는다(#60 접근성).
            Form {
                Picker("제안 종류", selection: $kind) {
                    ForEach(WordSuggestion.Kind.allCases, id: \.self) { k in
                        Text(k.displayName).tag(k)
                    }
                }

                TextField("친 글자", text: $typed, prompt: Text("한글 모드에서 보인 표기 (예: 메ㅔㅣㄷ)"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                TextField(kind.expectedLabel, text: $expected, prompt: Text("영어 단어 (예: apple)"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                TextField("메모 (선택)", text: $note, prompt: Text("어떤 상황에서 쓰는 말인지"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
            }

            Text("브라우저에서 GitHub 이슈 작성 화면이 열립니다. 앱이 직접 보내는 것은 없고, 내용을 확인한 뒤 GitHub에서 직접 등록합니다. (GitHub 계정 필요)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("GitHub에서 열기") { open() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url == nil)
            }
        }
        .padding()
        .frame(width: 480, height: 420)
    }

    /// 열고 나면 입력란을 비우고 시트를 닫는다 — 같은 제안을 두 번 여는 사고를 줄이려고.
    private func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
        typed = ""
        expected = ""
        note = ""
        dismiss()
    }

    // MARK: - 다른 절에서도 쓰는 입구

    /// 이 기기의 값(앱·macOS 버전)을 채운 이슈 URL. 화면의 버튼 비활성화도 이 값이 nil인지로
    /// 판정하므로, "만들 수 있는가"와 "여는 것"이 항상 같은 판정을 쓴다.
    static func issueURL(
        typed: String, expected: String, kind: WordSuggestion.Kind, note: String = ""
    ) -> URL? {
        WordSuggestion.issueURL(
            typed: typed, expected: expected, kind: kind, note: note,
            appVersion: appVersion, osVersion: osVersion)
    }

    /// 미리 채운 이슈 작성 화면을 기본 브라우저로 연다. **앱이 하는 유일한 바깥 동작**이고,
    /// 여는 것뿐이라 아무것도 전송되지 않는다. (`PersonalDictionarySettingsSection`의
    /// "최근 되돌린 변환 → 제안" 버튼도 이 함수를 쓴다.)
    @discardableResult
    static func openIssue(
        typed: String, expected: String, kind: WordSuggestion.Kind, note: String = ""
    ) -> Bool {
        guard let url = issueURL(typed: typed, expected: expected, kind: kind, note: note) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    /// 메뉴바에 보이는 것과 같은 버전 + 빌드 번호(어느 빌드에서 난 일인지 구분용).
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        if marketing.isEmpty { return "" }
        return build.isEmpty ? marketing : "\(marketing) (빌드 \(build))"
    }

    /// 예: `27.0 (26A428)`. `operatingSystemVersionString`은 표시 전용이라는 문서 그대로
    /// 표시에만 쓴다(파싱하지 않는다).
    static var osVersion: String {
        let raw = ProcessInfo.processInfo.operatingSystemVersionString
        let prefix = "Version "
        return raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
    }
}
