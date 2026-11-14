//
//  LiquidGlass+Containers.swift
//  ForPDA
//
//  Ready-made liquid glass surfaces for the patterns used across the app:
//  cards in scroll content, bars, pills and list rows.
//  All of them render exactly what was there before on iOS < 26.
//

import SwiftUI

// MARK: - Glass Card

/// A card-like surface inside scroll content.
/// iOS 26: transparent container + liquid glass, so the content underneath
/// (topic, article, images) shines through the card.
/// iOS < 26: keeps the original solid background color.
public struct LiquidGlassCard<Content: View>: View {
    
    @Environment(\.backgroundColors) private var backgroundColors
    
    private let glass: LiquidGlass.GlassEffectType
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let fallbackColor: Color?
    private let isInteractive: Bool
    private let content: () -> Content
    
    public init(
        _ glass: LiquidGlass.GlassEffectType = .regular,
        cornerRadius: CGFloat = LiquidGlass.innerRadius,
        padding: CGFloat = 12,
        fallbackColor: Color? = nil,
        isInteractive: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.glass = glass
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.fallbackColor = fallbackColor
        self.isInteractive = isInteractive
        self.content = content
    }
    
    public var body: some View {
        content()
            .padding(padding)
            .background {
                if !isLiquidGlass {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fallbackColor ?? backgroundColors.tertiary)
                }
            }
            .liquidGlass(glass, cornerRadius: cornerRadius, isInteractive: isInteractive)
    }
}

// MARK: - Glass Bar

/// Bottom / floating bar (input field row, BB panel, player controls).
public struct LiquidGlassBar<Fallback: View, Content: View>: View {
    
    private let glass: LiquidGlass.GlassEffectType
    private let shape: LiquidGlass.ShapeKind
    private let isInteractive: Bool
    private let fallback: () -> Fallback
    private let content: () -> Content
    
    public init(
        _ glass: LiquidGlass.GlassEffectType = .regular,
        shape: LiquidGlass.ShapeKind = .capsule,
        isInteractive: Bool = false,
        @ViewBuilder fallback: @escaping () -> Fallback,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.glass = glass
        self.shape = shape
        self.isInteractive = isInteractive
        self.fallback = fallback
        self.content = content
    }
    
    public var body: some View {
        content()
            .background {
                if !isLiquidGlass {
                    fallback()
                }
            }
            .liquidGlass(glass, shape: shape, isInteractive: isInteractive)
    }
}

// MARK: - Glass Pill

/// Small capsule surface: counters, tags, "last edit" badges, chips.
public struct LiquidGlassPill<Content: View>: View {
    
    @Environment(\.backgroundColors) private var backgroundColors
    
    private let cornerRadius: CGFloat
    private let fallbackColor: Color?
    private let content: () -> Content
    
    public init(
        cornerRadius: CGFloat = 10,
        fallbackColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.fallbackColor = fallbackColor
        self.content = content
    }
    
    public var body: some View {
        content()
            .background {
                if !isLiquidGlass {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fallbackColor ?? backgroundColors.tertiary)
                }
            }
            .liquidGlass(.regular, cornerRadius: cornerRadius)
    }
}

// MARK: - Row Background

/// Glass surface used as a `listRowBackground` replacement.
/// Keeps the list layout untouched: the system still clips it to the row,
/// but on iOS 26 the row gets a real liquid glass surface instead of a solid color.
public struct LiquidGlassRowBackground: View {
    
    private let fallback: Color
    private let cornerRadius: CGFloat
    
    public init(
        fallback: Color,
        cornerRadius: CGFloat = LiquidGlass.innerRadius
    ) {
        self.fallback = fallback
        self.cornerRadius = cornerRadius
    }
    
    public var body: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        } else {
            fallback
        }
    }
}

// MARK: - List Row Glass

/// Glass background for list rows / list sections.
/// Replaces `listRowBackground(backgroundColors.tertiary)` on iOS 26.
public struct LiquidGlassListRowModifier: ViewModifier {
    
    private let cornerRadius: CGFloat
    private let glass: LiquidGlass.GlassEffectType
    
    public init(
        cornerRadius: CGFloat = LiquidGlass.innerRadius,
        glass: LiquidGlass.GlassEffectType = .regular
    ) {
        self.cornerRadius = cornerRadius
        self.glass = glass
    }
    
    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .liquidGlass(glass, cornerRadius: cornerRadius)
                .padding(.vertical, 2)
        } else {
            content
        }
    }
}

// MARK: - Grouped Shape

/// Shape for rows that are visually grouped inside a section: the first row
/// gets rounded top corners, the last one rounded bottom corners and the rows
/// in between stay square, so the group reads as a single glass slab.
public struct LiquidGroupedShape: InsettableShape {
    
    public enum Position: Sendable {
        case single, first, middle, last
    }
    
    private let radius: CGFloat
    private let position: Position
    private var inset: CGFloat = 0
    
    public init(radius: CGFloat, position: Position) {
        self.radius = radius
        self.position = position
    }
    
    public func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let r = max(0, radius - inset)
        
        let top: CGFloat = (position == .first || position == .single) ? r : 0
        let bottom: CGFloat = (position == .last || position == .single) ? r : 0
        
        return Path(
            roundedRect: rect,
            cornerRadii: RectangleCornerRadii(
                topLeading: top,
                bottomLeading: bottom,
                bottomTrailing: bottom,
                topTrailing: top
            ),
            style: .continuous
        )
    }
    
    public func inset(by amount: CGFloat) -> LiquidGroupedShape {
        var copy = self
        copy.inset += amount
        return copy
    }
}

public extension LiquidGroupedShape.Position {
    /// Позиция строки в сгруппированной секции.
    static func of(_ index: Int, count: Int) -> LiquidGroupedShape.Position {
        let total = max(1, count)
        if total == 1 { return .single }
        if index == 0 { return .first }
        if index == total - 1 { return .last }
        return .middle
    }
}

// MARK: - View Extensions

public extension View {
    
    /// Glass row background inside `List` (iOS 26 only, no-op before).
    @ViewBuilder
    func liquidGlassListRow(
        cornerRadius: CGFloat = LiquidGlass.innerRadius,
        glass: LiquidGlass.GlassEffectType = .regular
    ) -> some View {
        modifier(LiquidGlassListRowModifier(cornerRadius: cornerRadius, glass: glass))
    }
    
    /// Grouped row inside a list section: one glass slab per section.
    @ViewBuilder
    func liquidGlassGroupedRow(
        radius: CGFloat = 24,
        position: LiquidGroupedShape.Position,
        isInteractive: Bool = false
    ) -> some View {
        self.liquidGlass(
            .regular,
            in: LiquidGroupedShape(radius: radius, position: position),
            isInteractive: isInteractive
        )
    }
    
    /// Row background that becomes liquid glass on iOS 26 and stays the
    /// original color below it (works on both `View` and `Section`).
    @ViewBuilder
    func liquidRowBackground(
        fallback: Color,
        cornerRadius: CGFloat = LiquidGlass.innerRadius
    ) -> some View {
        self.listRowBackground(
            LiquidGlassRowBackground(fallback: fallback, cornerRadius: cornerRadius)
        )
    }
    
    /// Расширяет фон контента под навигационный бар, чтобы стекло бара
    /// размывало сам контент, а не пустоту (no-op до iOS 26).
    @ViewBuilder
    func liquidGlassToolbar() -> some View {
        if isLiquidGlass {
            self
                .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self
        }
    }
}

// MARK: - Grouped Row Background

/// `listRowBackground` для строк, которые визуально слиты в одну плиту:
/// на iOS 26 каждый ряд получает стеклянную поверхность с нужными углами,
/// на iOS < 26 — прежний цветной фон с теми же радиусами.
public struct LiquidGlassGroupedRowBackground: View {
    
    private let position: LiquidGroupedShape.Position
    private let fallbackColor: Color
    private let radius: CGFloat
    private let glass: LiquidGlass.GlassEffectType
    
    public init(
        position: LiquidGroupedShape.Position,
        fallbackColor: Color,
        radius: CGFloat = 24,
        glass: LiquidGlass.GlassEffectType = .regular
    ) {
        self.position = position
        self.fallbackColor = fallbackColor
        self.radius = radius
        self.glass = glass
    }
    
    public var body: some View {
        if #available(iOS 26.0, *) {
            let shape = LiquidGroupedShape(radius: radius, position: position)
            shape
                .fill(.clear)
                .glassEffect(glass.asGlass(), in: shape)
        } else {
            let top: CGFloat = (position == .first || position == .single) ? radius : 0
            let bottom: CGFloat = (position == .last || position == .single) ? radius : 0
            fallbackColor
                .clipShape(
                    .rect(
                        topLeadingRadius: top,
                        bottomLeadingRadius: bottom,
                        bottomTrailingRadius: bottom,
                        topTrailingRadius: top
                    )
                )
        }
    }
}
