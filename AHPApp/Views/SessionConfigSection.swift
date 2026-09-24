import AgentHostProtocol
import SwiftUI

/// A new session's settings, drawn from what the host describes
/// (`resolveSessionConfig`) rather than from a list built into the app, so a
/// host's new setting appears without an app change.
///
/// Renders the shapes a phone can offer directly — a string with an `enum`
/// becomes a picker, a boolean a switch — each in its own section with the
/// host's `description` underneath. Anything else keeps the host's resolved
/// value and is not shown.
struct SessionConfigSection: View {
    let schema: SessionConfigSchema
    let values: [String: AnyCodable]
    let onChange: (_ key: String, _ value: AnyCodable) -> Void

    /// Dictionary order is not the host's order, so sort by what the user reads.
    private var keys: [String] {
        schema.properties
            .filter { Self.options(for: $0.value) != nil || $0.value.type == "boolean" }
            .sorted { $0.value.title.localizedCompare($1.value.title) == .orderedAscending }
            .map(\.key)
    }

    var body: some View {
        ForEach(keys, id: \.self) { key in
            if let property = schema.properties[key] {
                Section {
                    row(key: key, property: property)
                } footer: {
                    if let description = property.description, !description.isEmpty {
                        Text(description)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(key: String, property: SessionConfigPropertySchema) -> some View {
        if let options = Self.options(for: property) {
            Picker(property.title, selection: Binding(
                get: { selectedValue(key: key, property: property, options: options) },
                set: { onChange(key, AnyCodable($0)) }
            )) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .disabled(property.readOnly == true)
        } else if property.type == "boolean" {
            Toggle(property.title, isOn: Binding(
                get: { (values[key]?.value as? Bool) ?? (property.default?.value as? Bool) ?? false },
                set: { onChange(key, AnyCodable($0)) }
            ))
            .disabled(property.readOnly == true)
        }
    }

    /// The current value, falling back to the schema default and then the first
    /// option: a picker whose selection matches no tag renders blank.
    private func selectedValue(
        key: String,
        property: SessionConfigPropertySchema,
        options: [(value: String, label: String)]
    ) -> String {
        let candidates = [values[key]?.value as? String, property.default?.value as? String]
        for case let value? in candidates where options.contains(where: { $0.value == value }) {
            return value
        }
        return options[0].value
    }

    /// A string property's choices with their labels, or nil if it is not an
    /// all-string enum.
    static func options(for property: SessionConfigPropertySchema) -> [(value: String, label: String)]? {
        guard property.type == "string",
              let raw = property.enum, !raw.isEmpty else { return nil }
        let values = raw.compactMap { $0.value as? String }
        guard values.count == raw.count else { return nil }
        return values.enumerated().map { index, value in
            let label = property.enumLabels.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            return (value, label ?? value)
        }
    }
}
