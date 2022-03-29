//
//  Created by Adam Gerber on 14/03/2022.
//  Copyright © 2022 JW Player. All Rights Reserved.
//
/*
 Abstract:
 The `ContentKeyManager` class configures the instance of `AssetResourceLoaderDelegate` to use for requesting
 content keys securely for playback or offline use.
 */

import AVFoundation

class ContentKeyManager {
    
    // MARK: Types.
    
    /// The singleton for `ContentKeyManager`.
    static let shared: ContentKeyManager = ContentKeyManager()
    
    // MARK: Properties.
    
    /// The instance of `AVContentKeySession` that is used for managing and preloading content keys.
    let contentKeySession: AVContentKeySession
    
    /**
     The instance of `ContentKeyDelegate` which conforms to `AVContentKeySessionDelegate` and is used to respond to content key requests from
     the `AVContentKeySession`
     */
    let contentKeyDelegate: ContentKeyDelegate
    
    /// The DispatchQueue to use for delegate callbacks.
    let contentKeyDelegateQueue = DispatchQueue(label: "com.example.apple-samplecode.HLSCatalog.ContentKeyDelegateQueue")
    
    // MARK: Initialization.
    
    private init() {
        contentKeySession = AVContentKeySession(keySystem: .fairPlayStreaming)
        contentKeyDelegate = ContentKeyDelegate()
        contentKeySession.setDelegate(contentKeyDelegate, queue: contentKeyDelegateQueue)
    }
}
