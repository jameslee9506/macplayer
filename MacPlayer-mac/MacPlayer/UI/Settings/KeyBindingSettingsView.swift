import SwiftUI

/// Settings view for customizing keyboard shortcuts.
struct KeyBindingSettingsView: View {
    let keyBindingManager: KeyBindingManager

    @State private var recordingAction: PlayerAction?

    var body: some View {
        Form {
            Section {
                ForEach(keyBindingManager.bindings) { binding in
                    HStack {
                        Text(binding.action.displayName)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if recordingAction == binding.action {
                            KeyRecorderView { keyCode, modifiers in
                                keyBindingManager.updateBinding(
                                    for: binding.action,
                                    keyCode: keyCode,
                                    modifiers: modifiers
                                )
                                recordingAction = nil
                            }
                            .frame(width: 120, height: 24)
                        } else {
                            Button(action: { recordingAction = binding.action }) {
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
                    keyBindingManager.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
