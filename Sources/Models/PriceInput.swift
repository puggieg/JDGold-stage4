import Foundation

// FIX(B10): 空白/0 表示关闭；支持全角数字、小数逗号和规范的千位分组。
// 例：８００，５ → 800.5；１，２３４．５６ → 1234.56；1,2,3 是错误输入。
// 不接受负数、NaN、Infinity、科学计数法，避免错误内容静默覆盖老配置。
public func parsePriceInput(_ raw: String) -> Double? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let fullWidth = Array("０１２３４５６７８９．，＋－")
    let halfWidth = Array("0123456789.,+-")
    text = String(text.map { char in
        if let index = fullWidth.firstIndex(of: char) { return halfWidth[index] }
        return char
    })
    if text.isEmpty { return 0 }
    if text.contains(",") {
        if text.range(of: #"^\+?[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?$"#, options: .regularExpression) != nil {
            text = text.replacingOccurrences(of: ",", with: "")
        } else if text.range(of: #"^\+?[0-9]+,[0-9]{1,2}$"#, options: .regularExpression) != nil {
            text = text.replacingOccurrences(of: ",", with: ".")
        } else { return nil }
    }
    guard text.range(of: #"^\+?([0-9]+(\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
          let value = Double(text), value.isFinite, value >= 0 else { return nil }
    return value
}

