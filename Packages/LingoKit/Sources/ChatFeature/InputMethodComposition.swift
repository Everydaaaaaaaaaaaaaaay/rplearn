import UIKit

/// 输入法组字状态：拼音、注音等输入法在选字确认前，键入的字母以“标记文本”留在输入框里。
/// SwiftUI 的输入框会把这些未确认的字母同步给绑定的文本，实时翻译要等它们确认后再进行。
@MainActor
enum InputMethodComposition {
    fileprivate static weak var responder: UIResponder?

    /// 当前第一响应者还有未确认的标记文本。
    static var isComposing: Bool {
        responder = nil
        defer { responder = nil }
        UIApplication.shared.sendAction(
            #selector(UIResponder.lingoCaptureFirstResponder(_:)), to: nil, from: nil, for: nil
        )
        return (responder as? UITextInput)?.markedTextRange != nil
    }
}

extension UIResponder {
    @objc fileprivate func lingoCaptureFirstResponder(_ sender: Any?) {
        InputMethodComposition.responder = self
    }
}
