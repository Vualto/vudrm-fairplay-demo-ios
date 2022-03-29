//
//  ContentKeyDelegate.swift
//
//  Created by Adam Gerber on 14/03/2022.
//  Copyright © 2022 JW Player. All Rights Reserved.
//

import AVFoundation
import StudioDRMKit

class ContentKeyDelegate: NSObject, AVContentKeySessionDelegate {
    
    // MARK: Properties
    
    /// The directory that is used to save persistable content keys.
    lazy var contentKeyDirectory: URL = {
        guard let documentPath =
                NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            fatalError("Unable to determine library URL")
        }
        
        let documentURL = URL(fileURLWithPath: documentPath)
        
        let contentKeyDirectory = documentURL.appendingPathComponent(".keys", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: contentKeyDirectory.path, isDirectory: nil) {
            do {
                try FileManager.default.createDirectory(at: contentKeyDirectory,
                                                        withIntermediateDirectories: false,
                                                        attributes: nil)
            } catch {
                fatalError("Unable to create directory for content keys at path: \(contentKeyDirectory.path)")
            }
        }
        
        return contentKeyDirectory
    }()
    
    /// A set containing the currently pending content key identifiers associated with persistable content key requests that have not been completed.
    var pendingPersistableContentKeyIdentifiers = Set<String>()
    
    /// A dictionary mapping content key identifiers to their associated stream name.
    var contentKeyToStreamNameMap = [String: String]()
    
    var licenseUrl: String?
    var studioDRMToken: String?
    var contentID: String?
    var renewInterval = 0
    var drm: StudioDRM?
    
    /// The DispatchQueue to use for ContentKeyDelegate callbacks.
    fileprivate lazy var urlSessionConf: URLSessionConfiguration  = {
        
        let ephimeralSession = URLSessionConfiguration.ephemeral
        ephimeralSession.allowsCellularAccess = true
        let interval =  TimeInterval(30)
        ephimeralSession.timeoutIntervalForRequest = interval
        ephimeralSession.httpCookieAcceptPolicy = HTTPCookie.AcceptPolicy.never
        
        return ephimeralSession
    }()
    
    /// Preloads all the content keys associated with an Asset for persisting on disk.
    ///
    /// It is recommended you use AVContentKeySession to initiate the key loading process
    /// for online keys too. Key loading time can be a significant portion of your playback
    /// startup time because applications normally load keys when they receive an on-demand
    /// key request. You can improve the playback startup experience for your users if you
    /// load keys even before the user has picked something to play. AVContentKeySession allows
    /// you to initiate a key loading process and then use the key request you get to load the
    /// keys independent of the playback session. This is called key preloading. After loading
    /// the keys you can request playback, so during playback you don't have to load any keys,
    /// and the playback decryption can start immediately.
    ///
    /// In this sample use the Streams.plist to specify your own content key identifiers to use
    /// for loading content keys for your media. See the README document for more information.
    ///
    /// - Parameter asset: The `Asset` to preload keys for.
    func requestPersistableContentKeys(forAsset asset: Asset) {
        for identifier in asset.stream.contentKeyIDList ?? [] {
            
            guard let contentKeyIdentifierURL = URL(string: identifier), let _ = contentKeyIdentifierURL.host else { continue }
            contentID = contentKeyIdentifierURL.lastPathComponent
            pendingPersistableContentKeyIdentifiers.insert(contentID!)
            contentKeyToStreamNameMap[contentID!] = asset.stream.contentID
            
            ContentKeyManager.shared.contentKeySession.processContentKeyRequest(withIdentifier: identifier, initializationData: nil, options: nil)
        }
    }
    
    /// Returns whether or not a content key should be persistable on disk.
    ///
    /// - Parameter identifier: The asset ID associated with the content key request.
    /// - Returns: `true` if the content key request should be persistable, `false` otherwise.
    func shouldRequestPersistableContentKey(withIdentifier identifier: String) -> Bool {
        return pendingPersistableContentKeyIdentifiers.contains(identifier)
    }
    
    // MARK: AVContentKeySessionDelegate Methods
    
    /*
     The following delegate callback gets called when the client initiates a key request or AVFoundation
     determines that the content is encrypted based on the playlist the client provided when it requests playback.
     */
    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        
        // reset renewInterval
        self.renewInterval = 0
        
        // check and set renewInterval if it exists for this stream / request
        
        // ***NOTE*** Use of renewInterval can be detrimental to your DRM service and may incur unexpected overheads, therefore using this feature should only commence after consultation with Vualto.
        
        for stream in StreamListManager.shared.streams {
            let url = NSURL(string: keyRequest.identifier as! String)
            if stream.contentID == url?.lastPathComponent {
                if stream.renewInterval != nil{
                    self.renewInterval = stream.renewInterval!
                }
            }
        }
        handleStreamingContentKeyRequest(keyRequest: keyRequest)
    }
    
    /*
     Provides the receiver with a new content key request representing a renewal of an existing content key.
     Will be invoked by an AVContentKeySession as the result of a call to -renewExpiringResponseDataForContentKeyRequest:.
     */
    func contentKeySession(_ session: AVContentKeySession, didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        
        handleStreamingContentKeyRequest(keyRequest: keyRequest)
    }
    
    /*
     Provides the receiver a content key request that should be retried because a previous content key request failed.
     Will be invoked by an AVContentKeySession when a content key request should be retried. The reason for failure of
     previous content key request is specified. The receiver can decide if it wants to request AVContentKeySession to
     retry this key request based on the reason. If the receiver returns YES, AVContentKeySession would restart the
     key request process. If the receiver returns NO or if it does not implement this delegate method, the content key
     request would fail and AVContentKeySession would let the receiver know through
     -contentKeySession:contentKeyRequest:didFailWithError:.
     */
    func contentKeySession(_ session: AVContentKeySession, shouldRetry keyRequest: AVContentKeyRequest,
                           reason retryReason: AVContentKeyRequest.RetryReason) -> Bool {
        
        var shouldRetry = false
        
        switch retryReason {
        /*
         Indicates that the content key request should be retried because the key response was not set soon enough either
         due the initial request/response was taking too long, or a lease was expiring in the meantime.
         */
        case AVContentKeyRequest.RetryReason.timedOut:
            shouldRetry = true
            
        /*
         Indicates that the content key request should be retried because a key response with expired lease was set on the
         previous content key request.
         */
        case AVContentKeyRequest.RetryReason.receivedResponseWithExpiredLease:
            shouldRetry = true
            print("expired lease")
        /*
         Indicates that the content key request should be retried because an obsolete key response was set on the previous
         content key request.
         */
        case AVContentKeyRequest.RetryReason.receivedObsoleteContentKey:
            shouldRetry = true
            
        default:
            break
        }
        
        return shouldRetry
    }
    
    // Informs the receiver a content key request has failed.
    func contentKeySession(_ session: AVContentKeySession, contentKeyRequest keyRequest: AVContentKeyRequest, didFailWithError err: Error) {
        // Add your code here to handle errors.
        print("contentKeySession didFailWithError \(err)")
    }

    func handleStreamingContentKeyRequest(keyRequest: AVContentKeyRequest) {

        guard let contentKeyIdentifierString = keyRequest.identifier as? String,
              let contentKeyIdentifierURL = URL(string: contentKeyIdentifierString),
              let assetIDString = contentKeyIdentifierURL.host,
              let assetIDData = assetIDString.data(using: .utf8)

        else {
            print("Failed to retrieve the assetID from the keyRequest!")
            return
        }

        contentID = contentKeyIdentifierURL.lastPathComponent

        var licenseServerURLString = contentKeyIdentifierURL.absoluteString
        licenseServerURLString = licenseServerURLString.replacingOccurrences(of: "skd", with: "https")
        self.licenseUrl = licenseServerURLString

        for stream in StreamListManager.shared.streams {
            if stream.contentID == contentID {
                self.studioDRMToken = stream.studioDRMToken!
                self.renewInterval = stream.renewInterval ?? 0
            }
        }

        let provideOnlinekey: () -> Void = { [self] () -> Void in

            do {
                self.drm = StudioDRM()
                let applicationCertificate = try drm!.requestApplicationCertificate(token: self.studioDRMToken!, contentID: contentID!)

                let completionHandler = { [weak self] (spcData: Data?, error: Error?) in
                    guard let strongSelf = self else { return }
                    if let error = error {
                        keyRequest.processContentKeyResponseError(error)
                        return
                    }

                    guard let spcData = spcData else { return }

                    do {
                        // Send SPC to Key Server and obtain CKC

                        let ckcData = try strongSelf.drm!.requestContentKeyFromKeySecurityModule(spcData: spcData, token: studioDRMToken!, assetID: contentID!, licenseURL: licenseUrl!,renewal: renewInterval)
                        /*
                         AVContentKeyResponse is used to represent the data returned from the key server when requesting a key for
                         decrypting content.
                         */

                        let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckcData!)

                        /*
                         Provide the content key response to make protected content available for processing.
                         */
                        keyRequest.processContentKeyResponse(keyResponse)

                    } catch {
                        keyRequest.processContentKeyResponseError(error)
                    }
                }

                keyRequest.makeStreamingContentKeyRequestData(forApp: applicationCertificate!,
                                                              contentIdentifier: assetIDData,
                                                              options: [AVContentKeyRequestProtocolVersionsKey: [1]],
                                                              completionHandler: completionHandler)

    // ***NOTE*** Use of renewInterval can be detrimental to your DRM service and may incur unexpected overheads, therefore using this feature should only commence after consultation with Vualto.
                
                if self.renewInterval > 0 {
                    let msg = "Setting renewal timer to \(self.renewInterval)"
                    print(msg)
                    DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(self.renewInterval)) {
                        let msg = "Renewal timer fired!"
                        print(msg)
                        ContentKeyManager.shared.contentKeySession.renewExpiringResponseData(for: keyRequest)
                    }
                }

            } catch {
                keyRequest.processContentKeyResponseError(error)
            }
        }

        #if os(iOS)
        /*
         When you receive an AVContentKeyRequest via -contentKeySession:didProvideContentKeyRequest:
         and you want the resulting key response to produce a key that can persist across multiple
         playback sessions, you must invoke -respondByRequestingPersistableContentKeyRequest on that
         AVContentKeyRequest in order to signal that you want to process an AVPersistableContentKeyRequest
         instead. If the underlying protocol supports persistable content keys, in response your
         delegate will receive an AVPersistableContentKeyRequest via -contentKeySession:didProvidePersistableContentKeyRequest:.
         */
        if shouldRequestPersistableContentKey(withIdentifier: contentID!) ||
            persistableContentKeyExistsOnDisk(withContentKeyIdentifier: contentID!) {

            print("handleStreamingContentKeyRequest: Request a Persistable Key Request")
            // Request a Persistable Key Request.
            do {
                try keyRequest.respondByRequestingPersistableContentKeyRequestAndReturnError()
            } catch {

                /*
                 This case will occur when the client gets a key loading request from an AirPlay Session.
                 You should answer the key request using an online key from your key server.
                 */
                provideOnlinekey()
            }

            return
        }
        #endif

        provideOnlinekey()
    }
}
