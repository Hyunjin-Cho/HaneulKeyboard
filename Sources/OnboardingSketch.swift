import AppKit
import CoreText
import SwiftUI

/// 짧은 안내 메모만 손글씨로 표시한다. 본문과 버튼은 시스템 글꼴을 유지한다.
enum OnboardingHandwriting {
    private static let fontName: String? = {
        guard let url = Bundle.main.url(forResource: "NanumPenScript-Regular", withExtension: "ttf") else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        return descriptors?.first.flatMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
    }()

    static func font(size: CGFloat = 28) -> Font {
        if let fontName { return .custom(fontName, size: size) }
        return .system(size: size - 5, weight: .medium, design: .rounded)
    }
}

struct OnboardingSketchNote: View {
    let text: String
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text).font(OnboardingHandwriting.font()).rotationEffect(.degrees(-5))
                .fixedSize().padding(.leading, 5)
            SketchArrow().stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: 100, height: compact ? 36 : 49).padding(.leading, 42)
                .accessibilityHidden(true)
        }.frame(width: 235, height: compact ? 70 : 90, alignment: .topLeading)
    }
}

private struct SketchArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: at(0.05, 0.04))
        p.addCurve(to: at(0.93, 0.85), control1: at(-0.08, 0.5), control2: at(0.42, 0.66))
        p.move(to: at(0.70, 0.94)); p.addLine(to: at(0.93, 0.85)); p.addLine(to: at(0.80, 0.54))
        return p
    }
}

/// 일부러 닫히지 않는 두 획으로 색연필 표시처럼 아이콘을 강조한다.
struct OnboardingPencilRing: Shape {
    func path(in rect: CGRect) -> Path {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var p = Path()
        p.move(to: at(0.78, 0.08))
        p.addCurve(to: at(0.04, 0.46), control1: at(0.32, -0.06), control2: at(0.02, 0.10))
        p.addCurve(to: at(0.82, 0.93), control1: at(-0.03, 0.91), control2: at(0.49, 1.10))
        p.addCurve(to: at(0.92, 0.20), control1: at(1.05, 0.84), control2: at(1.01, 0.44))
        p.move(to: at(0.13, 0.85))
        p.addCurve(to: at(0.88, 0.04), control1: at(-0.15, 0.22), control2: at(0.44, -0.12))
        return p
    }
}

struct OnboardingMenuHint: View {
    var body: some View {
        VStack(spacing: 2) {
            Path { p in
                p.move(to: CGPoint(x: 17, y: 24))
                p.addQuadCurve(to: CGPoint(x: 15, y: 2), control: CGPoint(x: 10, y: 16))
                p.move(to: CGPoint(x: 7, y: 10))
                p.addLine(to: CGPoint(x: 15, y: 2)); p.addLine(to: CGPoint(x: 22, y: 11))
            }.stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 30, height: 24).accessibilityHidden(true)
            Text("필요할 땐 여기!").font(OnboardingHandwriting.font(size: 23))
                .rotationEffect(.degrees(-3))
        }.frame(width: 170, height: 48)
    }
}

struct OnboardingConversionDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var frame = 0
    @State private var replay = 0
    private let words = ["ㅁ", "메", "메ㅔ", "메ㅔㅣ", "메ㅔㅣㄷ", "메ㅔㅣㄷ", "apple"]
    private var showsResult: Bool { reduceMotion || frame == 6 }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                OnboardingSketchNote(text: "한/영 키는 그대로 두세요")
                    .foregroundStyle(OnboardingRiso.ink(for: scheme))
                Spacer()
            }.frame(height: 80)
            HStack(spacing: 14) {
                Text(showsResult ? "메ㅔㅣㄷ → apple" : words[frame])
                    .font(.system(size: showsResult ? 34 : 48, weight: .medium))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Space").font(.system(size: 15, weight: .medium))
                    .frame(width: 124, height: 32)
                    .background(OnboardingRiso.yellow.opacity(frame == 5 ? 0.6 : 0.2), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(OnboardingRiso.yellow.opacity(0.5)))
            }.frame(height: 68)
            HStack {
                Label("한글 모드 유지", systemImage: "checkmark.circle").font(.system(size: 14))
                Spacer()
                Button("다시 보기", systemImage: "arrow.counterclockwise") { replay += 1 }
                    .buttonStyle(OnboardingRisoButtonStyle(prominent: false))
            }.padding(.top, 10)
        }
        .frame(maxWidth: .infinity).padding(20)
        .modifier(OnboardingPrintPanel())
        .task(id: "\(replay)-\(reduceMotion)") {
            frame = 0
            guard !reduceMotion else { return }
            for next in 1...6 {
                do { try await Task.sleep(for: .milliseconds(next == 6 ? 650 : 430)) }
                catch { return }
                withAnimation(.easeOut(duration: 0.18)) { frame = next }
            }
        }
    }
}
