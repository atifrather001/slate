import SwiftUI

struct FindReplaceBar: View {
    @ObservedObject var state: AppState
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Find", text: $state.findText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .focused($findFocused)
                    .onSubmit(state.findNext)
                Button("Previous", action: state.findPrevious)
                Button("Next", action: state.findNext)
                Text(state.findMessage).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: state.hideFind).keyboardShortcut(.cancelAction)
            }
            if state.replacePanelVisible {
                HStack {
                    TextField("Replace", text: $state.replaceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                    Button("Replace", action: state.replaceCurrent)
                    Button("Replace All", action: state.replaceAll)
                }
            }
            HStack {
                Toggle("Match case", isOn: $state.findOptions.caseSensitive)
                Toggle("Whole word", isOn: $state.findOptions.wholeWord)
                Toggle("Regex", isOn: $state.findOptions.regex)
                Toggle("Wrap around", isOn: $state.findOptions.wrapAround)
            }
            .toggleStyle(.checkbox)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { findFocused = true }
        .onChange(of: state.findFocusRequest) { _, _ in findFocused = true }
    }
}
