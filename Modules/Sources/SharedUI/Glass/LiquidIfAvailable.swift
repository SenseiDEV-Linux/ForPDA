//
//  LiquidIfAvailable.swift
//  ForPDA
//
//  Created by Ilia Lubianoi on 27.08.2025.
//

import SwiftUI

public struct LiquidIfAvailable: ViewModifier {
    
    public enum GlassEffectType {
        case clear, identity, regular
        
        @available(iOS 26.0, *)
        func asGlass() -> Glass {
            switch self {
            case .clear:    return .clear
            case .identity: return .identity
            case .regular:  return .regular
            }
        }
        
        var asLiquidGlass: LiquidGlass.GlassEffectType {
            switch self {
            case .clear:    return .clear
            case .identity: return .identity
            case .regular:  return .regular
            }
        }
    }
    
    let glass: GlassEffectType
    let isInteractive: Bool
    
    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    glass.asGlass()
                        .interactive(isInteractive)
                )
        } else {
            content
        }
    }
}

// MARK: - Shape Aware Variant

public struct LiquidShapeIfAvailable<S: InsettableShape>: ViewModifier {
    
    let glass: LiquidIfAvailable.GlassEffectType
    let shape: S
    let isInteractive: Bool
    
    public func body(content: Content) -> some View {
        content
            .liquidGlass(
                glass.asLiquidGlass,
                in: shape,
                isInteractive: isInteractive
            )
    }
}

public extension View {
    func liquidIfAvailable(
        glass: LiquidIfAvailable.GlassEffectType = .regular,
        isInteractive: Bool = false
    ) -> some View {
        modifier(LiquidIfAvailable(glass: glass, isInteractive: isInteractive))
    }
    
    func liquidIfAvailable(
        glass: LiquidIfAvailable.GlassEffectType = .regular,
        in shape: some InsettableShape,
        isInteractive: Bool = false
    ) -> some View {
        modifier(LiquidShapeIfAvailable(glass: glass, shape: shape, isInteractive: isInteractive))
    }
    
    func liquidIfAvailable(
        glass: LiquidIfAvailable.GlassEffectType = .regular,
        cornerRadius: CGFloat,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            LiquidShapeIfAvailable(
                glass: glass,
                shape: RoundedRectangle(cornerRadius: cornerRadius),
                isInteractive: isInteractive
            )
        )
    }
}
