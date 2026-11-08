import AppKit
import CoreText
import SwiftUI

/// 2026-11-08 오너(#209): 앱 글자를 전부 마루부리(네이버, 공개 글꼴)로 맞춘다.
/// 고운바탕은 뺐다 — 큰 제목에서는 멋있지만 작은 머리글에서 둔하고, 시스템 고딕 내용과 부딪혔다("명조체로 전부 다").
/// 굵기는 Regular·SemiBold·Bold 셋만 넣는다(공식 OTF, 합쳐 약 2MB). 라이선스 `Resources/Onboarding/MaruBuri-LICENSE.txt`.
/// 이 앱 프로세스에만 등록한다. 파일을 못 읽으면 시스템 명조로 물러난다.
/// 아이콘(SF Symbols) 크기 지정과 안내 화면 속 macOS 메뉴바 흉내(시계)는 시스템 글꼴을 그대로 쓴다.
enum AppFont {
    enum Weight { case regular, semibold, bold }

    private static let postScriptNames: [Weight: String] = {
        var out: [Weight: String] = [:]
        for (weight, file) in [(Weight.regular, "MaruBuri-Regular"), (.semibold, "MaruBuri-SemiBold"), (.bold, "MaruBuri-Bold")] {
            guard let url = Bundle.main.url(forResource: file, withExtension: "otf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first,
               let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                out[weight] = name
            }
        }
        return out
    }()

    /// 시스템 굵기를 세 굵기로 접는다: 보통 이하 → Regular, medium·semibold → SemiBold, bold 이상 → Bold.
    static func weight(_ w: Font.Weight) -> Weight {
        if w == .bold || w == .heavy || w == .black { return .bold }
        if w == .medium || w == .semibold { return .semibold }
        return .regular
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let w = Self.weight(weight)
        if let name = postScriptNames[w] { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: weight, design: .serif)
    }

    static func nsFont(size: CGFloat, weight: Font.Weight = .regular) -> NSFont {
        if let name = postScriptNames[Self.weight(weight)], let font = NSFont(name: name, size: size) { return font }
        return NSFont.systemFont(ofSize: size)
    }
}

extension Button where Label == Text {
    /// 2026-11-08 (#209): 시스템 버튼(.bordered 등)은 환경 글꼴을 따르지 않는다. 글자에 마루부리를 직접 준다.
    init(maru title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { Text(title).font(AppFont.font(size: 14)) }
    }
}
