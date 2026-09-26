import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Quotes a selection into the message box. Set by the chat; where it is
    /// nil (a file viewer), selected text offers no Reply.
    @Entry var quoteReply: ((String) -> Void)? = nil
}

/// Read-only text that can be selected by range, like Messages or Notes.
///
/// SwiftUI's `.textSelection(.enabled)` on iOS only offers Copy and Share for
/// the whole text on a long press, with nothing highlighted — so it was never
/// clear what would be copied. A non-editable `UITextView` gives the system's
/// drag handles, and its edit menu takes a Reply that quotes the selection.
struct SelectableText: UIViewRepresentable {
    let text: NSAttributedString

    init(_ text: NSAttributedString) {
        self.text = text
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.reply = context.environment.quoteReply
        context.coordinator.openURL = context.environment.openURL
        if view.attributedText != text {
            view.attributedText = text
        }
    }

    /// As wide as the text needs, up to what is offered, so a short message's
    /// bubble hugs it; as tall as it wraps to at that width.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let limit = proposal.width.map { $0.isFinite ? $0 : .greatestFiniteMagnitude } ?? .greatestFiniteMagnitude
        let natural = text.boundingRect(
            with: CGSize(width: limit, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let width = min(limit, ceil(natural.width))
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var reply: ((String) -> Void)?
        var openURL: OpenURLAction?

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let reply, range.length > 0,
                  let selected = Range(range, in: textView.text).map({ String(textView.text[$0]) })
            else { return nil }
            let action = UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) { _ in
                reply(selected)
                textView.selectedTextRange = nil
            }
            return UIMenu(children: [action] + suggestedActions)
        }

        /// Links go through SwiftUI's `openURL`, where the chat resolves file
        /// links to its own viewer; the text view would otherwise open them
        /// with the system.
        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard case .link(let url) = textItem.content, let openURL else { return defaultAction }
            return UIAction { _ in openURL(url) }
        }
    }
}

enum QuoteReply {
    /// `selection` as a markdown blockquote, with a blank line after it to
    /// type the reply on.
    static func quoted(_ selection: String) -> String {
        let lines = selection
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? ">" : "> \($0)" }
        return lines.joined(separator: "\n") + "\n\n"
    }

    /// The draft with the quote added: after whatever is already typed,
    /// separated by a blank line, so replying twice builds up both quotes.
    static func draft(_ current: String, quoting selection: String) -> String {
        let quote = quoted(selection)
        let kept = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return kept.isEmpty ? quote : kept + "\n\n" + quote
    }
}
