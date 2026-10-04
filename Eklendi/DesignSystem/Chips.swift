import SwiftUI

/// Visual variants of a chip.
enum ChipStyle {
    /// Selected = teal fill + dark text; unselected = card fill + white text (durations, options).
    case standard
    /// "I don't care" style: outline; selected = teal outline + teal text.
    case dontCare
    /// Small suggestion chip with a leading "+" (interest ideas). Selection state is ignored.
    case suggestion
}

/// A single pill-shaped toggle. `Chip("1 hr", isSelected: sel) { sel.toggle() }`
struct Chip: View {
    let title: String
    var isSelected: Bool = false
    var style: ChipStyle = .standard
    var systemImage: String? = nil
    let action: () -> Void

    init(_ title: String, isSelected: Bool = false, style: ChipStyle = .standard,
         systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.style = style
        self.systemImage = systemImage
        self.action = action
    }

    private var background: Color {
        switch style {
        case .standard: return isSelected ? EKColor.teal : EKColor.card
        case .dontCare: return isSelected ? EKColor.raised : Color.clear
        case .suggestion: return EKColor.card
        }
    }

    private var foreground: Color {
        switch style {
        case .standard: return isSelected ? EKColor.onTeal : EKColor.textPrimary
        case .dontCare: return isSelected ? EKColor.teal : EKColor.muted
        case .suggestion: return EKColor.textSecondary
        }
    }

    private var border: Color {
        switch style {
        case .standard: return isSelected ? EKColor.teal : EKColor.raisedBorder
        case .dontCare: return isSelected ? EKColor.teal : EKColor.divider
        case .suggestion: return EKColor.raisedBorder
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if style == .suggestion {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage).font(.system(size: 14, weight: .bold))
                }
                Text(title)
                    .font(.system(size: style == .suggestion ? 14 : 16, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, style == .suggestion ? 14 : 18)
            .frame(minHeight: style == .suggestion ? 40 : 46)
            .background(Capsule().fill(background))
            .overlay(Capsule().stroke(border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Wraps chips onto multiple lines.
/// `ChipGroup(options: ["30 min", "1 hr"], selection: $multiSet)` (multi-select) or
/// `ChipGroup(options: opts, selection: $single)` (single-select, tap again to clear).
/// Generic: `ChipGroup(options: DurationOption.presets, title: { label($0) }, selection: $set)`.
struct ChipGroup<Option: Hashable>: View {
    private enum Mode {
        case single(Binding<Option?>)
        case multi(Binding<Set<Option>>)
    }

    let options: [Option]
    let title: (Option) -> String
    var style: ChipStyle = .standard
    var spacing: CGFloat = 10
    private let mode: Mode

    /// Multi-select.
    init(options: [Option], title: @escaping (Option) -> String, selection: Binding<Set<Option>>,
         style: ChipStyle = .standard, spacing: CGFloat = 10) {
        self.options = options
        self.title = title
        self.mode = .multi(selection)
        self.style = style
        self.spacing = spacing
    }

    /// Single-select (tapping the selected chip clears it).
    init(options: [Option], title: @escaping (Option) -> String, selection: Binding<Option?>,
         style: ChipStyle = .standard, spacing: CGFloat = 10) {
        self.options = options
        self.title = title
        self.mode = .single(selection)
        self.style = style
        self.spacing = spacing
    }

    private func isSelected(_ option: Option) -> Bool {
        switch mode {
        case .single(let binding): return binding.wrappedValue == option
        case .multi(let binding): return binding.wrappedValue.contains(option)
        }
    }

    private func toggle(_ option: Option) {
        switch mode {
        case .single(let binding):
            binding.wrappedValue = (binding.wrappedValue == option) ? nil : option
        case .multi(let binding):
            var set: Set<Option> = binding.wrappedValue
            if set.contains(option) { set.remove(option) } else { set.insert(option) }
            binding.wrappedValue = set
        }
    }

    var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(options, id: \.self) { option in
                Chip(title(option), isSelected: isSelected(option), style: style) {
                    toggle(option)
                }
            }
        }
    }
}

extension ChipGroup where Option == String {
    init(options: [String], selection: Binding<Set<String>>, style: ChipStyle = .standard) {
        self.init(options: options, title: { $0 }, selection: selection, style: style)
    }

    init(options: [String], selection: Binding<String?>, style: ChipStyle = .standard) {
        self.init(options: options, title: { $0 }, selection: selection, style: style)
    }
}

/// Simple left-aligned wrapping layout. `FlowLayout(spacing: 8) { ... }`
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth: CGFloat = proposal.width ?? .infinity
        let rows: [[CGSize]] = arrange(maxWidth: maxWidth, subviews: subviews)
        let vSpacing: CGFloat = lineSpacing ?? spacing
        var height: CGFloat = 0
        var width: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight: CGFloat = row.map { $0.height }.max() ?? 0
            let rowWidth: CGFloat = row.map { $0.width }.reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0))
            height += rowHeight
            if index > 0 { height += vSpacing }
            width = max(width, rowWidth)
        }
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let vSpacing: CGFloat = lineSpacing ?? spacing
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size: CGSize = subview.sizeThatFits(.unspecified)
            let fittedWidth: CGFloat = min(size.width, bounds.width)
            if x > bounds.minX && x + fittedWidth > bounds.maxX {
                x = bounds.minX
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: fittedWidth, height: size.height))
            x += fittedWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [[CGSize]] {
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for subview in subviews {
            let raw: CGSize = subview.sizeThatFits(.unspecified)
            let size = CGSize(width: min(raw.width, maxWidth), height: raw.height)
            if x > 0 && x + size.width > maxWidth {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        return rows
    }
}

/// Small non-interactive pill ("1 hr", "3 yes"). Defaults to the teal tint.
struct Pill: View {
    let text: String
    var background: Color = EKColor.pillTealBg
    var foreground: Color = EKColor.pillTealFg

    init(_ text: String, background: Color = EKColor.pillTealBg, foreground: Color = EKColor.pillTealFg) {
        self.text = text
        self.background = background
        self.foreground = foreground
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(background))
    }
}

private struct ChipsPreviewDemo: View {
    @State private var multi: Set<String> = ["1 hr"]
    @State private var single: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ChipGroup(options: ["30 min", "1 hr", "2 hr", "3 hr", "Custom"], selection: $multi)
            ChipGroup(options: ["Home", "Current location", "Somewhere else"], selection: $single)
            Chip("I don't care how long", isSelected: true, style: .dontCare) {}
            Chip("Coffee shops", style: .suggestion) {}
            HStack { Pill("1 hr"); Pill("2 maybe", background: EKColor.pillYellowBg, foreground: EKColor.pillYellowFg) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ekScreenBackground()
    }
}

#Preview {
    ChipsPreviewDemo()
}
