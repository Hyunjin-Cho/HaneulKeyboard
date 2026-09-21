import SwiftUI

/// 설정 → 「고급」 탭. (2026-09-21, #60)
///
/// 절이 「전체 제거」 하나뿐이고 아래는 전부 여백이다 — 의도한 것이다. 파괴적 동작이 텅 빈 방에
/// 혼자 있는 그림 자체가 경고이고, 다른 설정을 만지다가 실수로 누를 거리도 멀어진다.
/// 확인 다이얼로그와 결과 다이얼로그는 컨테이너(`SettingsView`)가 갖고, 여기서는 켜기만 한다.
struct AdvancedSettingsTab: View {
    @Binding var showingUninstallConfirm: Bool

    var body: some View {
        Form {
            Section("전체 제거") {
                Text("하늘키보드의 앱·입력기·설정을 모두 지웁니다. 다시 쓰려면 내려받아 설치해야 합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("전체 제거...", role: .destructive) {
                        showingUninstallConfirm = true
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
