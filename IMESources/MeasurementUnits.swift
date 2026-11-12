import Foundation

/// 2026-10-07 (#82): 키보드로 입력하는 단위 표기. 단위 환산/철자 교정은 하지 않는다.
/// 대소문자는 의미가 다를 수 있어 정확히 조회하고, 출력에는 원래 키열을 쓴다.
/// 공식 기호와 실용 ASCII 별칭을 구분한 근거/제외 기준: docs/measurement-units.md.
/// 2026-10-08: 메가픽셀의 실용 표기 mp/MP/Mp 추가. 입력 대소문자를 보존한다.
enum MeasurementUnits {
    static let symbols: Set<String> = Set("""
        m mm cm dm km um nm pm angstrom in ft yd mi nmi mil
        g kg mg ug ng oz lb lbs t ton
        L l ml mL cl cL dl dL hl hL kl kL ul uL cc pt qt gal floz
        s ms us ns ps min h hr d wk
        Hz kHz MHz GHz THz hz khz mhz ghz thz fps rpm
        K mol mmol umol nmol cd rad sr
        N mN kN MN Pa hPa kPa MPa GPa bar mbar psi atm Torr torr
        J mJ kJ MJ GJ cal kcal eV keV MeV GeV
        W mW kW MW GW Wh mWh kWh MWh
        A mA uA nA Ah mAh C V mV kV F uF nF pF ohm kohm Mohm S mS H mH
        Wb T mT lm lx Bq kBq MBq Gy mGy Sv mSv uSv kat ha acre
        bit B KB MB GB TB PB KiB MiB GiB TiB PiB kb mb gb tb pb
        bps kbps Mbps Gbps mbps gbps dpi ppi px mp MP Mp em rem dB dBA ppm ppb ppt
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static func contains(_ raw: String) -> Bool { symbols.contains(raw) }

    /// 2026-11-08 오너 결정(#194): 숫자가 붙을 때만 바꾸는 단위. 단독 `nm`(ㅜㅡ)은 그대로 두고 `10nm`·`10 nm`·`1.5nm`은 바꾼다.
    /// 숫자 뒤 판정은 `allowsAfterQuantity`가 맡으므로 이 목록을 보지 않는다.
    /// 2026-11-10 오너 결정(#222): 소문자 바이트 단위(kb·mb·gb·tb·pb)도 이 단위 경로에서는 숫자가 붙을 때만 바꾼다. 단독 `ㅡㅠ`(우는 표정)·`휴`·`슈`는 그대로다.
    /// 2026-11-13 정정(#225, 리뷰 english-dict-F-3, 오너 결정 가 "kb·pb 단독 변환 유지"): 이 목록은 단위 경로만 막는다.
    /// kb(ㅏㅠ)·pb(ㅔㅠ)는 2026-11-08(#194) 짧은 단어 목록(`EnglishDetector.shortWords`, 모음으로 시작하는 R1 경로)에 있어 단독으로도 바뀐다.
    /// 그래서 실제로 단독이 한글로 남는 것은 nm·mb·gb·tb다(gb·tb는 표제어 휴·슈 veto, nm·mb는 이 목록). 시험이 이 겹침을 kb·pb로 고정한다.
    /// 지금 어느 단위가 단독·숫자 뒤에서 바뀌는지는 `bash scripts/audit_units.sh`로 확인한다(목록·개수를 문서에 박지 않는다).
    static let quantityOnlySymbols: Set<String> = ["nm", "kb", "mb", "gb", "tb", "pb"]

    /// 2026-11-10 오너 결정(#222, "숫자를 앞에 쓰고 뒤에 '슈'를 쓰는 일은 거의 없긴하거든"): 소문자 gb·tb의 한글(휴·슈)은 표제어지만
    /// 숫자에 **붙여 쓴** 경우에는 바이트 단위로 본다(이 Mac 문서·오너 메시지에서 숫자+휴·슈 우리말 0건). 띄어 쓴 `20 휴`는 그대로다.
    /// 붙여 쓴 `3휴가`도 `3gb가`가 된다(Shift+Space로 되돌린다). 휴가·휴일만 막아 보면 더 흔한 `16gb가`·`16gb일`이 깨져서 막지 않았다(2026-11-10 시험).
    static let attachedOverKoreanWord: Set<String> = ["gb", "tb"]

    /// 정수 또는 소수. 부호는 기존 구두점 경로에 남긴다. `1.`은 수량으로 확정하지 않는다.
    static func isQuantity(_ raw: String) -> Bool {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        return (1...2).contains(parts.count) && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy(AlphanumericWords.isDigit)
        }
    }

    static func splitQuantity(_ raw: String) -> (amount: String, unit: String)? {
        let amount = String(raw.prefix { AlphanumericWords.isDigit($0) || $0 == "." })
        let unit = String(raw.dropFirst(amount.count))
        guard isQuantity(amount), contains(unit) else { return nil }
        return (amount, unit)
    }

    /// 숫자가 있어도 `10이(dl)`·`3치(cl)`처럼 실제 한글은 보호한다.
    /// GB/dB/dL의 Shift처럼 한글 자모를 바꾸지 않는 명시적 대문자가 있으면
    /// 숫자 + 정확한 단위 기호를 영어 의도로 인정한다. QWERTOP Shift는 한글 의도다.
    /// `attached`: 숫자에 바로 붙여 친 단위인가(`20gb`). 띄어 쓴 단위(`20 gb`)는 false.
    static func allowsAfterQuantity(_ unit: String, hangul: String, attached: Bool = false) -> Bool {
        guard contains(unit), KoreanDictionary.isLoaded else { return false }
        return !KoreanDictionary.contains(hangul)
            || (attached && attachedOverKoreanWord.contains(unit))
            || unit.contains { $0.isUppercase && !"QWERTOP".contains($0) }
    }
}
