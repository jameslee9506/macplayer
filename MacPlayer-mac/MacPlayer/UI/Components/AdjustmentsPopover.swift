import SwiftUI

/// Popover for video filters, rotation, and audio sync — all per-file settings.
struct AdjustmentsPopover: View {
    let engine: PlaybackEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Filters section
            sectionHeader("Filters")
            ForEach(engine.filters.filters.indices, id: \.self) { i in
                filterRow(index: i)
            }

            Divider().padding(.vertical, 6)

            // Rotation
            sectionHeader("Rotation")
            HStack {
                Text("\(engine.videoRotation)°")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
                Spacer()
                Button("−90") { engine.rotateBy(-90) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("+90") { engine.rotateBy(90) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Reset") { engine.setRotation(0) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(engine.videoRotation == 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            Divider().padding(.vertical, 6)

            // Audio Sync
            sectionHeader("Audio Sync")
            HStack(spacing: 8) {
                Text(audioDelayLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
                Slider(
                    value: audioDelayBinding,
                    in: -5...5,
                    step: 0.05
                )
                Button("Reset") { engine.setAudioDelay(0) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(engine.audioDelay == 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider().padding(.vertical, 2)

            // Reset All
            HStack {
                Spacer()
                Button("Reset All") {
                    engine.resetAllAdjustments()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasAnyAdjustment)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .frame(width: 300)
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }

    private func filterRow(index: Int) -> some View {
        let filter = engine.filters.filters[index]
        let param = filter.parameters[0]
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { engine.filters.filters[index].isEnabled },
                set: {
                    engine.filters.filters[index].isEnabled = $0
                    engine.syncFiltersToMPV()
                    engine.needsFrameRefresh = true
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text(filter.name)
                .font(.system(size: 11))
                .frame(width: 64, alignment: .leading)

            Slider(
                value: Binding(
                    get: { engine.filters.filters[index].parameters[0].value },
                    set: {
                        engine.filters.filters[index].parameters[0].value = $0
                        if !engine.filters.filters[index].isEnabled {
                            engine.filters.filters[index].isEnabled = true
                        }
                        engine.syncFiltersToMPV()
                        engine.needsFrameRefresh = true
                    }
                ),
                in: param.minValue...param.maxValue
            )

            Text(paramLabel(param))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
    }

    // MARK: - Helpers

    private var audioDelayBinding: Binding<Double> {
        Binding(
            get: { engine.audioDelay },
            set: { engine.setAudioDelay($0) }
        )
    }

    private var audioDelayLabel: String {
        let d = engine.audioDelay
        if d == 0 { return "0.00s" }
        let sign = d > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", d))s"
    }

    private func paramLabel(_ param: FilterParameter) -> String {
        if param.defaultValue == 0 {
            return String(format: "%.2f", param.value)
        } else {
            return String(format: "%.1f", param.value)
        }
    }

    private var hasAnyAdjustment: Bool {
        engine.filters.hasActiveFilters
            || engine.videoRotation != 0
            || engine.audioDelay != 0
    }
}
