
//
//  Created by Adam Gerber on 14/03/2022.
//  Copyright © 2022 JW Player. All Rights Reserved.
//

import UIKit
import AVFoundation
import AVKit

class AssetListTableViewController: UITableViewController {
    // MARK: Properties
    
    static let presentPlayerViewControllerSegueID = "PresentPlayerViewControllerSegueIdentifier"
    
    fileprivate var playerViewController: AVPlayerViewController?
    
    private var pendingContentKeyRequests = [String: Asset]()
    
    
    private var parsedContentKeyID: NSURL? = nil
    
    // MARK: Deinitialization
    
    deinit {
        NotificationCenter.default.removeObserver(self,
                                                  name: .AssetListManagerDidLoad,
                                                  object: nil)
    }
    
    // MARK: UIViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // General setup for auto sizing UITableViewCells.
        tableView.estimatedRowHeight = 75.0
        tableView.rowHeight = UITableView.automaticDimension
        
        // Set AssetListTableViewController as the delegate for AssetPlaybackManager to recieve playback information.
        AssetPlaybackManager.sharedManager.delegate = self
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAssetListManagerDidLoad(_:)),
                                               name: .AssetListManagerDidLoad, object: nil)
        
        #if os(iOS)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleContentKeyDelegateDidSaveAllPersistableContentKey(notification:)),
                                                   name: .DidSaveAllPersistableContentKey,
                                                   object: nil)
        #endif
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if playerViewController != nil {
            // The view reappeared as a results of dismissing an AVPlayerViewController.
            // Perform cleanup.
            AssetPlaybackManager.sharedManager.setAssetForPlayback(nil)
            playerViewController?.player = nil
            playerViewController = nil
        }
    }
    
    func getContentKeyIDList (videoUrl: NSURL, completion: @escaping() -> Void) {
        print("Parsing Content Key ID from manifest with \(videoUrl)")
        var request = URLRequest(url: videoUrl as URL)
        var gotURI = false
        request.httpMethod = "GET"
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let task = session.dataTask(with: request) { data, response, _ in
            guard let data = data else { return }
            let strData = String(data: data, encoding: .utf8)!
            if strData.contains("EXT-X-SESSION-KEY") || strData.contains("EXT-X-KEY") {
                let start = strData.range(of: "URI=\"")!.upperBound
                let end = strData[start...].range(of: "\"")!.lowerBound
                let keyUrlString = strData[start..<end]
                let keyUrl = URL(string: String(keyUrlString))
                print("Parsed Content Key ID from manifest: \(keyUrlString)")
                self.parsedContentKeyID = keyUrl as NSURL?
                gotURI = true
            } else {
                // This could be HLS content with variants
                if strData.contains("EXT-X-STREAM-INF") {
                    // Prepare the new variant video url last path components
                    let start = strData.range(of: "EXT-X-STREAM-INF")!.upperBound
                    let end = strData[start...].range(of: ".m3u8")!.upperBound
                    let strData2 = strData[start..<end]
                    let start2 = strData2.range(of: "\n")!.lowerBound
                    let end2 = strData2[start...].range(of: ".m3u8")!.upperBound
                    let unparsedVariantUrl = strData[start2..<end2]
                    let variantUrl = unparsedVariantUrl.replacingOccurrences(of: "\n", with: "")
                    // Prepare the new variant video url
                    let videoUrlString = videoUrl.absoluteString
                    let replaceString = String(videoUrl.lastPathComponent!)
                    if let unwrappedVideoUrlString = videoUrlString {
                        let newVideoUrlString = unwrappedVideoUrlString.replacingOccurrences(of: replaceString, with: variantUrl)
                        let pathURL = NSURL(string: newVideoUrlString)!
                        // Push the newly compiled variant video URL through this method
                        self.getContentKeyIDList(videoUrl: pathURL){
                        }
                    }
                } else {
                    // Nothing we understand, yet
                    print("Unable to parse URI from manifest. EXT-X-SESSION-KEY, EXT-X-KEY, or variant not found.")
                }
            }
            while !gotURI {
                // wait
            }
            completion()
        }
        task.resume()
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return AssetListManager.sharedManager.numberOfAssets()
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AssetListTableViewCell.reuseIdentifier, for: indexPath)
        
        let asset = AssetListManager.sharedManager.asset(at: indexPath.row)
        
        if let cell = cell as? AssetListTableViewCell {
            cell.asset = asset
            cell.delegate = self
        }
        
        return cell
    }
    
#if os(iOS)
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? AssetListTableViewCell, let asset = cell.asset else { return }
        
        let downloadState = AssetPersistenceManager.sharedManager.downloadState(for: asset)
        let alertAction: UIAlertAction
        
        switch downloadState {
        case .notDownloaded:
            alertAction = UIAlertAction(title: "Download", style: .default) { _ in
                if asset.stream.isProtected {
                    self.pendingContentKeyRequests[asset.stream.contentID] = asset
                    let url = NSURL(fileURLWithPath: asset.stream.playlistURL)
                    let cleanUrlString = url.absoluteString!.replacingOccurrences(of: " -- file:///", with: "")
                    let cleanUrlString2 = cleanUrlString.replacingOccurrences(of: "file:///", with: "")
                    guard let cleanUrl = NSURL(string:cleanUrlString2) else { return }
                    
                    // Note: Here we call the method getContentKeyIDList for the manifest to be parsed to retrieve the Content Key Identifier (skd:// URI). This is required for Offline assets and licenses to be persisted correctly.
                    
                    self.getContentKeyIDList(videoUrl: cleanUrl as NSURL){
                        asset.stream.contentKeyIDList?.append((self.parsedContentKeyID?.absoluteString)!)
                        ContentKeyManager.shared.assetResourceLoaderDelegate.requestPersistableContentKeys(forAsset: asset)
                    }
                } else {
                    AssetPersistenceManager.sharedManager.downloadStream(for: asset)
                }
            }
            
        case .downloading:
            alertAction = UIAlertAction(title: "Cancel", style: .default) { _ in
                AssetPersistenceManager.sharedManager.cancelDownload(for: asset)
            }
            
        case .downloaded:
            alertAction = UIAlertAction(title: "Delete", style: .default) { _ in
                AssetPersistenceManager.sharedManager.deleteAsset(asset)
                
                if asset.stream.isProtected {
                    ContentKeyManager.shared.assetResourceLoaderDelegate.deleteAllPeristableContentKeys(forAsset: asset)
                }
            }
        }
        
        let alertController = UIAlertController(title: asset.stream.contentID, message: "Select from the following options:", preferredStyle: .actionSheet)
        alertController.addAction(alertAction)
        alertController.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            guard let popoverController = alertController.popoverPresentationController else {
                return
            }
            
            popoverController.sourceView = cell
            popoverController.sourceRect = cell.bounds
        }
        
        present(alertController, animated: true, completion: nil)
    }
#endif
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        
        if segue.identifier == AssetListTableViewController.presentPlayerViewControllerSegueID {
            guard let cell = sender as? AssetListTableViewCell,
                let playerViewControler = segue.destination as? AVPlayerViewController,
                let asset = cell.asset else { return }
            
            // Grab a reference for the destinationViewController to use in later delegate callbacks from AssetPlaybackManager.
            playerViewController = playerViewControler
            
            #if os(iOS)
                if AssetPersistenceManager.sharedManager.downloadState(for: asset) == .downloaded {
                    if !asset.urlAsset.resourceLoader.preloadsEligibleContentKeys {
                        asset.urlAsset.resourceLoader.preloadsEligibleContentKeys = true
                    }
                }
            #endif
            
            // Load the new Asset to playback into AssetPlaybackManager.
            AssetPlaybackManager.sharedManager.setAssetForPlayback(asset)
        }
    }
    
    // MARK: Notification handling
    
    @objc
    func handleAssetListManagerDidLoad(_: Notification) {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
#if os(iOS)
    @objc
    func handleContentKeyDelegateDidSaveAllPersistableContentKey(notification: Notification) {
        guard let assetName = notification.userInfo?["name"] as? String,
            let asset = self.pendingContentKeyRequests.removeValue(forKey: assetName) else {
            return
        }
        
        AssetPersistenceManager.sharedManager.downloadStream(for: asset)
    }
#endif
}

/**
 Extend `AssetListTableViewController` to conform to the `AssetListTableViewCellDelegate` protocol.
 */
extension AssetListTableViewController: AssetListTableViewCellDelegate {
    
    func assetListTableViewCell(_ cell: AssetListTableViewCell, downloadStateDidChange newState: Asset.DownloadState) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
}

/**
 Extend `AssetListTableViewController` to conform to the `AssetPlaybackDelegate` protocol.
 */
extension AssetListTableViewController: AssetPlaybackDelegate {
    func streamPlaybackManager(_ streamPlaybackManager: AssetPlaybackManager, playerReadyToPlay player: AVPlayer) {
        player.play()
    }
    
    func streamPlaybackManager(_ streamPlaybackManager: AssetPlaybackManager, playerCurrentItemDidChange player: AVPlayer) {
        guard let playerViewController = playerViewController, player.currentItem != nil else { return }
        
        playerViewController.player = player
    }
}
