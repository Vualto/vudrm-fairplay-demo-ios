//
//  AssetResourceLoaderDelegate+Persistable.swift
//
//  Created by Adam Gerber on 14/03/2022.
//  Copyright © 2022 JW Player. All Rights Reserved.
//

import AVFoundation
import StudioDRMKit

extension AssetResourceLoaderDelegate {
    
    func prepareAndSendPersistableContentKeyRequest(resourceLoadingRequest: AVAssetResourceLoadingRequest) {
        
        guard let contentKeyIdentifierURL = resourceLoadingRequest.request.url,
            let assetIDString = contentKeyIdentifierURL.host,
            let assetIDData = assetIDString.data(using: .utf8) else {
                print("Failed to get url or assetIDString for the request object of the resource.")
                return
        }
        
       var licenseServerURLString = contentKeyIdentifierURL.absoluteString
        licenseServerURLString = licenseServerURLString.replacingOccurrences(of: "skd", with: "https")
        self.licenseUrl = licenseServerURLString
        
        resourceLoadingRequest.contentInformationRequest?.contentType = AVStreamingKeyDeliveryPersistentContentKeyType
        
        do {
            
            // Check to see if we can satisfy this key request using a saved persistent key file.
            if persistableContentKeyExistsOnDisk(withContentKeyIdentifier: self.contentID!) {
                let urlToPersistableKey = urlForPersistableContentKey(withContentKeyIdentifier: self.contentID!)
                
                guard let contentKey = FileManager.default.contents(atPath: urlToPersistableKey.path) else {
                    // Error Handling.
                    contentID = contentKeyIdentifierURL.lastPathComponent
                    pendingPersistableContentKeyIdentifiers.remove(self.contentID!)
                    return
                }
                
                // Provide the content key response to make protected content available for processing.
                resourceLoadingRequest.dataRequest?.respond(with: contentKey)
                resourceLoadingRequest.finishLoading()
                
                return
            }
            
            self.drm = StudioDRM()
            let applicationCertificate = try drm!.requestApplicationCertificate(token: self.studioDRMToken!, contentID: contentID!)
            
            let spcData =
                try resourceLoadingRequest.streamingContentKeyRequestData(forApp: applicationCertificate!, contentIdentifier: assetIDData,
                        options: [AVAssetResourceLoadingRequestStreamingContentKeyRequestRequiresPersistentKey: true])
            
            // Send SPC to Key Server and obtain CKC
            let ckcData = try self.drm!.requestContentKeyFromKeySecurityModule(spcData: spcData, token: self.studioDRMToken!, assetID: self.contentID!, licenseURL: self.licenseUrl!, renewal: renewInterval)
            
            let persistentKey = try resourceLoadingRequest.persistentContentKey(fromKeyVendorResponse: ckcData!, options: nil)
            
            // Write the persistent content key to disk.
            try writePersistableContentKey(contentKey: persistentKey, withContentKeyIdentifier: contentID!)
            
            // Provide the content key response to make protected content available for processing.
            resourceLoadingRequest.dataRequest?.respond(with: persistentKey)
            resourceLoadingRequest.finishLoading()

            let assetName = contentKeyToStreamNameMap.removeValue(forKey: contentID!)
            
            if !contentKeyToStreamNameMap.values.contains(assetName!) {
                NotificationCenter.default.post(name: .DidSaveAllPersistableContentKey,
                                                object: nil,
                                                userInfo: ["name": assetName!])
            }
            
            pendingPersistableContentKeyIdentifiers.remove(contentID!)
            
        } catch {
            resourceLoadingRequest.finishLoading(with: error)
            
            pendingPersistableContentKeyIdentifiers.remove(contentID!)
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
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`.
    
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
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`.
    ///
    /// - Returns: `true` if the key exists on disk, `false` otherwise.
    func persistableContentKeyExistsOnDisk(withContentKeyIdentifier contentKeyIdentifier: String) -> Bool {
        let contentKeyURL = urlForPersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        
        return FileManager.default.fileExists(atPath: contentKeyURL.path)
    }
    
    // MARK: Private APIs
    
    /// Returns the `URL` for persisting or retrieving a persistable content key.
    ///
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`.
    ///
    /// - Returns: The fully resolved file URL.
    func urlForPersistableContentKey(withContentKeyIdentifier contentKeyIdentifier: String) -> URL {
        return contentKeyDirectory.appendingPathComponent("\(contentKeyIdentifier)-Key")
    }
    
    /// Writes out a persistable content key to disk.
    ///
    /// - Parameters:
    ///   - contentKey: The data representation of the persistable content key.
    ///   - contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`.
    ///
    /// - Throws: If an error occurs during the file write process.
    func writePersistableContentKey(contentKey: Data, withContentKeyIdentifier contentKeyIdentifier: String) throws {
        
        let fileURL = urlForPersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        
        try contentKey.write(to: fileURL, options: Data.WritingOptions.atomicWrite)
    }

}

extension Notification.Name {
    
    /**
     The notification that is posted when all the content keys for a given asset have been saved to disk.
     */
    static let DidSaveAllPersistableContentKey =
        Notification.Name("AssetResourceLoaderDelegateDidSaveAllPersistableContentKey")
}

