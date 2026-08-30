import SwiftUI

enum MarkdownInsertion: Equatable {
    case heading(Int)
    case bold
    case italic
    case underline
    case strikethrough
    case link
    case inlineCode
    case codeBlock
    case quote
    case bulletList
    case numberedList
    case checklist
}

/// Tags each toolbar tap with a unique id so `PlainTextEditor` can tell "already applied this
/// one" from "apply it" using a plain equality check, independent of exactly when/how often
/// SwiftUI re-invokes `updateNSView` for the same state value.
struct PendingMarkdownInsertion: Equatable {
    let id = UUID()
    let action: MarkdownInsertion
}

/// The markdown formatting bar shown when the "T" button is tapped — mirrors the reference
/// app's toolbar. Since notes are plain `.md` files, every action just inserts/wraps markdown
/// syntax around the current selection rather than applying rich-text attributes.
struct FormattingToolbar: View {
    var onInsert: (MarkdownInsertion) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Heading 1") { onInsert(.heading(1)) }
                Button("Heading 2") { onInsert(.heading(2)) }
                Button("Heading 3") { onInsert(.heading(3)) }
            } label: {
                HStack(spacing: 2) {
                    Text("H").font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
            }
            .menuIndicator(.hidden)

            Menu {
                Button("Bold") { onInsert(.bold) }
                Button("Italic") { onInsert(.italic) }
                Button("Underline") { onInsert(.underline) }
                Button("Strikethrough") { onInsert(.strikethrough) }
            } label: {
                HStack(spacing: 2) {
                    Text("I").italic().font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
            }
            .menuIndicator(.hidden)

            Button { onInsert(.link) } label: {
                Image(systemName: "link")
            }
            Button { onInsert(.inlineCode) } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }

            Divider().frame(height: 14)

            Button { onInsert(.codeBlock) } label: {
                Image(systemName: "curlybraces")
            }
            Button { onInsert(.quote) } label: {
                Image(systemName: "text.quote")
            }

            Divider().frame(height: 14)

            Menu {
                Button("Bullet List") { onInsert(.bulletList) }
                Button("Numbered List") { onInsert(.numberedList) }
                Button("Checklist") { onInsert(.checklist) }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "list.bullet")
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
            }
            .menuIndicator(.hidden)
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .font(.system(size: 13))
        .fixedSize()
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
    }
}
