//
//  HistoryScreen.swift
//  ForPDA
//
//  Created by Xialtal on 8.11.24.
//

import SwiftUI
import ComposableArchitecture
import PageNavigationFeature
import SFSafeSymbols
import SharedUI
import Models

@ViewAction(for: HistoryFeature.self)
public struct HistoryScreen: View {
    
    // MARK: - Properties
    
    @Perception.Bindable public var store: StoreOf<HistoryFeature>
    @Environment(\.tintColor) private var tintColor
    @Environment(\.backgroundColors) private var backgroundColors
    @State private var navigationMinimized = false
    
    private var shouldShowInlineNavigation: Bool {
        let isAnyFloatingNavigationEnabled = store.appSettings.floatingNavigation || store.appSettings.experimentalFloatingNavigation
        return store.pageNavigation.shouldShow && (!isLiquidGlass || !isAnyFloatingNavigationEnabled)
    }
    
    private var shouldShowFloatingNavigation: Bool {
        return isLiquidGlass && store.appSettings.floatingNavigation && !store.appSettings.experimentalFloatingNavigation
    }
    
    // MARK: - Init
    
    public init(store: StoreOf<HistoryFeature>) {
        self.store = store
    }
    
    // MARK: - Body
    
    public var body: some View {
        WithPerceptionTracking {
            ZStack {
                backgroundColors.primary
                    .ignoresSafeArea()

                if isLiquidGlass {
                    HistoryBlurredBackdrop(tint: tintColor)
                }
                
                List {
                    if !store.history.isEmpty, !store.isLoading {
                        Navigation()
                        
                        ForEach(store.history, id: \.self) { history in
                            HistorySection(history: history)
                        }
                        
                        Navigation()
                    }
                }
                .scrollContentBackground(.hidden)
                ._inScrollContentDetector(isEnabled: shouldShowFloatingNavigation, state: $navigationMinimized)
                .overlay(alignment: .center) {
                    if !store.isLoading, store.history.isEmpty {
                        EmptyHistory()
                    }
                }
            }
            .animation(.default, value: store.history)
            .navigationTitle(Text("History", bundle: .module))
            ._toolbarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if shouldShowFloatingNavigation {
                    PageNavigation(
                        store: store.scope(\.pageNavigation, action: \.pageNavigation),
                        minimized: $navigationMinimized
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .overlay {
                if store.isLoading {
                    PDALoader()
                        .frame(width: 24, height: 24)
                }
            }
            .onAppear {
                send(.onAppear)
            }
        }
    }
    
    // MARK: - Page Navigation
    
    @ViewBuilder
    private func Navigation() -> some View {
        if shouldShowInlineNavigation {
            PageNavigation(store: store.scope(\.pageNavigation, action: \.pageNavigation))
                .listRowBackground(isLiquidGlass ? Color.clear : backgroundColors.primary)
        }
    }
    
    // MARK: - History Section
    
    private func HistorySection(history: HistoryRow) -> some View {
        Section {
            ForEach(history.topics, id: \.id) { topic in
                TopicRow(
                    title: .plain(topic.name),
                    date: topic.lastPost.date,
                    username: topic.lastPost.username,
                    isClosed: topic.isClosed,
                    isUnread: topic.isUnread,
                    onAction: { unreadTapped in
                        send(.topicTapped(topic, showUnread: unreadTapped))
                    }
                )
            }
        } header: {
            Header(title: history.seenDate.formattedDateOnly())
        }
        .listRowBackground(HistoryGlassSurface(fallback: backgroundColors.tertiary))
    }
    
    // MARK: - Empty History
            
    @ViewBuilder
    private func EmptyHistory() -> some View {
        VStack(spacing: 0) {
            Image(systemSymbol: .clockArrowCirclepath)
                .font(.title)
                .foregroundStyle(tintColor)
                .frame(width: 48, height: 48)
                .padding(.bottom, 6)
            
            Text("No history", bundle: .module)
                .font(.title3)
                .bold()
                .foregroundColor(.primary)
                .padding(.bottom, 6)
            
            Text("View any topic in forum and it displays here.", bundle: .module)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.7)
        }
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private func Header(title: LocalizedStringKey) -> some View {
        Text(title, bundle: .module)
            .font(.subheadline)
            .foregroundStyle(Color(.Labels.teritary))
            .textCase(nil)
            .offset(x: -16)
            .padding(.bottom, 4)
    }
}

// MARK: - Extensions

private extension Date {

    func formattedDateOnly() -> LocalizedStringKey {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"

        if Calendar.current.isDateInToday(self) {
            return LocalizedStringKey("Today")
        } else if Calendar.current.isDateInYesterday(self) {
            return LocalizedStringKey("Yesterday")
        }
        
        return LocalizedStringKey("\(formatter.string(from: self))")
    }
}

// MARK: - Extensions

extension Bundle {
    static var models: Bundle? {
        return Bundle.allBundles.first(where: { $0.bundlePath.contains("Models") })
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        HistoryScreen(
            store: Store(
                initialState: HistoryFeature.State()
            ) {
                HistoryFeature()
            }
        )
    }
}

// Keep the native grouped list and the original appearance on earlier iOS.
private struct HistoryGlassSurface: View {
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

private struct HistoryBlurredBackdrop: View {
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
