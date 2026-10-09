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
        bit B KB MB GB TB PB KiB MiB GiB TiB PiB
        bps kbps Mbps Gbps mbps gbps dpi ppi px mp MP Mp em rem dB dBA ppm ppb ppt
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static func contains(_ raw: String) -> Bool { symbols.contains(raw) }

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
    static func allowsAfterQuantity(_ unit: String, hangul: String) -> Bool {
        guard contains(unit), KoreanDictionary.isLoaded else { return false }
        return !KoreanDictionary.contains(hangul)
            || unit.contains { $0.isUppercase && !"QWERTOP".contains($0) }
    }
}
