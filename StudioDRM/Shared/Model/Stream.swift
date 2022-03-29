
//
//  Created by Adam Gerber on 14/03/2022.
//  Copyright © 2022 JW Player. All Rights Reserved.
//

import Foundation

class Stream: Codable {
    
    // MARK: Types
    
    enum CodingKeys: String, CodingKey {
        case name = "name"
        case contentID = "content_id"
        case playlistURL = "playlist_url"
        case isProtected = "is_protected"
        case contentKeyIDList = "content_key_id_list"
        case studioDRMToken = "studio_drm_token"
        case renewInterval = "renew_interval"
    }
    
    // MARK: Properties
    
    /// The name of the stream.
    let name: String
    
    /// The contentID of the stream.
    let contentID: String
    
    /// The URL pointing to the HLS stream.
    let playlistURL: String
    
    /// A Boolen value representing if the stream uses FPS.
    let isProtected: Bool
    
    /// An array of content IDs to use for loading content keys with FPS.
    var contentKeyIDList: [String]?
    
    /// The StudioDRM token of the stream.
    let studioDRMToken: String?
    
    /// The renew interval of the stream.
    let renewInterval: Int?
}

extension Stream: Equatable {
    static func ==(lhs: Stream, rhs: Stream) -> Bool {
        
        var isEqual = (lhs.name == rhs.name) && (lhs.contentID == rhs.contentID) && (lhs.playlistURL == rhs.playlistURL) && (lhs.isProtected == rhs.isProtected) && (lhs.studioDRMToken == rhs.studioDRMToken) && (lhs.renewInterval == rhs.renewInterval)
        let lhsContentKeyIDList = lhs.contentKeyIDList ?? []
        let rhsContentKeyIDList = rhs.contentKeyIDList ?? []
        
        isEqual = isEqual && lhsContentKeyIDList.elementsEqual(rhsContentKeyIDList)
        
        return isEqual
    }
}
