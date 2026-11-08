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
            Text("하늘키보드를 모두 지울까요?")
                .font(OnboardingRiso.titleFont(size: 22))
                .foregroundStyle(OnboardingRiso.ink(for: scheme))
            Text("앱·입력기·설정·개인 사전을 모두 지워요. 되돌릴 수 없어요.")
                .fixedSize(horizontal: false, vertical: true)
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
        .font(.system(size: 14))
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 20)
        .frame(width: 420, alignment: .leading)
        .haneulWindowAppearance()
    }
}

/// 제거 결과. 문구는 `UninstallOutcome.statusText`(InstallDecisions.swift, 테스트가 검증)가 만든다.
/// 예전 경고창과 같은 동작: '확인'은 다 지워졌을 때만 앱을 끝낸다(IME 삭제가 실패해 앱을 남긴 경우는 다시 시도할 수 있게 둔다).
struct RemovalResultSheet: View {
    let outcome: Uninstaller.Outcome
    let onDone: () -> Void
    let onOpenInputSettings: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("제거 결과")
                .font(OnboardingRiso.titleFont(size: 22))
                .foregroundStyle(OnboardingRiso.ink(for: scheme))
            Text(outcome.statusText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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
        .font(.system(size: 14))
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 20)
        .frame(width: 420, alignment: .leading)
        .haneulWindowAppearance()
    }
}
