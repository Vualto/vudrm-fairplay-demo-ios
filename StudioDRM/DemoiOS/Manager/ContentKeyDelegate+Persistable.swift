//
//  ContentKeyDelegate+Persistable.swift
//  Demo
//
//  Created by Adam Gerber on 14/03/2022.
//  Copyright © 2022 JW Player. All Rights Reserved.
//

import AVFoundation
import StudioDRMKit

extension ContentKeyDelegate {
    
    /*
     Provides the receiver with a new content key request that allows key persistence.
     Will be invoked by an AVContentKeyRequest as the result of a call to
     -respondByRequestingPersistableContentKeyRequest.
     */
    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVPersistableContentKeyRequest) {
        handlePersistableContentKeyRequest(keyRequest: keyRequest)
    }
    
    /*
     Provides the receiver with an updated persistable content key for a particular key request.
     If the content key session provides an updated persistable content key data, the previous
     key data is no longer valid and cannot be used to answer future loading requests.
     
     This scenario can occur when using the FPS "dual expiry" feature which allows you to define
     and customize two expiry windows for FPS persistent keys. The first window is the storage
     expiry window which starts as soon as the persistent key is created. The other window is a
     playback expiry window which starts when the persistent key is used to start the playback
     of the media content.
     
     Here's an example:
     
     When the user rents a movie to play offline you would create a persistent key with a CKC that
     opts in to use this feature. This persistent key is said to expire at the end of storage expiry
     window which is 30 days in this example. You would store this persistent key in your apps storage
     and use it to answer a key request later on. When the user comes back within these 30 days and
     asks you to start playback of the content, you will get a key request and would use this persistent
     key to answer the key request. At that point, you will get sent an updated persistent key which
     is set to expire at the end of playback experiment which is 24 hours in this example.
     */
    func contentKeySession(_ session: AVContentKeySession,
                           didUpdatePersistableContentKey persistableContentKey: Data,
                           forContentKeyIdentifier keyIdentifier: Any) {
        /*
         The key ID is the URI from the EXT-X-KEY tag in the playlist (e.g. "skd://key65") and the
         contentID in this case is "key65".
         */
        guard let contentKeyIdentifierString = keyIdentifier as? String,
              let contentKeyIdentifierURL = URL(string: contentKeyIdentifierString),
              let _ = contentKeyIdentifierURL.host
        else {
            print("Failed to retrieve the assetID from the keyRequest!")
            return
        }
        
        do {
            deletePeristableContentKey(withContentKeyIdentifier: self.contentID!)
            
            try writePersistableContentKey(contentKey: persistableContentKey, withContentKeyIdentifier: self.contentID!)
        } catch {
            print("Failed to write updated persistable content key to disk: \(error.localizedDescription)")
        }
    }
    
    // MARK: API.
    
    /// Handles responding to an `AVPersistableContentKeyRequest` by determining if a key is already available for use on disk.
    /// If no key is available on disk, a persistable key is requested from the server and securely written to disk for use in the future.
    /// In both cases, the resulting content key is used as a response for the `AVPersistableContentKeyRequest`.
    ///
    /// - Parameter keyRequest: The `AVPersistableContentKeyRequest` to respond to.
    func handlePersistableContentKeyRequest(keyRequest: AVPersistableContentKeyRequest) {
        
        /*
         The key ID is the URI from the EXT-X-KEY tag in the playlist (e.g. "skd://key65") and the
         asset ID in this case is "key65".
         */
        guard let contentKeyIdentifierString = keyRequest.identifier as? String,
              let contentKeyIdentifierURL = URL(string: contentKeyIdentifierString),
              let assetIDString = contentKeyIdentifierURL.host,
              let assetIDData = assetIDString.data(using: .utf8)
        else {
            print("Failed to retrieve the assetID from the keyRequest!")
            return
        }
        
        
        var licenseServerURLString = contentKeyIdentifierURL.absoluteString
        licenseServerURLString = licenseServerURLString.replacingOccurrences(of: "skd", with: "https")
        self.licenseUrl = licenseServerURLString
        
        do {
            
            let completionHandler = { [weak self] (spcData: Data?, error: Error?) in
                guard let strongSelf = self else { return }
                if let error = error {
                    keyRequest.processContentKeyResponseError(error)
                    self!.contentID = contentKeyIdentifierURL.lastPathComponent
                    
                    strongSelf.pendingPersistableContentKeyIdentifiers.remove(self!.contentID!)
                    return
                }
                
                guard let spcData = spcData else { return }
                
                do {
                    // Send SPC to Key Server and obtain CKC
                    
                    self!.drm = StudioDRM()
                    let ckcData = try self!.drm!.requestContentKeyFromKeySecurityModule(spcData: spcData, token: self!.studioDRMToken!, assetID: self!.contentID!, licenseURL: self!.licenseUrl!, renewal: self!.renewInterval)
                    let persistentKey = try keyRequest.persistableContentKey(fromKeyVendorResponse: ckcData!, options: nil)
                    
                    try strongSelf.writePersistableContentKey(contentKey: persistentKey, withContentKeyIdentifier: self!.contentID!)
                    
                    /*
                     AVContentKeyResponse is used to represent the data returned from the key server when requesting a key for
                     decrypting content.
                     */
                    let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: persistentKey)
                    
                    /*
                     Provide the content key response to make protected content available for processing.
                     */
                    keyRequest.processContentKeyResponse(keyResponse)
                    
                    let assetName = strongSelf.contentKeyToStreamNameMap.removeValue(forKey: self!.contentID!)
                    
                    if !strongSelf.contentKeyToStreamNameMap.values.contains(assetName!) {
                        NotificationCenter.default.post(name: .DidSaveAllPersistableContentKey,
                                                        object: nil,
                                                        userInfo: ["name": assetName!])
                    }
                    
                    strongSelf.pendingPersistableContentKeyIdentifiers.remove(self!.contentID!)
                } catch {
                    keyRequest.processContentKeyResponseError(error)
                    
                    strongSelf.pendingPersistableContentKeyIdentifiers.remove(self!.contentID!)
                }
            }
            
            // Check to see if we can satisfy this key request using a saved persistent key file.
            if persistableContentKeyExistsOnDisk(withContentKeyIdentifier: self.contentID!) {
                
                let urlToPersistableKey = urlForPersistableContentKey(withContentKeyIdentifier: self.contentID!)
                
                guard let contentKey = FileManager.default.contents(atPath: urlToPersistableKey.path) else {
                    // Error Handling.
                    
                    pendingPersistableContentKeyIdentifiers.remove(self.contentID!)
                    
                    /*
                     Key requests should never be left dangling.
                     Attempt to create a new persistable key.
                     */
                    
                    let applicationCertificate = try drm!.requestApplicationCertificate(token: self.studioDRMToken!, contentID: contentID!)
                    
                    keyRequest.makeStreamingContentKeyRequestData(forApp: applicationCertificate!,
                                                                  contentIdentifier: assetIDData,
                                                                  options: [AVContentKeyRequestProtocolVersionsKey: [1]],
                                                                  completionHandler: completionHandler)
                    
                    return
                }
                
                /*
                 Create an AVContentKeyResponse from the persistent key data to use for requesting a key for
                 decrypting content.
                 */
                let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: contentKey)
                
                // Provide the content key response to make protected content available for processing.
                keyRequest.processContentKeyResponse(keyResponse)
                
                return
            }
            
            self.drm = StudioDRM()
            let applicationCertificate = try drm!.requestApplicationCertificate(token: self.studioDRMToken!, contentID: contentID!)
            
            keyRequest.makeStreamingContentKeyRequestData(forApp: applicationCertificate!,
                                                          contentIdentifier: assetIDData,
                                                          options: [AVContentKeyRequestProtocolVersionsKey: [1]],
                                                          completionHandler: completionHandler)
        } catch {
            print("Failure responding to an AVPersistableContentKeyRequest when attemping to determine if key is already available for use on disk.")
        }
    }
    
    /// Deletes all the persistable content keys on disk for a specific `Asset`.
    ///
    /// - Parameter asset: The `Asset` value to remove keys for.
    func deleteAllPeristableContentKeys(forAsset asset: Asset) {
        for contentKeyIdentifier in asset.stream.contentKeyIDList ?? [] {
            deletePeristableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        }
    }
    
    /// Deletes a persistable key for a given content key identifier.
    ///
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    func deletePeristableContentKey(withContentKeyIdentifier contentKeyIdentifier: String) {
        
        guard persistableContentKeyExistsOnDisk(withContentKeyIdentifier: contentKeyIdentifier) else { return }
        
        let contentKeyURL = urlForPersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        
        do {
            try FileManager.default.removeItem(at: contentKeyURL)
            
            UserDefaults.standard.removeObject(forKey: "\(contentKeyIdentifier)-Key")
        } catch {
            print("An error occured removing the persisted content key: \(error)")
        }
    }
    
    /// Returns whether or not a persistable content key exists on disk for a given content key identifier.
    ///
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    /// - Returns: `true` if the key exists on disk, `false` otherwise.
    func persistableContentKeyExistsOnDisk(withContentKeyIdentifier contentKeyIdentifier: String) -> Bool {
        let contentKeyURL = urlForPersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        
        return FileManager.default.fileExists(atPath: contentKeyURL.path)
    }
    
    // MARK: Private APIs
    
    /// Returns the `URL` for persisting or retrieving a persistable content key.
    ///
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    /// - Returns: The fully resolved file URL.
    func urlForPersistableContentKey(withContentKeyIdentifier contentKeyIdentifier: String) -> URL {
        return contentKeyDirectory.appendingPathComponent("\(contentKeyIdentifier)-Key")
    }
    
    /// Writes out a persistable content key to disk.
    ///
    /// - Parameters:
    ///   - contentKey: The data representation of the persistable content key.
    ///   - contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    /// - Throws: If an error occurs during the file write process.
    func writePersistableContentKey(contentKey: Data, withContentKeyIdentifier contentKeyIdentifier: String) throws {
        
        let fileURL = urlForPersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        
        print("Writing persistable key for \(contentKeyIdentifier)")
        try contentKey.write(to: fileURL, options: Data.WritingOptions.atomicWrite)
    }
    
}

extension Notification.Name {
    
    /**
     The notification that is posted when all the content keys for a given asset have been saved to disk.
     */
    static let DidSaveAllPersistableContentKey = Notification.Name("ContentKeyDelegateDidSaveAllPersistableContentKey")
}
