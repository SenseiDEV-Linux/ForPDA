//
//  QMSFeature.swift
//  ForPDA
//
//  Created by Ilia Lubianoi on 17.11.2024.
//

import CoreFoundation
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers
import ComposableArchitecture
import APIClient
import QMSClient
import PersistenceKeys
import Models
import AnalyticsClient
import NotificationsClient
import TCAExtensions
import ExyteChat
import UploadBoxFeature
import BBPanelFeature

// ExyteChat dismisses its full-screen message menu after a 300 ms animation.
private let qmsChatMenuDismissDelay = Duration.milliseconds(350)

@Reducer
public struct QMSFeature: Reducer, Sendable {
    
    public init() {}
    
    let defaultOffset = -30
    
    // MARK: - Enums
    
    public enum LoadKind {
        case latest // initial/refresh
        case older  // pagination
    }
    
    // MARK: - State
    
    @ObservableState
    public struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?
        
        @Shared(.appSettings) var appSettings: AppSettings
        @Shared(.userSession) var userSession: UserSession?
        
        public let chatId: Int
        public var chat: QMSChat?
        public var messages: [Message] = []
        var fullImageURLs: [Int: URL] = [:]
        var requestedFullImageURLIDs: Set<Int> = []
        var pendingDeleteMessageId: Int?
        var pendingDeleteMessageIsOwn = false
        var isDeleteMessageConfirmationPresented = false
        var isDeletingMessage = false
        var imageExportFileURLs: [URL] = []
        var isImageExportPresented = false
        var upload = UploadBoxFeature.State(type: .qms)
        var bbPanel = BBPanelFeature.State(for: .qms)
        var draftTextRange: NSRange?
        var focus: Int?
        
        var hasMoreOlderMessages = true
        var isLoadingMore = false
        var isSending = false
        
        var draftText = ""
        var draftSnapshot = ""
        
        var uploadedAttachmentIDs: [Int] {
            upload.files.compactMap { file in
                guard !file.isUploading, file.uploadingError == nil else { return nil }
                return file.serverId
            }
        }
        
        var canSendMessage: Bool {
            !isSending && !upload.isAnyFileUploading &&
            (!draftText.isEmpty || !uploadedAttachmentIDs.isEmpty)
        }
        
        public var title: String {
            if let chat {
                return chat.partnerName + " - " + chat.name
            } else {
                return ""
            }
        }
        
        public init(chatId: Int) {
            self.chatId = chatId
        }
    }
    
    // MARK: - Action
    
    public enum Action: BindableAction, ViewAction {
        case binding(BindingAction<State>)
        case upload(UploadBoxFeature.Action)
        case bbPanel(BBPanelFeature.Action)
        
        case alert(PresentationAction<Alert>)
        public enum Alert {
            case ok
        }
        
        case view(View)
        public enum View {
            case onAppear
            case attachmentButtonTapped
            case sendMessageButtonTapped(DraftMessage)
            case loadMoreTriggered
            case urlTapped(URL)
            case deleteMessageTapped(messageId: Int, isOwnMessage: Bool)
            case deleteMessageConfirmed(forAll: Bool)
            case saveImagesToPhotos([URL])
            case saveImagesToFiles([URL])
            case imageFileExportFinished(Bool)
        }
        
        case `internal`(Internal)
        public enum Internal {
            case loadChat
            case chatLoaded(Result<QMSChat, any Error>, LoadKind)
            case fullImageURLLoaded(Int, Result<URL, any Error>)
            case messageSent([Int])
            case messageSendError(any Error)
            case showDeleteMessageConfirmation
            case messageDeleted(Int, Result<String, any Error>)
            case imagesSavedToPhotos
            case imageSaveFailed(any Error)
            case imageFilesPrepared(Result<[URL], any Error>)
        }
        
        case delegate(Delegate)
        public enum Delegate {
            case handleUrl(URL)
            case fullyRead(_ userId: Int)
        }
    }
    
    // MARK: - Dependencies
    
    @Dependency(\.qmsClient) private var qmsClient
    @Dependency(\.analyticsClient) private var analyticsClient
    @Dependency(\.notificationCenter) private var notificationCenter
    @Dependency(\.notificationsClient) private var notificationsClient
    
    // MARK: - Body
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
        
        Scope(\.upload, action: \.upload) {
            UploadBoxFeature()
        }
        
        Scope(\.bbPanel, action: \.bbPanel) {
            BBPanelFeature()
        }
        
        Reduce<State, Action> { state, action in
            switch action {
            case .alert, .delegate, .upload:
                return .none
                
            case .view(.onAppear):
                return .merge([
                    .send(.internal(.loadChat)),
                    .run { send in
                        for await _ in notificationCenter.notifications(named: .sceneBecomeActive) {
                            await send(.internal(.loadChat))
                        }
                    },
                    .run { [chatId = state.chatId] send in
                        for await notification in notificationsClient.eventPublisher().values {
                            if case let .qms(id) = notification, chatId == id {
                                await send(.internal(.loadChat))
                            }
                        }
                    }
                ])
                
            case .view(.attachmentButtonTapped):
                guard !state.isSending, !state.upload.isAnyFileUploading else { return .none }
                return .send(.upload(.view(.selectFilesButtonTapped)))

            case let .view(.deleteMessageTapped(messageId, isOwnMessage)):
                guard !state.isDeletingMessage else { return .none }
                state.pendingDeleteMessageId = messageId
                state.pendingDeleteMessageIsOwn = isOwnMessage
                state.isDeleteMessageConfirmationPresented = false
                return .run { send in
                    do {
                        try await Task.sleep(for: qmsChatMenuDismissDelay)
                        await send(.internal(.showDeleteMessageConfirmation))
                    } catch is CancellationError {
                        return
                    }
                }

            case let .view(.deleteMessageConfirmed(forAll)):
                guard let messageId = state.pendingDeleteMessageId,
                      !state.isDeletingMessage,
                      !forAll || state.pendingDeleteMessageIsOwn
                else { return .none }
                state.pendingDeleteMessageId = nil
                state.isDeleteMessageConfirmationPresented = false
                state.isDeletingMessage = true
                return .run { [chatId = state.chatId] send in
                    let result = await Result {
                        try await qmsClient.deleteMessage(chatId, messageId, forAll)
                    }
                    await send(.internal(.messageDeleted(messageId, result)))
                }

            case let .view(.saveImagesToPhotos(urls)):
                guard !urls.isEmpty else { return .none }
                return .run { send in
                    do {
                        try await Task.sleep(for: qmsChatMenuDismissDelay)
                        let images = try await downloadQMSImages(from: urls)
                        try await saveQMSImagesToPhotos(images)
                        await send(.internal(.imagesSavedToPhotos))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.internal(.imageSaveFailed(error)))
                    }
                }

            case let .view(.saveImagesToFiles(urls)):
                guard !urls.isEmpty else { return .none }
                return .run { send in
                    do {
                        try await Task.sleep(for: qmsChatMenuDismissDelay)
                        let result = await Result {
                            let images = try await downloadQMSImages(from: urls)
                            return try writeQMSImagesToTemporaryFiles(images)
                        }
                        await send(.internal(.imageFilesPrepared(result)))
                    } catch is CancellationError {
                        return
                    }
                }

            case let .view(.imageFileExportFinished(didExport)):
                let fileURLs = state.imageExportFileURLs
                state.imageExportFileURLs = []
                state.isImageExportPresented = false
                if didExport {
                    state.alert = qmsImagesSavedToFilesAlert()
                }
                return .run { _ in
                    removeQMSImageExportFiles(fileURLs)
                }

            case let .bbPanel(.delegate(.tagTapped(tag))):
                let selection = state.draftTextRange ?? NSRange(location: state.draftText.utf16.count, length: 0)
                if let range = Range(selection, in: state.draftText) {
                    if range.isEmpty {
                        state.draftText.insert(contentsOf: "\(tag.0)\(tag.1)", at: range.lowerBound)
                        state.draftTextRange = NSRange(location: selection.location + tag.0.utf16.count, length: 0)
                    } else {
                        state.draftText.insert(contentsOf: tag.1, at: range.upperBound)
                        state.draftText.insert(contentsOf: tag.0, at: range.lowerBound)
                        state.draftTextRange = NSRange(
                            location: selection.location + tag.0.utf16.count,
                            length: selection.length
                        )
                    }
                } else {
                    let location = state.draftText.utf16.count
                    state.draftText.append("\(tag.0)\(tag.1)")
                    state.draftTextRange = NSRange(location: location + tag.0.utf16.count, length: 0)
                }
                state.focus = state.chatId
                return .none
                
            case .bbPanel:
                return .none
                
            case let .view(.sendMessageButtonTapped(draftMessage)):
                let attachments = state.uploadedAttachmentIDs
                guard !state.isSending,
                      !state.upload.isAnyFileUploading,
                      (!draftMessage.text.isEmpty || !attachments.isEmpty)
                else { return .none }
                
                state.draftText = ""
                state.draftTextRange = NSRange(location: 0, length: 0)
                state.draftSnapshot = draftMessage.text
                state.isSending = true
                
                return .run { [chatId = state.chatId, message = draftMessage.text, attachments] send in
                    try await qmsClient.sendMessage(chatId: chatId, message: message, attachments: attachments)
                    await send(.internal(.messageSent(attachments)))
                } catch: { error, send in
                    await send(.internal(.messageSendError(error)))
                }
                
            case .view(.loadMoreTriggered):
                guard !state.isLoadingMore else { return .none }
                guard state.hasMoreOlderMessages else { return .none }
                guard (state.chat?.totalCount ?? defaultOffset) > abs(defaultOffset) else { return .none }
                state.isLoadingMore = true
                return .run { [id = state.chatId, chat = state.chat] send in
                    let lastMessageId = chat?.messages.first?.id ?? 0
                    let result = await Result { try await qmsClient.loadChat(id, lastMessageId, defaultOffset) }
                    await send(.internal(.chatLoaded(result, .older)))
                }
                
            case let .internal(.messageSent(attachments)):
                state.isSending = false
                state.draftSnapshot = ""
                state.draftTextRange = NSRange(location: 0, length: 0)
                let sentAttachmentIDs = Set(attachments)
                state.upload.files.removeAll { file in
                    guard let serverId = file.serverId else { return false }
                    return sentAttachmentIDs.contains(serverId)
                }
                return .send(.internal(.loadChat))
                
            case let .internal(.messageSendError(error)):
                state.isSending = false
                state.draftText = state.draftSnapshot
                state.draftTextRange = NSRange(location: state.draftText.utf16.count, length: 0)
                state.draftSnapshot = ""
                state.alert = .somethingWentWrong
                analyticsClient.capture(error)
                return .none
                
            case .internal(.showDeleteMessageConfirmation):
                guard state.pendingDeleteMessageId != nil, !state.isDeletingMessage else { return .none }
                state.isDeleteMessageConfirmationPresented = true
                return .none

            case let .internal(.messageDeleted(messageId, result)):
                state.isDeletingMessage = false
                switch result {
                case .success:
                    if var chat = state.chat {
                        chat.messages.removeAll { $0.id == messageId }
                        state.chat = chat
                    }
                    state.messages.removeAll { $0.id == String(messageId) }
                    return .send(.internal(.loadChat))
                case let .failure(error):
                    state.alert = .somethingWentWrong
                    analyticsClient.capture(error)
                    return .none
                }

            case .internal(.imagesSavedToPhotos):
                state.alert = qmsImagesSavedToPhotosAlert()
                return .none

            case let .internal(.imageSaveFailed(error)):
                state.alert = qmsImageSaveFailedAlert(for: error)
                analyticsClient.capture(error)
                return .none

            case let .internal(.imageFilesPrepared(result)):
                switch result {
                case let .success(fileURLs):
                    guard !fileURLs.isEmpty else {
                        state.alert = .somethingWentWrong
                        return .none
                    }
                    state.imageExportFileURLs = fileURLs
                    state.isImageExportPresented = true
                case let .failure(error):
                    state.alert = qmsImageSaveFailedAlert(for: error)
                    analyticsClient.capture(error)
                }
                return .none

            case let .view(.urlTapped(url)):
                guard url.absoluteString.contains("act=findpost"),
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let act = components.queryItems?.first(where: { $0.name == "act" })?.value,
                      act == "findpost",
                      let pidRaw = components.queryItems?.first(where: { $0.name == "pid"})?.value,
                      let pid = Int(pidRaw)
                else {
                    return .send(.delegate(.handleUrl(url)))
                }
                
                return .run { [topicShowAllPosts = state.appSettings.topicShowAllPostsFilter] send in
                    @Dependency(\.apiClient) var api
                    let request = JumpForumRequest(
                        postId: pid,
                        topicId: 0,
                        postsFilter: topicShowAllPosts ? .all : .exceptDeleted,
                        type: .post
                    )
                    let response = try await api.jumpForum(request: request)
                    let url = URL(string: "https://4pda.to/forum/index.php?showtopic=\(response.id)&view=findpost&p=\(response.postId)")!
                    await send(.delegate(.handleUrl(url)))
                }
                
            case .internal(.loadChat):
                return .run { [id = state.chatId] send in
                    let result = await Result { try await qmsClient.loadChat(id, 0, defaultOffset) }
                    await send(.internal(.chatLoaded(result, .latest)))
                }
                
            case let .internal(.chatLoaded(result, loadKind)):
                state.isLoadingMore = false
                var fullImageIDsToResolve = Set<Int>()
                
                switch result {
                case let .success(chat):
                    let existingRemote = state.chat?.messages ?? []
                    let mergeResult = mergeRemoteMessages(
                        existing: existingRemote,
                        incoming: chat.messages,
                        loadKind: loadKind
                    )
                    
                    var mergedChat = chat
                    mergedChat.messages = mergeResult.messages
                    
                    fullImageIDsToResolve = Set(mergeResult.messages.flatMap { message in
                        message.attachments.compactMap { attachment -> Int? in
                            guard attachment.type == .image,
                                  attachment.metadata != nil,
                                  attachment.metadata?.fullUrl == nil,
                                  state.fullImageURLs[attachment.id] == nil,
                                  !state.requestedFullImageURLIDs.contains(attachment.id)
                            else { return nil }
                            return attachment.id
                        }
                    })
                    state.requestedFullImageURLIDs.formUnion(fullImageIDsToResolve)

                    state.messages = makeLocalMessages(
                        from: mergeResult.messages,
                        chat: mergedChat,
                        currentUserId: state.userSession!.userId,
                        fullImageURLs: state.fullImageURLs
                    )
                    state.chat = mergedChat
                    
                    if mergeResult.messages.count >= chat.totalCount {
                        state.hasMoreOlderMessages = false
                    } else if loadKind == .older, mergeResult.uniqueIncomingCount == 0 {
                        state.hasMoreOlderMessages = false
                    } else {
                        state.hasMoreOlderMessages = true
                    }
                    
                case let .failure(error):
                    analyticsClient.capture(error)
                    state.alert = .somethingWentWrong
                }
                
                analyticsClient.reportFullyDisplayed()
                return .merge([
                    .run { [userId = state.chat!.partnerId] send in
                        let ids = (try? result.get().id).map { [$0] } ?? []
                        await notificationsClient.removeNotifications(ids: ids)
                        await send(.delegate(.fullyRead(userId)))
                    },
                    .run { [ids = fullImageIDsToResolve] send in
                        @Dependency(\.apiClient) var apiClient
                        let getAttachment = apiClient.getAttachment
                        await withTaskGroup(of: (Int, Result<URL, any Error>).self) { group in
                            for id in ids {
                                group.addTask {
                                    let result = await Result { try await getAttachment(id) }
                                    return (id, result)
                                }
                            }
                            for await (id, result) in group {
                                await send(.internal(.fullImageURLLoaded(id, result)))
                            }
                        }
                    }
                ])

            case let .internal(.fullImageURLLoaded(id, result)):
                state.requestedFullImageURLIDs.remove(id)
                if case let .success(url) = result {
                    state.fullImageURLs[id] = url
                    if let chat = state.chat {
                        state.messages = makeLocalMessages(
                            from: chat.messages,
                            chat: chat,
                            currentUserId: state.userSession!.userId,
                            fullImageURLs: state.fullImageURLs
                        )
                    }
                }
                return .none
                
            case .binding:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
        
        // Disabled until redesign
        // Analytics()
    }
    
    // MARK: - Shared Logic
    
    private struct RemoteMergeResult {
        let messages: [QMSMessage]
        let uniqueIncomingCount: Int
    }
    
    private func mergeRemoteMessages(
        existing: [QMSMessage],
        incoming: [QMSMessage],
        loadKind _: LoadKind
    ) -> RemoteMergeResult {
        let existingIds = Set(existing.map(\.id))
        var seenIncomingIds = Set<Int>()
        var uniqueIncomingCount = 0
        
        for message in incoming {
            if !existingIds.contains(message.id), seenIncomingIds.insert(message.id).inserted {
                uniqueIncomingCount += 1
            }
        }
        
        var messagesById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for message in incoming {
            messagesById[message.id] = message
        }
        
        let mergedMessages = messagesById.values.sorted {
            if $0.date == $1.date {
                return $0.id < $1.id
            }
            return $0.date < $1.date
        }
        
        return RemoteMergeResult(messages: mergedMessages, uniqueIncomingCount: uniqueIncomingCount)
    }
    
    private func makeLocalMessages(
        from remoteMessages: [QMSMessage],
        chat: QMSChat,
        currentUserId: Int,
        fullImageURLs: [Int: URL]
    ) -> [Message] {
        var localMessages = remoteMessages.map { remoteMessage in
            let isCurrentUser = currentUserId == remoteMessage.senderId
            let user = User(
                id: String(remoteMessage.senderId),
                name: isCurrentUser ? "You" : chat.partnerName,
                avatarURL: isCurrentUser ? nil : chat.avatarUrl ?? Links.defaultQMSAvatar,
                isCurrentUser: isCurrentUser
            )
            let imageAttachments = remoteMessage.attachments.compactMap { attachment -> ExyteChat.Attachment? in
                guard attachment.type == .image, let metadata = attachment.metadata else { return nil }
                let cacheKey = "qms-\(remoteMessage.id)-\(attachment.id)"
                let fullImageURL = metadata.fullUrl ?? fullImageURLs[attachment.id] ?? metadata.url
                return ExyteChat.Attachment(
                    id: cacheKey,
                    thumbnail: metadata.url,
                    full: fullImageURL,
                    type: ExyteChat.AttachmentType.image,
                    thumbnailCacheKey: "\(cacheKey)-thumbnail",
                    fullCacheKey: "\(cacheKey)-full-\(fullImageURL.absoluteString.hashValue)"
                )
            }
            
            return Message(
                id: String(remoteMessage.id),
                user: user,
                status: .none,
                createdAt: remoteMessage.date,
                text: remoteMessage.processedText,
                attachments: imageAttachments
            )
        }
        
        for index in localMessages.indices {
            guard localMessages[index].user.isCurrentUser else { continue }
            localMessages[index].status = .read
        }
        
        for index in localMessages.indices.suffix(chat.unreadCount) {
            guard localMessages[index].user.isCurrentUser else { continue }
            localMessages[index].status = .sent
        }
        
        return localMessages
    }
    }

private struct QMSImageExportFile: Equatable, Sendable {
    let data: Data
    let fileName: String
}

private enum QMSImageExportError: Error, Sendable {
    case noImages
    case invalidImage
    case photoLibraryAccessDenied
    case photoSaveFailed
    case invalidResponse
}

private func downloadQMSImages(from urls: [URL]) async throws -> [QMSImageExportFile] {
    let imageURLs = urls.filter { $0.scheme == "https" || $0.scheme == "http" }
    guard !imageURLs.isEmpty else { throw QMSImageExportError.noImages }

    var images: [QMSImageExportFile] = []
    for (index, url) in imageURLs.enumerated() {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw QMSImageExportError.invalidResponse
        }
        guard !data.isEmpty,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0,
              let imageTypeIdentifier = CGImageSourceGetType(imageSource) as String?
        else {
            throw QMSImageExportError.invalidImage
        }
        images.append(QMSImageExportFile(
            data: data,
            fileName: qmsImageFileName(
                for: url,
                index: index,
                mimeType: response.mimeType,
                imageTypeIdentifier: imageTypeIdentifier
            )
        ))
    }
    return images
}

private func qmsImageFileName(
    for url: URL,
    index: Int,
    mimeType: String?,
    imageTypeIdentifier: String
) -> String {
    let candidate = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
    let path = URL(fileURLWithPath: candidate)
    let candidateExtension = path.pathExtension.lowercased()
    let mimeTypeExtension: String? = switch mimeType?.lowercased() {
    case "image/jpeg", "image/jpg": "jpg"
    case "image/png": "png"
    case "image/gif": "gif"
    case "image/heic": "heic"
    case "image/webp": "webp"
    default: nil
    }
    let supportedExtensions = ["jpg", "jpeg", "png", "gif", "heic", "webp", "tif", "tiff", "bmp"]
    let detectedExtension = UTType(imageTypeIdentifier)?.preferredFilenameExtension?.lowercased()
    let fileExtension = [detectedExtension, mimeTypeExtension, candidateExtension]
        .compactMap { $0 }
        .first(where: supportedExtensions.contains) ?? "jpg"
    let rawName = path.deletingPathExtension().lastPathComponent
    let safeName = rawName
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: "\\", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let baseName = safeName.isEmpty ? "QMS-image" : safeName
    return "\(baseName)-\(index + 1).\(fileExtension)"
}

private func saveQMSImagesToPhotos(_ images: [QMSImageExportFile]) async throws {
    let authorizationStatus = await withCheckedContinuation { continuation in
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            continuation.resume(returning: status)
        }
    }
    guard authorizationStatus == .authorized else {
        throw QMSImageExportError.photoLibraryAccessDenied
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        PHPhotoLibrary.shared().performChanges {
            for image in images {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: image.data, options: nil)
            }
        } completionHandler: { success, error in
            if success {
                continuation.resume(returning: ())
            } else {
                continuation.resume(throwing: error ?? QMSImageExportError.photoSaveFailed)
            }
        }
    }
}

private func writeQMSImagesToTemporaryFiles(_ images: [QMSImageExportFile]) throws -> [URL] {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("qms-image-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    do {
        return try images.map { image in
            let url = directory.appendingPathComponent(image.fileName)
            try image.data.write(to: url, options: .atomic)
            return url
        }
    } catch {
        try? FileManager.default.removeItem(at: directory)
        throw error
    }
}

private func removeQMSImageExportFiles(_ urls: [URL]) {
    let directories = Set(urls.map(\.deletingLastPathComponent()))
    for directory in directories {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func qmsImageSaveFailedAlert(for error: any Error) -> AlertState<QMSFeature.Action.Alert> {
    let isPhotoLibraryAccessDenied: Bool
    if let exportError = error as? QMSImageExportError,
       case .photoLibraryAccessDenied = exportError {
        isPhotoLibraryAccessDenied = true
    } else {
        isPhotoLibraryAccessDenied = false
    }

    return AlertState {
        TextState("qms.image.save.failed.title", bundle: .module)
    } actions: {
        ButtonState(role: .cancel, action: .ok) {
            TextState("OK", bundle: .module)
        }
    } message: {
        isPhotoLibraryAccessDenied
            ? TextState("qms.image.save.photos.permission.message", bundle: .module)
            : TextState("qms.image.save.failed.message", bundle: .module)
    }
}

private func qmsImagesSavedToPhotosAlert() -> AlertState<QMSFeature.Action.Alert> {
    AlertState {
        TextState("qms.image.saved.photos.title", bundle: .module)
    } actions: {
        ButtonState(role: .cancel, action: .ok) {
            TextState("OK", bundle: .module)
        }
    } message: {
        TextState("qms.image.saved.photos.message", bundle: .module)
    }
}

private func qmsImagesSavedToFilesAlert() -> AlertState<QMSFeature.Action.Alert> {
    AlertState {
        TextState("qms.image.saved.files.title", bundle: .module)
    } actions: {
        ButtonState(role: .cancel, action: .ok) {
            TextState("OK", bundle: .module)
        }
    } message: {
        TextState("qms.image.saved.files.message", bundle: .module)
    }
}
