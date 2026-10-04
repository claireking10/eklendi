import SwiftUI

/// Reusable three-way swipe stack (KAL-12). Right = yes, left = no, down = maybe
/// (CLAUDE.md "Core interaction: the swipe").
///
///     SwipeCardStack(items: slots,
///                    onVote: { slot, vote in votes[slot.id] = vote },
///                    onFinished: { submit() }) { slot in
///         TimeSlotCardContent(slot: slot)   // your card body; add your own padding
///     }
///
/// - Cards are drawn as a stack (up to 3 visible). Swiping the top card away reveals the
///   next one, which is already underneath (no drop-in animation).
/// - While dragging, the border glows teal (yes) or white (maybe); dragging left (no)
///   gradually covers the card with a shadow coming from the top-left corner.
/// - Tappable No / Maybe / Yes buttons under the stack (ids "swipeNo", "swipeMaybe", "swipeYes").
/// - The stack provides the card chrome (fill, 28pt corners, border, clipping). `content`
///   fills the whole card; draw a photo background inside it if needed.
/// - Progress is tracked by item id, so appending items (e.g. a suggested time) just adds
///   cards to the end. `onFinished` fires after the vote that leaves no unvoted items.
///   To restart ("Redo my swipes"), give the stack a new `.id(...)`.
/// - `onVote` is called once per card, after its exit animation.
struct SwipeCardStack<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let onVote: (Item, Vote) -> Void
    let onFinished: () -> Void
    var showsButtons: Bool = true
    let content: (Item) -> Content

    @State private var votedIds: Set<Item.ID> = []
    @State private var drag: CGSize = .zero
    @State private var exiting: Vote? = nil
    @State private var exitingId: Item.ID? = nil
    @State private var pendingToken: Int = 0
    @State private var voteCount: Int = 0

    private let swipeThreshold: CGFloat = 90
    private let exitDuration: Double = 0.28

    init(items: [Item],
         showsButtons: Bool = true,
         onVote: @escaping (Item, Vote) -> Void,
         onFinished: @escaping () -> Void = {},
         @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.showsButtons = showsButtons
        self.onVote = onVote
        self.onFinished = onFinished
        self.content = content
    }

    private struct Layer: Identifiable {
        let id: Item.ID
        let item: Item
        let depth: Int
    }

    private var remaining: [Item] {
        items.filter { !votedIds.contains($0.id) }
    }

    private var layers: [Layer] {
        let visible: [Item] = Array(remaining.prefix(3))
        var result: [Layer] = []
        for (index, item) in visible.enumerated() {
            result.append(Layer(id: item.id, item: item, depth: index))
        }
        return result.reversed()   // deepest first so the top card is drawn last
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                ForEach(layers) { layer in
                    card(for: layer)
                }
            }
            .padding(.bottom, 28)   // room for the cards peeking below
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsButtons {
                voteButtons
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: voteCount)
    }

    // MARK: Card

    /// One code path for every depth so a card keeps its identity (and loaded images)
    /// when it moves up to become the top card.
    private func card(for layer: Layer) -> some View {
        let isTop: Bool = layer.depth == 0
        let shift: Int = (exiting != nil && !isTop) ? layer.depth - 1 : layer.depth
        let depth: CGFloat = CGFloat(max(shift, 0))
        let backOffset = CGSize(width: 0, height: 14 * depth)

        return cardChrome(for: layer.item, isTop: isTop)
            .scaleEffect(isTop ? 1.0 : 1.0 - 0.05 * depth, anchor: .top)
            .offset(isTop ? topOffset : backOffset)
            .rotationEffect(.degrees(isTop ? topRotation : 0))
            .opacity(isTop ? topOpacity : 1)
            .zIndex(Double(10 - layer.depth))
            .gesture(dragGesture)
            .allowsHitTesting(isTop)
            .accessibilityHidden(!isTop)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(isTop ? "swipeCard" : "swipeCardBehind")
            .accessibilityAction(named: Text("Yes")) { commit(.yes) }
            .accessibilityAction(named: Text("Maybe")) { commit(.maybe) }
            .accessibilityAction(named: Text("No")) { commit(.no) }
            .transition(.identity)
    }

    private func cardChrome(for item: Item, isTop: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: EKRadius.swipeCard, style: .continuous)
        let glow: (color: Color, amount: Double) = isTop ? glowState : (color: EKColor.yesGlow, amount: 0)
        let shadow: Double = isTop ? noShadowProgress : 0
        return content(item)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(EKColor.card)
            .overlay(NoShadowOverlay(progress: shadow).allowsHitTesting(false))
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    glow.amount < 0.02 ? EKColor.swipeCardBorder : glow.color.opacity(0.35 + 0.65 * glow.amount),
                    lineWidth: 1 + 2 * glow.amount
                )
            )
            .shadow(color: glow.color.opacity(0.6 * glow.amount), radius: 16 * glow.amount)
            .contentShape(shape)
    }

    // MARK: Drag state → visuals

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    private var yesAmount: Double {
        if exiting == .yes { return 1 }
        if exiting != nil { return 0 }
        return clamp(Double(drag.width / swipeThreshold))
    }

    private var maybeAmount: Double {
        if exiting == .maybe { return 1 }
        if exiting != nil { return 0 }
        return clamp(Double((drag.height - abs(drag.width)) / swipeThreshold))
    }

    /// Strongest of yes (teal) / maybe (white).
    private var glowState: (color: Color, amount: Double) {
        let y: Double = yesAmount
        let m: Double = maybeAmount
        if y >= m { return (color: EKColor.yesGlow, amount: y) }
        return (color: EKColor.maybeGlow, amount: m)
    }

    /// 0 → no shadow, 1 → covered. Grows slowly (full at 220pt) so it doesn't cover too soon.
    private var noShadowProgress: Double {
        if exiting == .no { return 1 }
        if exiting != nil { return 0 }
        return clamp(Double(-drag.width / 220))
    }

    private var topOffset: CGSize {
        switch exiting {
        case .yes: return CGSize(width: 600, height: 40)
        case .no: return CGSize(width: -600, height: 40)
        case .maybe: return CGSize(width: 0, height: 900)
        case .none: return drag
        }
    }

    private var topRotation: Double {
        switch exiting {
        case .yes: return 22
        case .no: return -22
        case .maybe: return 0
        case .none: return Double(drag.width / 18)
        }
    }

    private var topOpacity: Double {
        switch exiting {
        case .yes, .maybe: return 0
        default: return 1
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard exiting == nil else { return }
                drag = CGSize(width: value.translation.width, height: max(0, value.translation.height))
            }
            .onEnded { value in
                guard exiting == nil else { return }
                let dx: CGFloat = value.translation.width
                let dy: CGFloat = value.translation.height
                let px: CGFloat = value.predictedEndTranslation.width
                let py: CGFloat = value.predictedEndTranslation.height
                var vote: Vote? = nil
                if dx > swipeThreshold || (px > swipeThreshold * 2.5 && dx > 30) {
                    vote = .yes
                } else if dx < -swipeThreshold || (px < -swipeThreshold * 2.5 && dx < -30) {
                    vote = .no
                } else if dy > swipeThreshold || (py > swipeThreshold * 2.5 && dy > 30) {
                    vote = .maybe
                }
                if let vote = vote {
                    commit(vote)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        drag = .zero
                    }
                }
            }
    }

    // MARK: Voting

    private func commit(_ vote: Vote) {
        // A second tap while a card is still flying off finishes that card right away.
        if exiting != nil { finishPending() }
        guard let item = remaining.first else { return }
        pendingToken += 1
        let token: Int = pendingToken
        exitingId = item.id
        withAnimation(.easeOut(duration: exitDuration)) {
            exiting = vote
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration) {
            if token == pendingToken { finishPending() }
        }
    }

    private func finishPending() {
        guard let vote = exiting, let id = exitingId,
              let item = items.first(where: { $0.id == id }) else {
            exiting = nil
            exitingId = nil
            return
        }
        var newVoted: Set<Item.ID> = votedIds
        newVoted.insert(id)
        let finished: Bool = items.allSatisfy { newVoted.contains($0.id) }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            votedIds = newVoted
            exiting = nil
            exitingId = nil
            drag = .zero
        }
        pendingToken += 1   // invalidate any scheduled finish for this card
        voteCount += 1
        onVote(item, vote)
        if finished { onFinished() }
    }

    // MARK: Buttons

    private var voteButtons: some View {
        HStack {
            Spacer()
            VoteCircleButton(vote: .no) { commit(.no) }
                .accessibilityIdentifier("swipeNo")
            Spacer()
            VoteCircleButton(vote: .maybe) { commit(.maybe) }
                .accessibilityIdentifier("swipeMaybe")
            Spacer()
            VoteCircleButton(vote: .yes) { commit(.yes) }
                .accessibilityIdentifier("swipeYes")
            Spacer()
        }
        .disabled(remaining.isEmpty)
    }
}

/// Shadow that sweeps in from the top-left corner as `progress` goes 0 → 1
/// (matches the design's 260% linear-gradient background-position trick).
struct NoShadowOverlay: View {
    let progress: Double

    var body: some View {
        let p: CGFloat = CGFloat(min(1, max(0, progress)))
        let origin: CGFloat = -1.6 * (1 - p)
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color.black.opacity(0.9), location: 0),
                Gradient.Stop(color: Color.black.opacity(0.9), location: 0.38),
                Gradient.Stop(color: Color.black.opacity(0), location: 0.62),
                Gradient.Stop(color: Color.black.opacity(0), location: 1),
            ],
            startPoint: UnitPoint(x: origin, y: origin),
            endPoint: UnitPoint(x: origin + 2.6, y: origin + 2.6)
        )
        .opacity(p < 0.001 ? 0 : 1)
    }
}

/// The round No / Maybe / Yes button used under swipe stacks (64pt circle + label).
struct VoteCircleButton: View {
    let vote: Vote
    let action: () -> Void

    private var title: String {
        switch vote {
        case .yes: return "Yes"
        case .maybe: return "Maybe"
        case .no: return "No"
        }
    }

    private var hint: String {
        switch vote {
        case .yes: return "Swipe right"
        case .maybe: return "Swipe down"
        case .no: return "Swipe left"
        }
    }

    @ViewBuilder
    private var ring: some View {
        switch vote {
        case .no:
            Circle().strokeBorder(EKColor.noRing, lineWidth: 2)
                .overlay(Image(systemName: "xmark").font(.system(size: 24, weight: .bold)).foregroundStyle(EKColor.noRing))
        case .maybe:
            Circle().strokeBorder(EKColor.maybeRing, lineWidth: 2)
                .overlay(Image(systemName: "arrow.down").font(.system(size: 24, weight: .bold)).foregroundStyle(EKColor.maybeRing))
        case .yes:
            Circle().fill(EKColor.teal)
                .overlay(Image(systemName: "checkmark").font(.system(size: 26, weight: .heavy)).foregroundStyle(EKColor.onTeal))
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ring
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color(hex: "#080E0F").opacity(0.85)))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(EKColor.textPrimary)
            }
        }
        .buttonStyle(VotePressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

private struct VotePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Preview

private struct SwipePreviewItem: Identifiable {
    let id: Int
    let weekday: String
    let time: String
}

private struct SwipeStackPreviewDemo: View {
    @State private var log: [String] = []
    @State private var finished: Bool = false
    private let items: [SwipePreviewItem] = [
        SwipePreviewItem(id: 1, weekday: "THURSDAY", time: "3:00 – 4:00 PM"),
        SwipePreviewItem(id: 2, weekday: "TUESDAY", time: "6:30 – 7:30 PM"),
        SwipePreviewItem(id: 3, weekday: "FRIDAY", time: "7:00 – 8:00 PM"),
        SwipePreviewItem(id: 4, weekday: "SATURDAY", time: "11:00 AM – 1:00 PM"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            if finished {
                Text("Done: \(log.joined(separator: ", "))").foregroundStyle(EKColor.textPrimary)
            } else {
                SwipeCardStack(items: items, onVote: { item, vote in
                    log.append("\(item.id)=\(vote.rawValue)")
                }, onFinished: {
                    finished = true
                }) { item in
                    VStack(spacing: 6) {
                        Text(item.weekday).font(EKFont.display).foregroundStyle(EKColor.textPrimary)
                        Text(item.time).font(EKFont.headline).foregroundStyle(EKColor.textPrimary)
                    }
                    .padding(22)
                }
                .frame(height: 520)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ekScreenBackground()
    }
}

#Preview {
    SwipeStackPreviewDemo()
}
