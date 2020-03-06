//
//  ViewController.swift
//  vudrmFairPlay
//
//  Created by Adam Gerber on 20/09/2017.
//  Copyright © 2017 Vualto Ltd. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit
import vudrmFairPlay

class ViewController: UIViewController {
    
    // MARK: - Properties
    weak var player: AVPlayer?
    var drm: vudrmFairPlay?
    var assetDownloadTask: AVAssetDownloadTask!
    var backgroundConfiguration: URLSessionConfiguration?
    var assetUrlSession: AVAssetDownloadURLSession!
    var contentKeyIDList: [String]?
    var assetExists: Bool?
    
    @IBOutlet weak var networkStatus: UIButton!
    @IBOutlet weak var downloadButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var deleteButton: UIButton!
    
    @IBOutlet weak var methodButton1: UIButton!
    @IBOutlet weak var methodButton2: UIButton!
    
    private var assetURL = URL(string: "")
    private var token = ""
    private var contentID = ""
    
    private var assetFileURL: URL?
    
    @IBOutlet weak var streamURLField: UITextField!
    @IBOutlet weak var streamTokenField: UITextField!
    @IBOutlet weak var contentIDField: UITextField!
    
    @IBOutlet weak var downloadProgress: UIProgressView!
    
    // MARK: - Structs
    private struct KVOContext {
        static var player = 1487062800
        static var item = 1487066400
    }
    
    private struct Constant {
        struct KeyPath {
            struct Player {
                static let rate = "rate"
            }
        }
    }
    
    // MARK: - deinit & dismiss
    deinit {
        removeNotificationObservers()
        removeKVOObservers()
    }
    
    override func dismiss(animated flag: Bool,
                          completion: (() -> Void)?)
    {
        super.dismiss(animated: flag, completion:completion)
        removeNotificationObservers()
        if ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 11, minorVersion: 0, patchVersion: 0)) {
        } else {
            removeKVOObservers()
        }
    }
    
    // MARK: - UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()
        do {
            if #available(iOS 10.0, *) {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            } else {
                // Fallback on earlier versions
            }
        }
        catch {
            print("Setting category to AVAudioSessionCategoryPlayback failed.")
        }

        let timer = Timer.scheduledTimer(timeInterval: 1, target: self,   selector: (#selector(self.updateUserInterface)), userInfo: nil, repeats: true)
        timer.fire()
        NotificationCenter.default.addObserver(self, selector: #selector(statusManager), name: .flagsChanged, object: Network.reachability)
        updateUserInterface()
        backgroundConfiguration = URLSessionConfiguration.background(withIdentifier: "assetDownloadConfigurationIdentifier")
        assetUrlSession = AVAssetDownloadURLSession(configuration: backgroundConfiguration!, assetDownloadDelegate: self, delegateQueue: .main)
        downloadProgress.progress = 0.0
        addNotificationObservers()
        let tap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(ViewController.dismissKeyboard))
        
        //Uncomment the line below if you want the tap not not interfere and cancel other interactions.
        //tap.cancelsTouchesInView = false
        
        view.addGestureRecognizer(tap)
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.portrait
    }
    
    @IBAction func URLChanged(_ sender: Any) {
        let entry = streamURLField.text
        var stringToReplace = entry
        if let range = stringToReplace?.range(of: "\n") {
            stringToReplace?.replaceSubrange(range, with: "")
        }
        if (stringToReplace?.contains(" "))!{
            let myStringArr = stringToReplace?.components(separatedBy: " ")
            streamURLField.text = myStringArr?[0]
            streamTokenField.text = myStringArr?[1]
        }
    }
    // MARK: - IBActions
    
    // MARK: - Legacy Methods
    @IBAction func method1(_ sender: Any) {
        if (streamTokenField.text! != ""){
            assetURL = URL(string: streamURLField.text!)
        }
        if (streamURLField.text! != ""){
            token = streamTokenField.text!
        }
        if (contentIDField.text != ""){
            contentID = contentIDField.text!
        }
        if (assetURL != nil){
            let player = AVPlayer(url: assetURL!)
            self.drm = vudrmFairPlay(player: player, token: token, contentID: contentID)
            player.addObserver(
                self,
                forKeyPath: Constant.KeyPath.Player.rate,
                options: .new,
                context: &KVOContext.player
            )
            
            self.player = player
            
            let playerController = AVPlayerViewController()
            playerController.showsPlaybackControls = false
            playerController.delegate = self as? AVPlayerViewControllerDelegate
            self.showDetailViewController(playerController, sender: self)
            playerController.view.frame = self.view.frame
            playerController.player = self.player
            playerController.showsPlaybackControls = true
            player.play()
            dumpPlayerStatus()
        }
        
    }
    
    @IBAction func method2(_ sender: Any) {
        if (streamTokenField.text! != ""){
            assetURL = URL(string: streamURLField.text!)
        }
        if (streamURLField.text! != ""){
            token = streamTokenField.text!
        }
        if (contentIDField.text != ""){
            contentID = contentIDField.text!
        }
        if (assetURL != nil){
            self.drm = vudrmFairPlay(url:assetURL! as NSURL, token: token, contentID: contentID)
            let playerItem = AVPlayerItem(asset: (drm?.asset)!)
            let player = AVPlayer(playerItem: playerItem)
            player.addObserver(
                self,
                forKeyPath: Constant.KeyPath.Player.rate,
                options: .new,
                context: &KVOContext.player
            )
            
            self.player = player
            
            let playerController = AVPlayerViewController()
            playerController.showsPlaybackControls = false
            playerController.delegate = self as? AVPlayerViewControllerDelegate
            self.showDetailViewController(playerController, sender: self)
            playerController.view.frame = self.view.frame
            playerController.player = self.player
            playerController.showsPlaybackControls = true
            player.play()
            dumpPlayerStatus()
        }
    }
    
    // MARK: - New persisted offline and online Methods
    @IBAction func download(_ sender: UIButton) {
        
        if #available(iOS 10.0, *) {
            assetExists = false
            switch downloadButton.currentTitle {
            case "Cancel":
                self.cancelDownload()
                if self.drm != nil{
                    if (drm?.persistedContentKeyExists)!{
                        deleteAllPersistableContentKeys()
                    }
                }
            default:
                if self.assetDownloadTask == nil {
                    if (streamTokenField.text! != ""){
                        assetURL = URL(string: streamURLField.text!)
                    }
                    if (streamURLField.text! != ""){
                        token = streamTokenField.text!
                    }
                    if (contentIDField.text != ""){
                        contentID = contentIDField.text!
                    }
                    if (assetURL != nil){
                        let asset = AVURLAsset(url: assetURL!)
                        self.drm = vudrmFairPlay(asset: asset, contentID: contentID, token: token)
                        self.drm!.pendingPersistableContentKeyIdentifiers.insert(contentID)
                        assetDownloadTask = assetUrlSession.makeAssetDownloadTask(asset: asset, assetTitle: contentID, assetArtworkData: nil, options: nil)!
                        assetDownloadTask.taskDescription = contentID
                    }
                }
                assetDownloadTask.resume()
            }
        } else {
            // Fallback on earlier versions
            print("Must be iOS 10+ to use Offline")
        }
    }
    
    
    @IBAction func play(_ sender: Any) {
        if self.assetDownloadTask == nil {
            if #available(iOS 10.0, *) {
                if (streamTokenField.text! != ""){
                    assetURL = URL(string: streamURLField.text!)
                }
                if (streamURLField.text! != ""){
                    token = streamTokenField.text!
                }
                if (contentIDField.text != ""){
                    contentID = contentIDField.text!
                }
                if (assetURL != nil){
                    let asset = AVURLAsset(url: assetURL!)
                    self.drm = vudrmFairPlay(asset: asset, contentID: contentID, token: token)
                    assetDownloadTask = assetUrlSession.makeAssetDownloadTask(asset: asset, assetTitle: contentID, assetArtworkData: nil, options: nil)!
                    assetDownloadTask.taskDescription = contentID
                    self.getTasks()
                }
                
            }
        }
        
        guard let assetDownloadTask = self.assetDownloadTask else {
            return }
        
        let playerItem = AVPlayerItem(asset: assetDownloadTask.urlAsset)
        let player = AVPlayer(playerItem: playerItem)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        present(playerViewController, animated: true) {
            player.play()
        }
    }
    
    @IBAction func deleteAsset(_ sender: Any) {
        self.deleteAsset()
    }
    
    
    // MARK: - Private methods
    private func dumpPlayerStatus() {
        guard let player = self.player else { return }
        
        print("Current playback rate: \(player.rate)")
        switch player.status {
        case .unknown:
            print("Player in .unknown status")
        case .readyToPlay:
            print("Player in .readyToPlay status")
        case .failed:
            print("Player in .failed status")
        @unknown default:
            print("Player in .unknown status")
            return
        }
        if #available(iOS 10.0, *) {
            print("reasonForWaitingToPlay: \(String(describing: player.reasonForWaitingToPlay))")
        }
    }
    
    // Get AVAssetDownloadURLSession Tasks
    func getTasks() {
        // Grab all the tasks associated with the assetDownloadURLSession
        self.assetUrlSession.getAllTasks { tasksArray in
            // For each task, restore the state in the app by recreating Asset structs and reusing existing AVURLAsset objects.
            print ("Found \(tasksArray.count) AVAssetDownloadURLSession tasks")
            for task in tasksArray {
                guard let assetDownloadTask = task as? AVAssetDownloadTask, let contentID = task.taskDescription else { break }
                let urlAsset = assetDownloadTask.urlAsset
                print ("Found AVAssetDownloadURLSession task with associated with name: \(contentID) and url: \(urlAsset.url)")
            }
        }
    }
    
    /// Deletes an Asset on disk if possible.
    func deleteAsset() {
        do {
            let localFileLocation = assetFileURL
            try FileManager.default.removeItem(at: localFileLocation!)
            
            //                NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil,
            //                                                userInfo: userInfo)
            
            DispatchQueue.main.async {
                self.downloadProgress.progress = 0.0
            }
            
            print("Deleted the file at \(String(describing: localFileLocation))!")
            deletePersistableContentKey()
            self.assetDownloadTask = nil
            self.drm = nil
            self.downloadButton.isEnabled = true
            self.deleteButton.isEnabled = false
            self.player = nil
        } catch {
            print("An error occured deleting the file: \(error)")
        }
    }
    
    /// Cancels the AVAssetDownloadTask
    func cancelDownload() {
        self.assetDownloadTask.cancel()
    }
    
    // Deletes all the persistable content keys on disk for this specific `Asset`.
    func deleteAllPersistableContentKeys() {
        if contentKeyIDList != nil {
            for contentKeyIdentifier in contentKeyIDList! {
                self.drm!.deletePersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
            }
        }
    }
    
    func deletePersistableContentKey() {
        let contentKeyIdentifier = contentID
        self.drm!.deletePersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
    }
    
    @objc func updateUserInterface() {
        if assetExists == true {
            self.player?.allowsExternalPlayback = false
        }
        
        guard let status = Network.reachability?.status else { return }
        switch status {
        case .unreachable:
            self.downloadButton.isEnabled = false
            self.networkStatus.backgroundColor = .red
            self.methodButton1.isEnabled = false
            self.methodButton2.isEnabled = false
        case .wifi:
            if self.downloadProgress.progress == 0 || assetExists == false {
                self.downloadButton.isEnabled = true}
            self.networkStatus.backgroundColor = .green
            self.methodButton1.isEnabled = true
            self.methodButton2.isEnabled = true
        case .wwan:
            self.downloadButton.isEnabled = false
            self.networkStatus.backgroundColor = .yellow
            self.methodButton1.isEnabled = false
            self.methodButton2.isEnabled = false
        }
        //  print("Reachability Status:", status)
    }
    
    @objc func statusManager(_ notification: Notification) {
        updateUserInterface()
    }
    
    // MARK: - AVPlayerItem notifications
    private func addNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemAccessLog(notification:)),
            name: Notification.Name.AVPlayerItemNewAccessLogEntry,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemErrorLog(notification:)),
            name: Notification.Name.AVPlayerItemNewAccessLogEntry,
            object: nil
        )
    }
    
    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc
    private func itemAccessLog(notification: Notification) {
        if let item = notification.object as? AVPlayerItem,
            let accessLog = item.accessLog(),
            let latestEvent = accessLog.events.last
        {
            print("Access log entry for \(String(describing: latestEvent.uri)), with bytes transfered: \(latestEvent.numberOfBytesTransferred)")
        }
    }
    
    @objc
    private func itemErrorLog(notification: Notification) {
        if let item = notification.object as? AVPlayerItem,
            let errorsLog = item.errorLog(),
            let latestEvent = errorsLog.events.last
        {
            print("Error log from domain: \(latestEvent.errorDomain), code: \(latestEvent.errorStatusCode), comment: \(String(describing: latestEvent.errorComment))")
        }
    }
    
    
    // MARK: - KVO
    private func removeKVOObservers() {
        guard let player = self.player else { return }
        
        player.removeObserver(self, forKeyPath: Constant.KeyPath.Player.rate, context: &KVOContext.player)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &KVOContext.player {
            if keyPath == Constant.KeyPath.Player.rate {
                if let rate = change?[.newKey] as? Float {
                    print("Rate changed: \(rate)")
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    //Calls this function when the tap is recognized.
    @objc func dismissKeyboard() {
        ///Causes the view (or one of its embedded text fields) to resign the first responder status.
        view.endEditing(true)
    }
}

extension ViewController: AVAssetDownloadDelegate {
    
    /// Tells the delegate that the task finished transferring data.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        /*
         This is the ideal/correct place to begin downloading additional media selections
         once the asset itself has finished downloading.
         */
        
        if let error = error as NSError? {
            switch (error.domain, error.code) {
            case (NSURLErrorDomain, NSURLErrorCancelled):
                /*
                 This task was cancelled, you should perform cleanup using the
                 URL saved from AVAssetDownloadDelegate.urlSession(_:assetDownloadTask:didFinishDownloadingTo:).
                 */
                
                do {
                    let localFileLocation = assetFileURL
                    try FileManager.default.removeItem(at: localFileLocation!)
                    
                    //                NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil,
                    //                                                userInfo: userInfo)
                    DispatchQueue.main.async {
                        self.downloadProgress.progress = 0.0
                    }
                    print("Deleted the file at \(String(describing: localFileLocation))!")
                    deletePersistableContentKey()
                    self.assetDownloadTask = nil
                    self.drm = nil
                    self.downloadButton.setTitle("Download", for: .normal)
                    self.downloadButton.isEnabled = true
                    self.deleteButton.isEnabled = false
                } catch {
                    print("An error occured deleting the file: \(error)")
                }
            case (NSURLErrorDomain, NSURLErrorUnknown):
                print("Downloading HLS streams is not supported in the simulator.")
                
            default:
                print("An unexpected error occured \(error.domain)")
            }
        } else {
            /*
             This task did complete sucessfully. At this point the application
             can download additional media selections here if needed.
             
             To download additional `AVMediaSelection`s, you should use the
             `AVMediaSelection` reference saved in `AVAssetDownloadDelegate.urlSession(_:assetDownloadTask:didResolve:)`.
             */
            
        }
    }
    
    
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didFinishDownloadingTo location: URL) {
        /*
         This delegate callback should only be used to save the asset location URL
         somewhere in your application. Any additional work should be done in
         `URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)`.
         */
        
        assetFileURL = location
        self.downloadButton.setTitle("Download", for: .normal)
        self.downloadButton.isEnabled = false
        self.deleteButton.isEnabled = true
        assetExists = true
        print ("Saved persisted asset to \(location)")
    }
    
    public func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                           didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                           timeRangeExpectedToLoad: CMTimeRange){
        var percentComplete = 0.0
        for value in loadedTimeRanges {
            let loadedTimeRange: CMTimeRange = value.timeRangeValue
            percentComplete += CMTimeGetSeconds(loadedTimeRange.duration) / CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        }
        
        self.downloadButton.setTitle("Cancel", for: .normal)
        percentComplete *= 100
        DispatchQueue.main.async {
            self.downloadProgress.progress = Float((percentComplete/100))
        }
        print("percentComplete: \(percentComplete)")
        if percentComplete == Double(100) {
            print("Download complete")
        }
    }
}
