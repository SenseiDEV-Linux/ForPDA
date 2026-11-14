//
//  LiquidGlass.swift
//  ForPDA
//
//  Central Liquid Glass toolkit.
//  Every glass call in the app goes through this file, so behaviour can be
//  tuned in one place (and safely degrades to plain content below iOS 26).
//

import SwiftUI

// MARK: - Namespace

public enum LiquidGlass {
    
    // MARK: - Glass Type
    
    public enum GlassEffectType: Sendable {
        case clear, identity, regular
        
        @available(iOS 26.0, *)
        public func asGlass() -> Glass {
            switch self {
            case .clear:    return .clear
            case .identity: return .identity
            case .regular:  return .regular
            }
        }
    }
    
    // MARK: - Shape
    
    /// Shape of the glass surface, described without generics so it can be
    /// passed around and stored.
    public enum ShapeKind: Sendable {
        /// Rounded rectangle with the given corner radius.
        case rect(cornerRadius: CGFloat)
        /// Fully rounded capsule (bars, pills, buttons).
        case capsule
        /// Perfect circle (floating circular buttons).
        case circle
        
        /// Default corner radius used across the app (matches `isLiquidGlass ? 28 : 14`).
        public static let card = ShapeKind.rect(cornerRadius: 28)
        
        /// Corner radius for nested/inner elements (quotes, code, badges).
        public static let inner = ShapeKind.rect(cornerRadius: 16)
    }
    
    // MARK: - Defaults
    
    /// Spacing used by `LiquidGlassContainer` when none is provided.
    public static let defaultSpacing: CGFloat = 8
    
    /// Radius of the app-wide "big" elements (bars, panels, fields).
    public static let cardRadius: CGFloat = 28
    
    /// Radius of the app-wide "small" elements (cards inside lists, quotes).
    public static let innerRadius: CGFloat = 16
}

// MARK: - Container

/// Wraps content into a `GlassEffectContainer` on iOS 26+ so that neighboring
/// glass surfaces can merge/blend, and renders plain content below that.
public struct LiquidGlassContainer<Content: View>: View {
    
    private let spacing: CGFloat?
    private let content: () -> Content
    
    public init(
        spacing: CGFloat? = LiquidGlass.defaultSpacing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.spacing = spacing
        self.content = content
    }
    
    public var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

// MARK: - Glass Modifier

public struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    
    let glass: LiquidGlass.GlassEffectType
    let shape: S
    let isInteractive: Bool
    let isEnabled: Bool
    
    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *), isEnabled {
            content
                .glassEffect(glass.asGlass().interactive(isInteractive), in: shape)
        } else {
            content
        }
    }
}

// MARK: - Service Glass (buttons / controls)

public struct LiquidGlassServiceModifier<S: InsettableShape>: ViewModifier {
    
    let shape: S
    let tint: Color?
    let isInteractive: Bool
    let isEnabled: Bool
    
    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *), isEnabled {
            if let tint {
                content
                    .glassEffect(
                        .regular
                            .tint(tint)
                            .interactive(isInteractive),
                        in: shape
                    )
            } else {
                content
                    .glassEffect(.regular.interactive(isInteractive), in: shape)
            }
        } else {
            content
        }
    }
}

// MARK: - Glass Union (merging surfaces)

public struct LiquidGlassUnionModifier<ID: Hashable>: ViewModifier {
    
    let id: ID
    let namespace: Namespace.ID
    let isEnabled: Bool
    
    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *), isEnabled {
            content
                .glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - View Extensions

public extension View {
    
    /// Applies Liquid Glass with a rounded-rect shape on iOS 26+.
    /// Below iOS 26 nothing changes — the view keeps its original background.
    @ViewBuilder
    func liquidGlass(
        _ glass: LiquidGlass.GlassEffectType = .regular,
        cornerRadius: CGFloat = LiquidGlass.innerRadius,
        isInteractive: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            LiquidGlassModifier(
                glass: glass,
                shape: RoundedRectangle(cornerRadius: cornerRadius),
                isInteractive: isInteractive,
                isEnabled: isEnabled
            )
        )
    }
    
    /// Applies Liquid Glass with an explicit shape on iOS 26+.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(
        _ glass: LiquidGlass.GlassEffectType = .regular,
        in shape: S,
        isInteractive: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            LiquidGlassModifier(
                glass: glass,
                shape: shape,
                isInteractive: isInteractive,
                isEnabled: isEnabled
            )
        )
    }
    
    /// Applies Liquid Glass using a `ShapeKind` (useful when the shape is stored).
    @ViewBuilder
    func liquidGlass(
        _ glass: LiquidGlass.GlassEffectType = .regular,
        shape kind: LiquidGlass.ShapeKind,
        isInteractive: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        switch kind {
        case .rect(let cornerRadius):
            liquidGlass(glass, cornerRadius: cornerRadius, isInteractive: isInteractive, isEnabled: isEnabled)
        case .capsule:
            liquidGlass(glass, in: Capsule(), isInteractive: isInteractive, isEnabled: isEnabled)
        case .circle:
            liquidGlass(glass, in: Circle(), isInteractive: isInteractive, isEnabled: isEnabled)
        }
    }
    
    /// Glass for interactive controls. Optionally tinted with the app accent
    /// color (or any explicit color) for prominent actions.
    @ViewBuilder
    func liquidGlassService(
        cornerRadius: CGFloat = LiquidGlass.innerRadius,
        tint: Color? = nil,
        isInteractive: Bool = true,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            LiquidGlassServiceModifier(
                shape: RoundedRectangle(cornerRadius: cornerRadius),
                tint: tint,
                isInteractive: isInteractive,
                isEnabled: isEnabled
            )
        )
    }
    
    /// Glass for interactive controls with an explicit shape.
    @ViewBuilder
    func liquidGlassService<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        isInteractive: Bool = true,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            LiquidGlassServiceModifier(
                shape: shape,
                tint: tint,
                isInteractive: isInteractive,
                isEnabled: isEnabled
            )
        )
    }
    
    /// Glass service shortcut for capsule-shaped controls (tab items, pills).
    @ViewBuilder
    func liquidGlassCapsule(
        tint: Color? = nil,
        isInteractive: Bool = true,
        isEnabled: Bool = true
    ) -> some View {
        liquidGlassService(in: Capsule(), tint: tint, isInteractive: isInteractive, isEnabled: isEnabled)
    }
    
    /// Glass service shortcut for circular controls (floating buttons).
    @ViewBuilder
    func liquidGlassCircle(
        tint: Color? = nil,
        isInteractive: Bool = true,
        isEnabled: Bool = true
    ) -> some View {
        liquidGlassService(in: Circle(), tint: tint, isInteractive: isInteractive, isEnabled: isEnabled)
    }
    
    /// Merges this glass surface with the one having the same `id` inside
    /// the given namespace (shapes flow into each other when close).
    @ViewBuilder
    func liquidGlassUnion<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        isEnabled: Bool = true
    ) -> some View {
        modifier(LiquidGlassUnionModifier(id: id, namespace: namespace, isEnabled: isEnabled))
    }
}

// MARK: - Shapes

public extension RoundedRectangle {
    /// App-wide outer radius (28 on iOS 26, 14 before).
    static var liquidCard: RoundedRectangle {
        RoundedRectangle(cornerRadius: isLiquidGlass ? LiquidGlass.cardRadius : 14)
    }
    
    /// App-wide inner radius (16 on iOS 26, 12 before).
    static var liquidInner: RoundedRectangle {
        RoundedRectangle(cornerRadius: isLiquidGlass ? LiquidGlass.innerRadius : 12)
    }
}
