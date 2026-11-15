import SwiftUI

/// Settings view for customizing keyboard shortcuts.
struct KeyBindingSettingsView: View {
    let keyBindingManager: KeyBindingManager

    @State private var recordingAction: PlayerAction?
    /// The action whose last recording was refused, and what holds the keys it asked for.
    @State private var rejected: (action: PlayerAction, owner: String)?

    var body: some View {
        Form {
            Section {
                ForEach(keyBindingManager.bindings) { binding in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(binding.action.displayName)
                            if let rejected, rejected.action == binding.action {
                                Text("Already used by \(rejected.owner)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if recordingAction == binding.action {
                            KeyRecorderView(
                                onKeyRecorded: { keyCode, modifiers in
                                    record(keyCode: keyCode, modifiers: modifiers, for: binding.action)
                                },
                                onCancel: { recordingAction = nil }
                            )
                            .frame(width: 120, height: 24)
                        } else {
                            Button(action: {
                                rejected = nil
                                recordingAction = binding.action
                            }) {
                                Text(binding.displayString)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 100)
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 6)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section {
                Button("Reset to Defaults") {
                    rejected = nil
                    recordingAction = nil
                    keyBindingManager.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// Stores a recorded key combination, or says what already uses it.
    private func record(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, for action: PlayerAction) {
        if let owner = keyBindingManager.conflict(for: action, keyCode: keyCode, modifiers: modifiers) {
            rejected = (action, owner)
        } else {
            keyBindingManager.updateBinding(for: action, keyCode: keyCode, modifiers: modifiers)
            rejected = nil
        }
        recordingAction = nil
    }
}
