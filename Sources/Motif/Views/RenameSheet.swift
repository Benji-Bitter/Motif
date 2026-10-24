import SwiftUI

/// Small rename dialog shared by the library and studios.
struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let onRename: (String) -> Void

    init(title: String, onRename: @escaping (String) -> Void) {
        _text = State(initialValue: title)
        self.onRename = onRename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename").font(.headline)
            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename") {
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { onRename(trimmed) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}
