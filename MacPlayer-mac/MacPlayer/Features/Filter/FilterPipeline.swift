import Foundation
import Metal

/// A video filter that processes frames via Metal compute shaders.
protocol VideoFilter: Identifiable, Sendable {
    var id: String { get }
    var name: String { get }
    var isEnabled: Bool { get set }
    var parameters: [FilterParameter] { get set }
}

/// Filter parameter with name, value, and range.
struct FilterParameter: Identifiable, Sendable {
    let id: String
    let name: String
    var value: Float
    let minValue: Float
    let maxValue: Float
    let defaultValue: Float
}

/// Standard video filters (brightness, contrast, saturation, sharpen, deband).
struct StandardFilter: VideoFilter {
    let id: String
    let name: String
    var isEnabled: Bool
    var parameters: [FilterParameter]

    static func brightness() -> StandardFilter {
        StandardFilter(
            id: "brightness", name: "Brightness", isEnabled: false,
            parameters: [FilterParameter(id: "value", name: "Brightness", value: 0, minValue: -1, maxValue: 1, defaultValue: 0)]
        )
    }

    static func contrast() -> StandardFilter {
        StandardFilter(
            id: "contrast", name: "Contrast", isEnabled: false,
            parameters: [FilterParameter(id: "value", name: "Contrast", value: 1, minValue: 0, maxValue: 3, defaultValue: 1)]
        )
    }

    static func saturation() -> StandardFilter {
        StandardFilter(
            id: "saturation", name: "Saturation", isEnabled: false,
            parameters: [FilterParameter(id: "value", name: "Saturation", value: 1, minValue: 0, maxValue: 3, defaultValue: 1)]
        )
    }

    static func sharpen() -> StandardFilter {
        StandardFilter(
            id: "sharpen", name: "Sharpen", isEnabled: false,
            parameters: [FilterParameter(id: "amount", name: "Amount", value: 0, minValue: 0, maxValue: 2, defaultValue: 0)]
        )
    }

    static func deband() -> StandardFilter {
        StandardFilter(
            id: "deband", name: "Deband", isEnabled: false,
            parameters: [FilterParameter(id: "threshold", name: "Threshold", value: 48, minValue: 0, maxValue: 128, defaultValue: 48)]
        )
    }
}

/// Manages the filter chain applied to video frames.
@MainActor
@Observable
final class FilterManager {
    var filters: [StandardFilter] = [
        .brightness(),
        .contrast(),
        .saturation(),
        .sharpen(),
        .deband()
    ]

    var hasActiveFilters: Bool {
        filters.contains { $0.isEnabled }
    }

    func resetAll() {
        for i in filters.indices {
            filters[i].isEnabled = false
            for j in filters[i].parameters.indices {
                filters[i].parameters[j].value = filters[i].parameters[j].defaultValue
            }
        }
    }
}
