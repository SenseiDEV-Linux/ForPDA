//
//  ForumScreen.swift
//  ForPDA
//
//  Created by Ilia Lubianoi on 02.09.2024.
//

import SwiftUI
import ComposableArchitecture
import SFSafeSymbols
import SharedUI

@ViewAction(for: ForumsListFeature.self)
public struct ForumsListScreen: View {
    
    // MARK: - Properties
    
    @Perception.Bindable public var store: StoreOf<ForumsListFeature>
    @Environment(\.tintColor) private var tintColor
    @Environment(\.backgroundColors) private var backgroundColors
    
    // MARK: - Init
    
    public init(store: StoreOf<ForumsListFeature>) {
        self.store = store
    }
    
    // MARK: - Body
    
    public var body: some View {
        WithPerceptionTracking {
            ZStack {
                backgroundColors.primary
                    .ignoresSafeArea()

                if isLiquidGlass {
                    ForumBlurredBackdrop(tint: tintColor)
                }
                
                if let forums = store.forums {
                    List(forums, id: \.id) { forumRow in
                        WithPerceptionTracking {
                            Section {
                                if store.isExpanded[forumRow.id]! {
                                    ForEach(forumRow.forums) { forum in
                                        ForumRow(
                                            title: forum.name,
                                            isUnread: forum.isUnread,
                                            onAction: {
                                                if let redirectUrl = forum.redirectUrl {
                                                    send(.forumRedirectTapped(redirectUrl))
                                                } else {
                                                    send(.forumTapped(id: forum.id, name: forum.name))
                                                }
                                            }
                                        )
                                    }
                                    
                                }
                            } header: {
                                Header(forumRow: forumRow)
                            }
                            .listRowBackground(ForumListSurface(fallback: backgroundColors.tertiary))
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .animation(.easeInOut(duration: 0.3), value: store.isExpanded)
                } else {
                    PDALoader()
                        .frame(width: 24, height: 24)
                }
            }
            .animation(.default, value: store.forums)
            .navigationTitle(Text("Forum", bundle: .module))
            ._toolbarTitleDisplayMode(.large)
            .toolbar {
                Button {
                    send(.searchButtonTapped)
                } label: {
                    Image(systemSymbol: .magnifyingglass)
                }
            }
            .onAppear {
                send(.onAppear)
            }
        }
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private func Header(forumRow: ForumRowInfo) -> some View {
        Button {
            send(.forumSectionExpandTapped(forumRow.id))
        } label: {
            HStack(spacing: 0) {
                Text(forumRow.title)
                    .font(.subheadline)
                    .foregroundStyle(Color(.Labels.teritary))
                    .textCase(nil)
                    .offset(x: -16)
                
                Spacer()
                
                Image(systemSymbol: .chevronUp)
                    .font(.body)
                    .foregroundStyle(Color(.Labels.quaternary))
                    .rotationEffect(.degrees(store.isExpanded[forumRow.id]! ? 0 : -180))
                    .offset(x: 16)
            }
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        ForumsListScreen(
            store: Store(
                initialState: ForumsListFeature.State()
            ) {
                ForumsListFeature()
            }
        )
    }
}

// Keep the native grouped list, including its separators and section behaviour.
private struct ForumListSurface: View {
    let fallback: Color

    var body: some View {
        if #available(iOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: Rectangle())
        } else {
            fallback
        }
    }
}

// Soft colour beneath the glass, without changing the readability of list text.
private struct ForumBlurredBackdrop: View {
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .fill(tint.opacity(0.24))
                    .frame(width: geometry.size.width * 0.9)
                    .offset(x: -geometry.size.width * 0.38, y: -geometry.size.height * 0.3)
                Circle()
                    .fill(Color.blue.opacity(0.16))
                    .frame(width: geometry.size.width * 0.85)
                    .offset(x: geometry.size.width * 0.4, y: geometry.size.height * 0.2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .blur(radius: 80)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
