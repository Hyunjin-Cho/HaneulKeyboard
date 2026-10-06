import SwiftUI

/// 2026-10-06 (#20, #29): 일반 설정과 메뉴바가 같은 안내를 쓴다.
/// 후원 방법/주소는 소유자가 확정한 뒤 이 화면에 연결한다.
struct SupportView: View {
    static let title = "하늘키보드 응원하기"
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(Self.title, systemImage: "heart")
                .font(.title2.bold())
            Text("하늘키보드를 응원해 주셔서 고마워요.")
            Text("후원 방법은 준비 중이에요. 준비가 끝나면 이곳에서 안내해 드릴게요.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("닫기", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
