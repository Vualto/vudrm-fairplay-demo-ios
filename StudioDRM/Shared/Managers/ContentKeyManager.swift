
//
//  Created by Adam Gerber on 14/03/2022.
//  Copyright © 2022 JW Player. All Rights Reserved.
//

import AVFoundation

class ContentKeyManager {
    
    // MARK: Types.
    
    /// The singleton for `ContentKeyManager`.
    static let shared: ContentKeyManager = ContentKeyManager()
    
    // MARK: Properties.
    
    /**
     The instance of `AssetResourceLoaderDelegate` which conforms to `AVAssetResourceLoaderDelegate` and is used to respond to content key requests
     from `AVAssetResourceLoader`.
    */
    let assetResourceLoaderDelegate: AssetResourceLoaderDelegate

    /// The DispatchQueue to use for delegate callbacks.
    let assetResourceLoaderDelegateQueue = DispatchQueue(label: "com.vualto.studiodrm.demo.AssetResourceLoaderDelegateQueue")
    
    // MARK: Initialization.
    
    private init() {
        assetResourceLoaderDelegate = AssetResourceLoaderDelegate()
    }
    
    func updateResourceLoaderDelegate(forAsset asset: AVURLAsset) {
        asset.resourceLoader.setDelegate(assetResourceLoaderDelegate, queue: assetResourceLoaderDelegateQueue)
    }
}
