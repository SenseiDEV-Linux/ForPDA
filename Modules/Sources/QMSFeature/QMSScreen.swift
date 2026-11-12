//
//  QMSScreen.swift
//  ForPDA
//
//  Created by Ilia Lubianoi on 17.11.2024.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ComposableArchitecture
import SharedUI
import SFSafeSymbols
import ExyteChat
import UploadBoxFeature
import BBPanelFeature

@ViewAction(for: QMSFeature.self)
public struct QMSScreen: View {
    
    // MARK: - Properties
    
    @Perception.Bindable public var store: StoreOf<QMSFeature>
    @Environment(\.tintColor) private var tintColor
    @Environment(\.backgroundColors) private var backgroundColors
    @FocusState private var focusedInput: Int?
    
    // MARK: - Init
    
    public init(store: StoreOf<QMSFeature>) {
        self.store = store
    }
    
    // MARK: - Body
    
    public var body: some View {
        WithPerceptionTracking {
            ZStack {
                backgroundColors.primary
                    .ignoresSafeArea()

                if store.chat != nil {
                    ChatView(messages: store.messages) { message in
                        // send(.sendMessageButtonTapped(message))
                    } inputViewBuilder: { text, _, _, inputViewStyle, inputViewActionClosure, _ in
                        WithPerceptionTracking {
                            Group {
                                switch inputViewStyle {
                                case .message:
                                    InputView(text: text)
                                case .signature:
                                    EmptyView()
                                }
                            }
                        }
                    } messageMenuAction: { (action: ChatAction, _, message) in
                        if case .copy = action {
                            UIPasteboard.general.string = message.text
                        }
                    }
                    .keyboardDismissMode(.interactive)
                    .enableLoadMore { _ in
                        await send(.loadMoreTriggered)
                    }
                    .linkPreviewsDisabled()
                    .messageUseStyler { string in
                        return QMSBuilder(text: string).build()
                    }
                    .setAvailableInputs([.text])
                    .chatTheme(
                        ChatTheme(
                            colors: ChatTheme
                                .Colors(
                                    mainBG: backgroundColors.primary,
                                    messageMyBG: Color(.Background.quaternary),
                                    messageMyText: Color(.Labels.primary),
                                    messageMyTimeText: Color(.systemGray),
                                    messageFriendBG: Color(.Background.quaternary),
                                    messageFriendText: Color(.Labels.primary),
                                    messageFriendTimeText: Color(.systemGray),
                                    statusGray: Color(.Theme.primary),
                                    sendButtonBackground: Color(.Theme.primary)
                                )
                        )
                    )
                    .environment(\.openURL, OpenURLAction(handler: { url in
                        send(.urlTapped(url))
                        return .handled
                    }))
                } else {
                    PDALoader()
                        .frame(width: 24, height: 24)
                }
            }
            .navigationTitle(store.title)
            ._toolbarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: Binding($store.upload.destination.fileImporter)) {
                QMSDocumentPicker(
                    isPresented: Binding($store.upload.destination.fileImporter),
                    onPick: { urls in
                        if urls.isEmpty {
                            store.send(.upload(.view(.fileImporterURLsRecievingFailure)))
                        } else {
                            store.send(.upload(.view(.fileImporterURLsRecieved(urls))))
                        }
                    }
                )
                .ignoresSafeArea()
            }
            .alert($store.scope(\.$alert, action: \.alert))
            .onAppear {
                send(.onAppear)
            }
        }
    }
    
    private func InputView(text: Binding<String>) -> some View {
        VStack(spacing: 8) {
            UploadBoxView(
                store: store.scope(\.upload, action: \.upload),
                usesExternalFileImporter: true
            )
            .disabled(store.isSending)
            
            HStack(alignment: .bottom, spacing: 8) {
                #if DEBUG
                if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                    Button(String("+")) { text.wrappedValue += "text" }
                        .buttonStyle(.borderedProminent)
                }
                #endif
                
                Button {
                    send(.attachmentButtonTapped)
                } label: {
                    Image(systemSymbol: .paperclip)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(tintColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("qms.attachments.add", bundle: .module))
                .disabled(store.isSending || store.upload.isAnyFileUploading)
                
                Field(
                    content: text,
                    placeholder: LocalizedStringResource("qms.textfield.placeholder", bundle: .module),
                    focusEqual: store.chatId,
                    focus: $focusedInput,
                    minHeight: 96,
                    selection: $store.draftTextRange,
                    bbPanel: {
                        BBPanelView(store: store.scope(\.bbPanel, action: \.bbPanel))
                            .onTapGesture {
                                focusedInput = store.chatId
                            }
                    }
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0)
                
                Button {
                    send(.sendMessageButtonTapped(
                        DraftMessage(text: text.wrappedValue, medias: [], giphyMedia: nil, recording: nil, replyMessage: nil, createdAt: .now)
                    ))
                } label: {
                    Circle()
                        .fill(Color(.Theme.primary))
                        .frame(width: 44, height: 44)
                        .overlay {
                            if store.isSending {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Image(systemSymbol: .arrowUp)
                                    .bold()
                                    .foregroundStyle(.white)
                            }
                        }
                        .opacity(store.canSendMessage ? 1 : 0.55)
                }
                .disabled(!store.canSendMessage)
                .accessibilityLabel(Text("qms.message.send", bundle: .module))
            }
        }
        .padding()
        .animation(.default, value: store.isSending)
        .animation(.default, value: store.canSendMessage)
        .animation(.default, value: text.wrappedValue)
        .bind($focusedInput, to: $store.focus)
        .bind(text, to: $store.draftText)
    }
}

private struct QMSDocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            asCopy: false
        )
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.onPick = onPick
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var isPresented: Binding<Bool>
        var onPick: ([URL]) -> Void

        init(isPresented: Binding<Bool>, onPick: @escaping ([URL]) -> Void) {
            self.isPresented = isPresented
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            // Explicitly drive the SwiftUI presentation state closed before forwarding the URLs.
            isPresented.wrappedValue = false
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresented.wrappedValue = false
        }
    }
}

// MARK: - Previews

#Preview {
    @Shared(.userSession) var userSession
    $userSession.withLock { $0 = .init(userId: 1, token: "", isHidden: false) }
    
    return NavigationStack {
        QMSScreen(
            store: Store(
                initialState: QMSFeature.State(chatId: 0)
            ) {
                QMSFeature()
            } withDependencies: { _ in
                
            }
        )
    }
    .environment(\.tintColor, Color(.Theme.primary))
    .environment(\.locale, Locale(identifier: "en"))
}

#Preview("Error On Send") {
    @Shared(.userSession) var userSession
    $userSession.withLock { $0 = .init(userId: 1, token: "", isHidden: false) }
    
    return QMSScreen(
        store: Store(initialState: QMSFeature.State(chatId: 0)) {
            QMSFeature()
        } withDependencies: {
            $0.qmsClient = .errorOnSend
        }
    )
    .environment(\.tintColor, Color(.Theme.primary))
    .environment(\.locale, Locale(identifier: "en"))
}
