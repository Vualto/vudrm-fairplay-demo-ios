//
//  AssetResourceLoaderDelegate.swift
//
//  Created by Adam Gerber on 14/03/2022.
//  Copyright © 2022 JW Player. All Rights Reserved.
//

import AVFoundation
import StudioDRMKit

class AssetResourceLoaderDelegate: NSObject {
    
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
    
    /// The DispatchQueue to use for AVAssetResourceLoaderDelegate callbacks.
    fileprivate let resourceLoadingRequestQueue = DispatchQueue(label: "com.vualto.studiodrm.demo.resourcerequests")
    
    // MARK: API
    
    /// Preloads all the content keys associated with an Asset for persisting on disk.
    ///
    /// - Parameter asset: The `Asset` to preload keys for.
    func requestPersistableContentKeys(forAsset asset: Asset) {
        for identifier in asset.stream.contentKeyIDList ?? [] {
            
            guard let contentKeyIdentifierURL = URL(string: identifier), let _ = contentKeyIdentifierURL.host else { continue }
            contentID = contentKeyIdentifierURL.lastPathComponent
            pendingPersistableContentKeyIdentifiers.insert(contentID!)
            contentKeyToStreamNameMap[contentID!] = asset.stream.contentID
            
            asset.urlAsset.resourceLoader.preloadsEligibleContentKeys = true
        }
    }
    
    /// Returns whether or not a content key should be persistable on disk.
    ///
    /// - Parameter identifier: The asset ID associated with the content key request.
    /// - Returns: `true` if the content key request should be persistable, `false` otherwise.
    func shouldRequestPersistableContentKey(withIdentifier identifier: String) -> Bool {
        return pendingPersistableContentKeyIdentifiers.contains(identifier)
    }
    
    func shouldLoadOrRenewRequestedResource(resourceLoadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        
        guard let url = resourceLoadingRequest.request.url else {
            return false
        }
        
        // AssetLoaderDelegate only should handle FPS Content Key requests.
        if url.scheme != "skd" {
            return false
        }
        
        resourceLoadingRequestQueue.async { [weak self] in
            self?.prepareAndSendContentKeyRequest(resourceLoadingRequest: resourceLoadingRequest)
        }
        
        return true
    }
    
    func prepareAndSendContentKeyRequest(resourceLoadingRequest: AVAssetResourceLoadingRequest) {
        
        guard let contentKeyIdentifierURL = resourceLoadingRequest.request.url,
              let assetIDString = contentKeyIdentifierURL.host,
              let assetIDData = assetIDString.data(using: .utf8) else {
            print("Failed to get url or assetIDString for the request object of the resource.")
            return
        }
        
        contentID = contentKeyIdentifierURL.lastPathComponent
        
        var licenseServerURLString = contentKeyIdentifierURL.absoluteString
        licenseServerURLString = licenseServerURLString.replacingOccurrences(of: "skd", with: "https")
        self.licenseUrl = licenseServerURLString
        
        for stream in StreamListManager.shared.streams {
            if stream.contentID == contentID {
                self.studioDRMToken = stream.studioDRMToken!
            }
        }
        
        let provideOnlineKey: () -> Void = { [self] () in
            do {
                self.drm = StudioDRM()
                
                let applicationCertificate = try drm?.requestApplicationCertificate(token: self.studioDRMToken!, contentID: contentID!)
                
                let spcData = try resourceLoadingRequest.streamingContentKeyRequestData(forApp: applicationCertificate!,contentIdentifier: assetIDData, options: nil)
                
                // Send SPC to Key Server and obtain CKC.
                let ckcData = try self.drm!.requestContentKeyFromKeySecurityModule(spcData: spcData, token: studioDRMToken!, assetID: self.contentID!, licenseURL: licenseUrl!,renewal: renewInterval)
                
                if ckcData != nil {
                    resourceLoadingRequest.dataRequest?.respond(with: ckcData!)
                } else {
                    print("Failed to get CKC for the request object of the resource.")
                    
                    return
                }
                /*
                 You should always set the contentType before calling finishLoading() to make sure you
                 have a contentType that matches the key response.
                 */
                resourceLoadingRequest.contentInformationRequest?.contentType = AVStreamingKeyDeliveryContentKeyType
                resourceLoadingRequest.finishLoading()
                
            } catch {
                resourceLoadingRequest.finishLoading(with: error)
            }
        }
        
        #if os(iOS)
        /*
         Look up if this request should request a persistable content key or if there is an existing one to use on disk.
         */
        
        /*
         Make sure this key request supports persistent content keys before proceeding.
         
         Clients can respond with a persistent key if allowedContentTypes is nil or if allowedContentTypes
         contains AVStreamingKeyDeliveryPersistentContentKeyType. In all other cases, the client should
         respond with an online key.
         */
        if  let contentTypes = resourceLoadingRequest.contentInformationRequest?.allowedContentTypes,
            !contentTypes.contains(AVStreamingKeyDeliveryPersistentContentKeyType) {
            
            // Fallback to provide online FairPlay Streaming key from key server.
            provideOnlineKey()
            
            return
        }
        
        if shouldRequestPersistableContentKey(withIdentifier: contentID!) ||
            persistableContentKeyExistsOnDisk(withContentKeyIdentifier: contentID!) {
            prepareAndSendPersistableContentKeyRequest(resourceLoadingRequest: resourceLoadingRequest)
            
            return
        }
        #endif
        // Provide online FairPlay Streaming key from key server.
        provideOnlineKey()
    }
}

// MARK: - AVAssetResourceLoaderDelegate protocol methods extension
extension AssetResourceLoaderDelegate: AVAssetResourceLoaderDelegate {
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        return shouldLoadOrRenewRequestedResource(resourceLoadingRequest: loadingRequest)
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        
        return shouldLoadOrRenewRequestedResource(resourceLoadingRequest: renewalRequest)
    }
}
