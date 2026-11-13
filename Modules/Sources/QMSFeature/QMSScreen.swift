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
            screenContent
        }
    }

    private var screenContent: some View {
        ZStack {
            backgroundColors.primary
                .ignoresSafeArea()

            filePickerPresenter
            imageExportPresenter
            chatContent
        }
        .navigationTitle(store.title)
        ._toolbarTitleDisplayMode(.inline)
        .alert($store.scope(\.$alert, action: \.alert))
        .confirmationDialog(
            Text("qms.delete.message.title", bundle: .module),
            isPresented: Binding($store.isDeleteMessageConfirmationPresented),
            titleVisibility: .visible
        ) {
            if store.pendingDeleteMessageIsOwn {
                Button(
                    String(localized: "qms.delete.message.forAll", bundle: .module),
                    role: .destructive
                ) {
                    send(.deleteMessageConfirmed(forAll: true))
                }
            }
            Button(
                String(localized: "qms.delete.message.forMe", bundle: .module),
                role: .destructive
            ) {
                send(.deleteMessageConfirmed(forAll: false))
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        }
        .onAppear {
            send(.onAppear)
        }
    }

    private var filePickerPresenter: some View {
        QMSFilePickerPresenter(
            isPresented: Binding($store.upload.destination.fileImporter).wrappedValue,
            onPick: { urls in
                if urls.isEmpty {
                    store.send(.upload(.view(.fileImporterURLsRecievingFailure)))
                } else {
                    store.send(.upload(.view(.fileImporterURLsRecieved(urls))))
                }
            },
            onCancel: {
                store.send(.upload(.destination(.dismiss)))
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var imageExportPresenter: some View {
        QMSImageExportPresenter(
            isPresented: store.isImageExportPresented,
            urls: store.imageExportFileURLs,
            onFinish: { didExport in
                store.send(.view(.imageFileExportFinished(didExport)))
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var chatContent: AnyView {
        if store.chat != nil {
            return makeChatView()
        } else {
            return AnyView(
                PDALoader()
                    .frame(width: 24, height: 24)
            )
        }
    }

    private func makeChatView() -> AnyView {
        AnyView(
            ChatView(messages: store.messages) { message in
                // send(.sendMessageButtonTapped(message))
            } inputViewBuilder: { text, _, _, inputViewStyle, _, _ in
                makeInputView(text: text, style: inputViewStyle)
            } messageMenuAction: { (action: ChatAction, _, message) in
                handleMessageMenuAction(action, message: message)
            }
            .keyboardDismissMode(.interactive)
            .enableLoadMore { _ in
                await send(.loadMoreTriggered)
            }
            .linkPreviewsDisabled()
            .messageUseStyler { string in
                QMSBuilder(text: string).build()
            }
            .setAvailableInputs([.text])
            .chatTheme(qmsChatTheme)
            .environment(\.openURL, OpenURLAction(handler: handleOpenURL))
        )
    }

    private var qmsChatTheme: ChatTheme {
        ChatTheme(
            colors: ChatTheme.Colors(
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
    }

    private func handleMessageMenuAction(_ action: ChatAction, message: ExyteChat.Message) {
        switch action {
        case .copy:
            UIPasteboard.general.string = message.text
        case .delete:
            guard let messageId = Int(message.id) else { return }
            send(.deleteMessageTapped(
                messageId: messageId,
                isOwnMessage: message.user.isCurrentUser
            ))
        case .saveToPhotos:
            send(.saveImagesToPhotos(imageURLs(in: message)))
        case .saveToFiles:
            send(.saveImagesToFiles(imageURLs(in: message)))
        }
    }

    private func imageURLs(in message: ExyteChat.Message) -> [URL] {
        message.attachments
            .filter { $0.type == .image }
            .map(\.full)
    }

    private func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
        send(.urlTapped(url))
        return .handled
    }

    private func makeInputView(text: Binding<String>, style: InputViewStyle) -> AnyView {
        switch style {
        case .message:
            return AnyView(
                WithPerceptionTracking {
                    InputView(text: text)
                }
            )
        case .signature:
            return AnyView(EmptyView())
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

private struct QMSFilePickerPresenter: UIViewControllerRepresentable {
    let isPresented: Bool
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> QMSFilePickerPresenterController {
        let controller = QMSFilePickerPresenterController()
        controller.configure(isPresented: isPresented, onPick: onPick, onCancel: onCancel)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: QMSFilePickerPresenterController,
        context: Context
    ) {
        uiViewController.configure(isPresented: isPresented, onPick: onPick, onCancel: onCancel)
    }
}

private final class QMSFilePickerPresenterController: UIViewController,
    UIDocumentPickerDelegate,
    UIAdaptivePresentationControllerDelegate
{
    private var shouldPresentPicker = false
    private var didPresentPickerForCurrentRequest = false
    private var documentPicker: UIDocumentPickerViewController?
    private var onPick: ([URL]) -> Void = { _ in }
    private var onCancel: () -> Void = {}

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentPickerIfNeeded()
    }

    func configure(
        isPresented: Bool,
        onPick: @escaping ([URL]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onPick = onPick
        self.onCancel = onCancel

        if isPresented {
            shouldPresentPicker = true
            presentPickerIfNeeded()
        } else {
            shouldPresentPicker = false
            didPresentPickerForCurrentRequest = false
            dismissPickerIfNeeded()
        }
    }

    private func presentPickerIfNeeded() {
        guard shouldPresentPicker,
              !didPresentPickerForCurrentRequest,
              viewIfLoaded?.window != nil,
              documentPicker == nil,
              presentedViewController == nil
        else { return }

        didPresentPickerForCurrentRequest = true
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            // QMS uploads file bytes; import a sandbox copy instead of opening the provider file in place.
            asCopy: true
        )
        picker.allowsMultipleSelection = true
        picker.modalPresentationStyle = .fullScreen
        picker.delegate = self
        documentPicker = picker
        present(picker, animated: true) { [weak self, weak picker] in
            picker?.presentationController?.delegate = self
        }
    }

    private func dismissPickerIfNeeded() {
        guard let picker = documentPicker else { return }
        documentPicker = nil
        guard picker.presentingViewController != nil, !picker.isBeingDismissed else { return }
        picker.dismiss(animated: true)
    }

    private func finishPicker(
        _ picker: UIDocumentPickerViewController,
        completion: @escaping () -> Void
    ) {
        guard documentPicker === picker else { return }
        documentPicker = nil

        if picker.presentingViewController != nil, !picker.isBeingDismissed {
            picker.dismiss(animated: true, completion: completion)
        } else {
            completion()
        }
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        finishPicker(controller) { [weak self] in
            self?.onPick(urls)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishPicker(controller) { [weak self] in
            self?.onCancel()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let picker = documentPicker else { return }
        finishPicker(picker) { [weak self] in
            self?.onCancel()
        }
    }
}

private struct QMSImageExportPresenter: UIViewControllerRepresentable {
    let isPresented: Bool
    let urls: [URL]
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> QMSImageExportPresenterController {
        let controller = QMSImageExportPresenterController()
        controller.configure(isPresented: isPresented, urls: urls, onFinish: onFinish)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: QMSImageExportPresenterController,
        context: Context
    ) {
        uiViewController.configure(isPresented: isPresented, urls: urls, onFinish: onFinish)
    }
}

private final class QMSImageExportPresenterController: UIViewController,
    UIDocumentPickerDelegate,
    UIAdaptivePresentationControllerDelegate
{
    private var shouldPresentPicker = false
    private var didPresentPicker = false
    private var documentPicker: UIDocumentPickerViewController?
    private var fileURLs: [URL] = []
    private var onFinish: (Bool) -> Void = { _ in }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentPickerIfNeeded()
    }

    func configure(isPresented: Bool, urls: [URL], onFinish: @escaping (Bool) -> Void) {
        self.fileURLs = urls
        self.onFinish = onFinish
        if isPresented {
            shouldPresentPicker = true
            presentPickerIfNeeded()
        } else {
            shouldPresentPicker = false
            didPresentPicker = false
            dismissPickerIfNeeded()
        }
    }

    private func presentPickerIfNeeded() {
        guard shouldPresentPicker,
              !didPresentPicker,
              !fileURLs.isEmpty,
              viewIfLoaded?.window != nil,
              documentPicker == nil,
              presentedViewController == nil
        else { return }

        didPresentPicker = true
        let picker = UIDocumentPickerViewController(forExporting: fileURLs, asCopy: true)
        picker.modalPresentationStyle = .fullScreen
        picker.delegate = self
        documentPicker = picker
        present(picker, animated: true) { [weak self, weak picker] in
            picker?.presentationController?.delegate = self
        }
    }

    private func dismissPickerIfNeeded() {
        guard let picker = documentPicker else { return }
        documentPicker = nil
        guard picker.presentingViewController != nil, !picker.isBeingDismissed else { return }
        picker.dismiss(animated: true)
    }

    private func finishPicker(_ picker: UIDocumentPickerViewController, didExport: Bool) {
        guard documentPicker === picker else { return }
        documentPicker = nil
        shouldPresentPicker = false
        let completion: () -> Void = { [weak self] in
            guard let self else { return }
            self.onFinish(didExport)
        }
        if picker.presentingViewController != nil, !picker.isBeingDismissed {
            picker.dismiss(animated: true, completion: completion)
        } else {
            completion()
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finishPicker(controller, didExport: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishPicker(controller, didExport: false)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let picker = documentPicker else { return }
        finishPicker(picker, didExport: false)
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
