import AppKit
import SwiftUI

/// 2026-10-11 (#55, #88): 단어 제안 — 설명은 최소 14pt로 표시한다.
///
/// 2026-09-21 (#60): 설정 창 탭 재편으로 **설정 안의 한 절 → 시트**가 됐다(입구는
/// `PersonalDictionaryTab`의 "단어 제안하기..." 버튼). 입력란 4개짜리 폼이 탭 높이를 혼자
/// 잡아먹었기 때문이다. 타입 이름은 그대로 둔다 — `PersonalDictionarySettingsSection`의
/// "제안" 버튼과 `PRIVACY.md`·`Sources/WordSuggestion.swift` 주석이 이 이름을 가리킨다.
///
/// 앱이 하는 일은 `NSWorkspace.open(url)`이다. 자동 제출이나 키 입력·문맥 수집은 없다. URL의 값은
/// 사용자가 이 화면에 직접 적은 것(또는 "최근 되돌린 변환"에서 고른 쌍)과 앱·macOS 버전뿐이다.
/// 내용 확인과 실제 발송/등록은 사용자가 선택한 앱에서 직접 한다(PRIVACY.md 8번).
///
/// URL 생성 규칙(제목·본문·인코딩·길이 상한)의 정본은 `Sources/WordSuggestion.swift`이고,
/// 여기는 화면과 "열기"만 한다.
struct WordSuggestionSettingsSection: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind: WordSuggestion.Kind = .add
    @State private var typed = ""
    @State private var expected = ""
    @State private var note = ""
    @State private var openError: String?

    init(typed: String = "", expected: String = "", kind: WordSuggestion.Kind = .add) {
        _typed = State(initialValue: typed)
        _expected = State(initialValue: expected)
        _kind = State(initialValue: kind)
    }

    private var url: URL? {
        Self.issueURL(typed: typed, expected: expected, kind: kind, note: note)
    }
    private var emailURL: URL? {
        WordSuggestion.emailURL(typed: typed, expected: expected, kind: kind, note: note,
            appVersion: Self.appVersion, osVersion: Self.osVersion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("단어 제안")
                .font(SettingsTypography.control)
            Text("모두의 사전에 필요한 단어나 산업군·분야를 알려 주세요. 다음 버전에 반영할 수 있도록 검토하겠습니다. 이 기기에서만 바꾸려면 개인 사전을 사용해 주세요.")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 라벨을 왼쪽에 세우는 정렬은 `Form` 기본 스타일이 해 준다 — placeholder만 있으면
            // VoiceOver가 값이 찬 뒤 그 칸의 이름을 잃는다(#60 접근성).
            Form {
                Picker("제안 종류", selection: $kind) {
                    ForEach(WordSuggestion.Kind.allCases, id: \.self) { k in
                        Text(k.displayName).tag(k)
                    }
                }

                TextField(kind.typedLabel, text: $typed,
                          prompt: Text(kind == .field ? "예: 건축, 영상 후반 작업" : "한글 모드에서 보인 표기 (예: 메ㅔㅣㄷ)"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                TextField(kind.expectedLabel, text: $expected,
                          prompt: Text(kind == .field ? "예시 용어를 아는 만큼 적어 주세요" : "영어 단어 (예: apple)"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                TextField("메모 (선택)", text: $note, prompt: Text("어떤 상황에서 쓰는 말인지"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
            }
            .font(SettingsTypography.body)

            Text("이메일은 메일 앱의 작성창을, GitHub는 브라우저의 등록 화면을 열어요. 내용을 확인한 뒤 직접 보내 주세요. GitHub는 계정이 필요해요.")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("이메일 받는 곳: \(WordSuggestion.contactEmail)")
                .font(SettingsTypography.body).foregroundStyle(.secondary).textSelection(.enabled)
            if let openError {
                Text(openError).font(SettingsTypography.body).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("이메일로 제안") { open(emailURL, email: true) }
                    .buttonStyle(.borderedProminent).tint(.blue).foregroundStyle(.white)
                    .disabled(emailURL == nil)
                Button("GitHub에서 등록") { open(url, email: false) }
                    .buttonStyle(.borderedProminent).tint(.blue).foregroundStyle(.white)
                    .keyboardShortcut(.defaultAction)
                    .disabled(url == nil)
            }
        }
        .font(SettingsTypography.control)
        .controlSize(.large)
        .padding()
        .frame(width: 600, height: 540)
        .background { OnboardingRisoPaper() }
    }

    /// 열고 나면 입력란을 비우고 시트를 닫는다 — 같은 제안을 두 번 여는 사고를 줄이려고.
    private func open(_ url: URL?, email: Bool) {
        guard let url else { return }
        guard NSWorkspace.shared.open(url) else {
            openError = email ? "메일 작성창을 열지 못했어요. Mac의 기본 메일 앱 설정을 확인해 주세요." : "등록 화면을 열지 못했어요. 기본 브라우저 설정을 확인해 주세요."
            return
        }
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

    /// 메뉴바에 보이는 것과 같은 버전 + 빌드 번호(어느 빌드에서 난 일인지 구분용).
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let marketing = UpdateDecision.releaseVersion(info: info) ?? ""
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
