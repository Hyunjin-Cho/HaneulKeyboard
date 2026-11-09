import AppKit
import SwiftUI

/// 2026-11-08 오너(#201): 전체 제거의 확인·결과를 시스템 경고창 대신 앱 창(한지 바탕·리소 버튼)으로 보인다.
/// 문구는 오너가 정했다 — "앱·입력기·설정·개인 사전을 모두 지워요. 되돌릴 수 없어요.", 버튼은 '취소 / 모두 삭제'.
/// 예전 경고창의 "입력기를 지우지 못했거나 관리자 암호 창을 취소하면…"은 뺐다. 그런 경우는 결과 창이 알려 준다.
/// 되돌릴 수 없는 일이라 Return(기본 버튼)으로는 지우지 않는다. Esc는 취소다.
struct RemovalConfirmSheet: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 2026-11-09 오너(#216): 제목 → 설명은 6pt(앱 전체 규칙). 버튼 줄까지는 그대로 띄운다.
            VStack(alignment: .leading, spacing: AppFont.lineSpacing) {
                Text("하늘키보드를 모두 지울까요?")
                    .font(OnboardingRiso.titleFont(size: 22))
                    .foregroundStyle(OnboardingRiso.ink(for: scheme))
                // 2026-11-09 오너(#216): 삭제 쪽 글은 전부 굵게 — 설정의 전체 제거 구획과 같은 무게.
                Text("앱·입력기·설정·개인 사전을 모두 지워요. 되돌릴 수 없어요.")
                    .font(AppFont.font(size: 14, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Spacer()
                Button("취소", action: onCancel)
                    .buttonStyle(OnboardingRisoButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button("모두 삭제", action: onConfirm)
                    .buttonStyle(OnboardingRisoButtonStyle(prominent: true, tint: .red))
            }
            .padding(.top, 6)
        }
        .font(AppFont.font(size: 14))
        .lineSpacing(AppFont.lineSpacing)
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 20)
        .frame(width: 420, alignment: .leading)
        .haneulWindowAppearance()
    }
}

/// 제거 결과. 문구는 `UninstallOutcome.headline`·`message`·`details`(InstallDecisions.swift, 테스트가 검증)가 만든다.
/// 2026-11-09 오너(#216, 4차): 제목 `제거 결과` 아래에 단계 기록을 늘어놓던 것을 바꿨다 — 제목이 결과를 말하고, 단계 기록은 `자세히`를 펼쳐야 보인다.
/// 설정 창에 붙는 시트라 제목 줄이 없다(견본의 `Untitled`는 검수 하네스가 따로 띄운 창이었다).
/// 예전 경고창과 같은 동작: '확인'은 다 지워졌을 때만 앱을 끝낸다(IME 삭제가 실패해 앱을 남긴 경우는 다시 시도할 수 있게 둔다).
struct RemovalResultSheet: View {
    let outcome: Uninstaller.Outcome
    let onDone: () -> Void
    let onOpenInputSettings: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 2026-11-09 오너(#216): 제목 → 설명은 6pt(앱 전체 규칙, 확인 창과 같다).
            VStack(alignment: .leading, spacing: AppFont.lineSpacing) {
                Text(outcome.headline)
                    .font(OnboardingRiso.titleFont(size: 22))
                    .foregroundStyle(OnboardingRiso.ink(for: scheme))
                Text(outcome.message)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let details = outcome.details {
                DisclosureGroup("자세히") {
                    ScrollView {
                        Text(details)
                            .font(AppFont.font(size: 12)).lineSpacing(3)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                }
            }
            HStack(spacing: 10) {
                Spacer()
                if outcome.stillEnabledInPicker {
                    Button("시스템 설정 열기", action: onOpenInputSettings)
                        .buttonStyle(OnboardingRisoButtonStyle(prominent: false))
                }
                Button("확인", action: onDone)
                    .buttonStyle(OnboardingRisoButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .font(AppFont.font(size: 14))
        .lineSpacing(AppFont.lineSpacing)
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 20)
        .frame(width: 420, alignment: .leading)
        .haneulWindowAppearance()
    }
}
