//
//  INFSDKWidgetManager.swift
//  TestFrameworkNew
//
//  Created by Mudit on 11/12/15.
//  Copyright © 2015 INFORM. All rights reserved.
//

import UIKit
import Foundation
import MediaPlayer

/** 🛠 Widget Manager is an Object Factory and will be responsible for -
 - Creation of Playback Controller Object
 - Maintaining all Widgets (assigning WidgetIds, maintaining live widgets)
 - Destructing all Widgets
 */

public class INFSDKWidgetManager: NSObject {
    private static var dispatchOnce : dispatch_once_t = 0
    public static let sharedInstance = INFSDKWidgetManager()
    static let buildEnvironment = ""
    
    var pageIdDictionary : Dictionary<String, INFID>?
    
    var pageCountDictionary : Dictionary<String, Int32>?
    
    private var requestController : INFRequestController = INFRequestController()
    
    var uid : String? = nil
    
    var webpageURL : String?
    
    private var partnerId : Int32 = 0 {
        didSet {
            //TODO: Call partnerID WebService to fetch configurations for the respective partner
        }
    }
    
    private (set) static var _activeWidgets : Dictionary<String, [AnyObject]>?
    static var activeWidgets : Dictionary<String, [AnyObject]>
    {
        if _activeWidgets == nil{
            _activeWidgets = Dictionary<String, [AnyObject]>()
        }
        return _activeWidgets!
    }//Property to maintain Active Widgets & there respective Ids
    
    private func addObservers(){
        
        NSNotificationCenter.defaultCenter().removeObserver(self)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "playbackStall:",
            name: INFSDKNotifications.INFPlaybackStallLikeliness.rawValue, object: nil)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "pauseOtherPlayers:",
            name: INFSDKNotifications.INFPlayEventTriggerred.rawValue, object: nil)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "removeSingleWidget:",
            name: INFSDKNotifications.INFPlaybackControllerRemove.rawValue, object: nil)
    }
    
    //This prevents others from using the default '()' initializer for this class.
    private override init() {
        super.init()
        self.pageIdDictionary = Dictionary<String, INFID>()
        self.pageCountDictionary = Dictionary<String, Int32>()
        ComScoreAnalyticsTracker.initialize()
        self.requestController.resume()
        addObservers()
    }
    
    //MARK: Playback Controller Creation
    /**
    Creates a playbcak controller (widget) object for Video Playback
    - parameter method:      The HTTP method.
    - parameter URLString:   The URL string.
    - parameter parameters:  The parameters. `nil` by default.
    - parameter encoding:    The parameter encoding. `.URL` by default.
    - parameter headers:     The HTTP headers. `nil` by default.
    - parameter destination: The closure used to determine the destination of the downloaded file.
    - returns: The created download request.
    */
    public func createPlayBackControllerFromDiv(let referer : String,
        let pageIDController : INFPageIDController,
        informTag tagFromHTML:String, webpageURL : String) throws ->INFPlaybackController {
            self.webpageURL = webpageURL
            
            // TODO : Review
            let playbackController = INFPlaybackController(referer: referer,
                widgetID: widgetID((unsafeAddressOf(pageIDController).debugDescription)),
                isLoadedFromIFrame : false, webpageURL: webpageURL,
                userInfo: ["addressOfArticle" : unsafeAddressOf(pageIDController).debugDescription])
            do {
                // Initialise widget setting from div
                try playbackController.initWidgetSettingsFromDiv(tagWithSettings: tagFromHTML)
                //If initialization of Widget is Successful, save the session
                INFSDKWidgetManager.saveSession(sessionToSave: playbackController,
                    addressOfArticle: (unsafeAddressOf(pageIDController).debugDescription))
            }
            catch INFPlaybackControllerError.InvalidDivTag
            {
                throw NSError(domain: INFError.Domain, code:
                    INFError.Code.InvalidDivTag.rawValue, userInfo: ["description":"Invalid Div Tag Value passed"])
            }
            catch INFPlaybackControllerError.InvalidPlayerConfigurations
            {
                throw NSError(domain: INFError.Domain,
                    code: INFError.Code.InvalidPlayerConfigurations.rawValue,
                    userInfo: ["description":"Invalid configurations for Widget"])
            }
            catch INFPlaybackControllerError.InvalidPlayerDimensions
            {
                throw NSError(domain: INFError.Domain,
                    code: INFError.Code.InvalidPlayerDimensions.rawValue,
                    userInfo: ["description":"Invalid Dimensions for widget. Minimum Threshold for Height is 20 and Width is 50"])
            }
            catch INFPlaybackControllerError.InvalidTrackingGroupId
            {
                throw NSError(domain: INFError.Domain,
                    code: INFError.Code.InvalidTrackingGroupId.rawValue,
                    userInfo: ["description":"Invalid Tracking Group Id"])
            }
            catch INFPlaybackControllerError.InvalidWidgetId
            {
                throw NSError(domain: INFError.Domain,
                    code: INFError.Code.InvalidWidgetId.rawValue,
                    userInfo: ["description":"Invalid Widget Id"])
            }
            
            initializePlaybackControllerWithPageID(playbackController,referer: referer,
                pageIDController: pageIDController, divTag: tagFromHTML)
            
            return playbackController
    }
    
    private func initializePlaybackControllerWithPageID(let playbackController : INFPlaybackController,
        let referer : String, let pageIDController : INFPageIDController, divTag tagFromHTML:String) {
            
            if self.uid == nil {
                // get uuid and page instance id
                INFPageInstanceIDService().makeRequest({ (callbackType : INFCallbackType?, anyObject : AnyObject?) -> INFRequestController? in
                    
                    switch (callbackType!) {
                    case .RequestSuccess:
                        
                        if (anyObject is INFID) {
                            let idDataFromRequest : INFID = anyObject as! INFID
                            
                            // Race condition check
                            if self.uid != nil {
                                // uid is present
                                
                                // Verify is page id present for provided pageIDController
                                let address : String = (unsafeAddressOf(pageIDController)).debugDescription
                                
                                let idDataFromDictionary : INFID? = self.pageIdDictionary![address];
                                
                                if idDataFromDictionary == nil {
                                    // page id not present for given pageIDController
                                    // set current idDataFromRequest as the id for given pageIDController
                                    self.pageIdDictionary![address] = idDataFromRequest
                                    
                                    // First encounter
                                    let count : Int32 = 1
                                    self.pageCountDictionary![idDataFromRequest.getPageID()] = count
                                    
                                    playbackController.initWidgetWithPageID(idDataFromRequest,
                                        furl : INFConstants.FURL, embedCount : count, eo : self.webpageURL! )
                                } else {
                                    // Page id already present for the pageIDController
                                    // set idDataFromDictionary as the id for given pageIDController
                                    
                                    // Not a first count, increament counter
                                    var count = (self.pageCountDictionary![idDataFromDictionary!.getPageID()]! + 1)
                                    count = count + 1
                                    
                                    self.pageCountDictionary![idDataFromRequest.getPageID()] = count
                                    
                                    playbackController.initWidgetWithPageID(idDataFromDictionary!, furl : INFConstants.FURL, embedCount : self.pageCountDictionary![idDataFromRequest.getPageID()]!, eo : self.webpageURL!)
                                }
                                
                            } else {
                                // uid == nil, implies that its a first request
                                // and not filled by any other racing request
                                // set the idFromRequest in playBackControoler and in pageIdDictionary
                                // set uid
                                self.uid = idDataFromRequest.getUID()
                                
                                let address : String = (unsafeAddressOf(pageIDController)).debugDescription
                                
                                self.pageIdDictionary![address] = idDataFromRequest
                                
                                // First count
                                let count : Int32 = 1
                                self.pageCountDictionary![idDataFromRequest.getPageID()] = count
                                
                                playbackController.initWidgetWithPageID(idDataFromRequest, furl : INFConstants.FURL, embedCount : count, eo : self.webpageURL!)
                            }
                        } else {
                            // Error case
                        }
                        
                        break
                        
                    case .RequestCancel:
                        // Error case
                        playbackController.showError("Network error")
                        break;
                    case .RequestFailure:
                        // Error case
                        playbackController.showError("Network error")
                        break;
                        
                    default:
                        break
                    }
                    
                    return self.requestController
                })
                
            } else {
                // uid already set into sdk widget manager
                // verify is page id present for provided pageIDController
                
                let address : String = (unsafeAddressOf(pageIDController)).debugDescription
                
                let idDataFromDictionary : INFID? = pageIdDictionary![address];
                
                if idDataFromDictionary == nil {
                    // page id not present
                    // Call to FetchPageInstanceIDService to get the page id
                    // Provide uid
                    // First call to get page id
                    fetchPageInstanceID(referer, playbackController: playbackController, address: address)
                } else {
                    // Page id already present for th pageIDController
                    
                    // increament count
                    var count = (self.pageCountDictionary![idDataFromDictionary!.getPageID()]! + 1)
                    count = count + 1
                    self.pageCountDictionary![idDataFromDictionary!.getPageID()] = count
                    
                    playbackController.initWidgetWithPageID(idDataFromDictionary!, furl : INFConstants.FURL, embedCount : count, eo : self.webpageURL!)
                }
            }
    }
    
    private func fetchPageInstanceID(let referer : String, let playbackController : INFPlaybackController, let address : String) {
        INFPageInstanceIDService().makeRequest(referer, uid: self.uid!, completionHandler: { (callbackType : INFCallbackType?, anyObject : AnyObject?) -> INFRequestController? in
            
            switch (callbackType!) {
            case .RequestSuccess:
                
                if (anyObject is INFID) {
                    let idData : INFID = anyObject as! INFID
                    
                    self.pageIdDictionary![address] = idData
                    
                    // First count
                    let count : Int32 = 1
                    self.pageCountDictionary![idData.getPageID()] = count
                    
                    playbackController.initWidgetWithPageID(idData, furl : INFConstants.FURL, embedCount : count, eo : self.webpageURL!)
                    
                } else {
                    // Error case
                }
                
                break
                
            case .RequestCancel:
                // Error case
                playbackController.showError("Network error")
                break;
            case .RequestFailure:
                // Error case
                playbackController.showError("Network error")
                break;
            default:
                break
            }
            return self.requestController
        })
    }
    
    
    
    private func widgetID(addressOfController:String) -> Int32{
        //TODO: Add code to assign widget ID while initializing any widget
        var widgetId : Int32 = 0
        if INFSDKWidgetManager.activeWidgets.keys.contains(addressOfController)
        {
            //Article is present for some widget earlier
            for (key, value) in INFSDKWidgetManager.activeWidgets{
                if key == addressOfController{
                    let widgetsForController = value
                    widgetId = Int32(widgetsForController.count)
                }
            }
        }
        else
        {
            //Article is not present for any widget - Default Widget ID is 0 always
            widgetId = 0
        }
        return widgetId
    }
    
    func playbackStall(notification: NSNotification){
        //TODO: Add Code for playback Stall Likeliness Logic
    }
    
    private static func saveSession(sessionToSave session:INFPlaybackController, addressOfArticle : String){
        if let _ = _activeWidgets{
            if INFSDKWidgetManager.activeWidgets.keys.contains(addressOfArticle){
                var playbackControllers = _activeWidgets![addressOfArticle]
                playbackControllers?.append(session)
                _activeWidgets![addressOfArticle] = playbackControllers
            }
            else{
                _activeWidgets![addressOfArticle] = [session]
            }
        }
        else{
            _activeWidgets = Dictionary<String, [AnyObject]>()
            _activeWidgets![addressOfArticle] = [session]
        }
        
    }
    
    //MARK: Observer Method to pause all other Players except the one which is opted to Play
    final func pauseOtherPlayers(notification: NSNotification){
        let userInfo = notification.object as? Dictionary<String, AnyObject>
        if let currentURL : NSURL = userInfo!["currentlyPlayingURL"] as? NSURL,
            let sessionProviderRef = userInfo!["sessionProvider"] as? String{
                for (key, value) in INFSDKWidgetManager.activeWidgets{
                    for playbackController:INFPlaybackController in value as! [INFPlaybackController]{
                        guard let _ = playbackController.sessionProvider.videoPlayer
                            else{
                                return
                        }
                        guard let _ = playbackController.sessionProvider.videoPlayer!.videoPlayer
                            else{
                                return
                        }
                        let asset = playbackController.sessionProvider.videoPlayer!.videoPlayer?.currentItem?.asset
                        if let _ = asset{
                            if (asset!.isMemberOfClass(AVURLAsset) && asset != nil)
                            {
                                let urlAsset = asset as! AVURLAsset
                                if currentURL != urlAsset.URL && sessionProviderRef == key{
                                    playbackController.sessionProvider.videoPlayer!.videoPlayer?.pause()
                                    playbackController.sessionProvider.videoPlayer!.playButton?.hidden = false
                                    playbackController.sessionProvider.videoPlayer!.pauseButton?.hidden = true
                                }
                            }
                        }
                    }
                }
        }
    }
    
    //MARK: Pause Widgets
    /**
    Closure to Pause Widgets, this method needs to be called from the Application View Controller for saving video Session, before navigating to other View Controllers
    - Returns: nil
    - Parameter pageIdController: View Controller Object
    - Parameter completion: Completion Handler provides viewWithPlayer, isSuccess, userInfo
    */

    public func pausePlayersForPage(pageIdController controller: INFPageIDController,
        completion:(isSuccess:Bool,
        userInfo:Dictionary<String, AnyObject>?)->Void){
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), {
                let controller = unsafeAddressOf(controller).debugDescription
                
                for (key, value) in INFSDKWidgetManager.activeWidgets{
                    if key == controller{
                        for playbackController:INFPlaybackController in value as! [INFPlaybackController]{
                            guard let _ = playbackController.sessionProvider.videoPlayer
                                else{
                                    completion(isSuccess:false, userInfo:["Status":NSLocalizedString("Widget_Not_Exist",
                                        tableName: "INFLocalizable", bundle: NSBundle(forClass: INFSDKWidgetManager.self),
                                        comment: "Widget doesn't exist")])
                                    return
                            }
                            guard let _ = playbackController.sessionProvider.videoPlayer!.videoPlayer
                                else{
                                    completion(isSuccess:false, userInfo:["Status":NSLocalizedString("Widget_Not_Exist",
                                        tableName: "INFLocalizable", bundle: NSBundle(forClass: INFSDKWidgetManager.self),
                                        comment: "Widget doesn't exist")])
                                    
                                    return
                            }
                            playbackController.sessionProvider.videoPlayer!.videoPlayer?.currentItem?.cancelPendingSeeks()
                            playbackController.sessionProvider.videoPlayer!.videoPlayer?.pause()
                            playbackController.sessionProvider.videoPlayer!.playButton?.hidden = false
                            playbackController.sessionProvider.videoPlayer!.pauseButton?.hidden = true
                            completion(isSuccess:true, userInfo:["Status":NSLocalizedString("Success",
                                tableName: "INFLocalizable", bundle: NSBundle(forClass: INFSDKWidgetManager.self),
                                comment: "All Widget(s) successfully paused")])
                        }
                    }
                    else{
                        completion(isSuccess:false, userInfo:["Status":NSLocalizedString("Widget_Not_Exist",
                            tableName: "INFLocalizable", bundle: NSBundle(forClass: INFSDKWidgetManager.self),
                            comment: "Widget doesn't exist")])
                    }
                }
                
            })
    }
    
    //MARK: Unload All Widgets
    /**
    Closure for unloading Widget (Unloading means - Pause a video and save its state),
    It also internally calls method for saving video Session.
    - Returns: nil
    - Parameter pageIdController: View Controller Object
    - Parameter completion: Completion Handler provides viewWithPlayer, isSuccess, userInfo
    */
    public func unLoadAllWidgets(pageIdController controller: INFPageIDController,
        completion:(isSuccess:Bool,
        userInfo:Dictionary<String, AnyObject>?)->Void){
            print(INFSDKWidgetManager._activeWidgets)
            let key = unsafeAddressOf(controller).debugDescription
            let widgets = INFSDKWidgetManager._activeWidgets?.keys
            guard let _ = widgets
                else{
                    completion(isSuccess:false, userInfo:["Status":NSLocalizedString("Widget_Not_Exist",
                        tableName: "INFLocalizable", bundle: NSBundle(forClass: INFSDKWidgetManager.self),
                        comment: "Widget doesn't exist")])
                    return
            }
            if widgets?.count > 0 && widgets!.contains(key){
                for widget in INFSDKWidgetManager._activeWidgets![key]!{
                    var playbackController = widget as? INFPlaybackController
                    if let _ = playbackController?.sessionProvider.videoPlayer{
                        playbackController?.sessionProvider.videoPlayer!.videoPlayer?.pause()
                        playbackController?.sessionProvider.videoPlayer!.videoPlayer?.currentItem?.cancelPendingSeeks()
                        playbackController?.sessionProvider.videoPlayer!.videoPlayer?.currentItem?.asset.cancelLoading()
                        playbackController?.sessionProvider.videoPlayer!.videoPlayerLayer?.removeFromSuperlayer()
                        playbackController?.sessionProvider.videoPlayer!.videoPlayer = nil
                        playbackController?.sessionProvider.videoPlayer = nil
                        playbackController?.mainView?.removeFromSuperview()
                        playbackController?.mainView = nil
                        playbackController = nil
                        INFSDKWidgetManager._activeWidgets![key]!.removeFirst()
                    }
                }
                INFSDKWidgetManager._activeWidgets?.removeValueForKey(key)
                completion(isSuccess:true, userInfo:["Status":NSLocalizedString("Widget_Unloaded",
                    tableName: "INFLocalizable", bundle: NSBundle(forClass: INFSDKWidgetManager.self),
                    comment: "Widget removed")])
            }
            else{
                completion(isSuccess:false, userInfo:["Status":NSLocalizedString("Widget_Not_Exist",
                    tableName: "INFLocalizable", bundle: NSBundle(forClass: INFSDKWidgetManager.self),
                    comment: "Widget doesn't exist")])
            }
    }
    
    
    //MARK:Method to remove single Widget
    internal static func removeSingleWidget(userInfo: Dictionary<String,INFPlaybackController>){
        if let widget = userInfo["playbackController"]{
            for (key, value) in INFSDKWidgetManager._activeWidgets!{
                var widgetsForKey : Array = value
                var i = 0
                for controller in widgetsForKey{
                    if controller  as? INFPlaybackController == widget{
                        widgetsForKey.removeAtIndex(i)
                        INFSDKWidgetManager._activeWidgets?[key] = widgetsForKey
                    }
                    i++
                }
            }
        }
    }
    
    public static func versionNumber() -> String{
        let bundle = NSBundle(forClass: INFSDKWidgetManager.self).infoDictionary!
        return bundle["CFBundleShortVersionString"] as! String
    }
    
    deinit {
        INFSDKWidgetManager._activeWidgets = nil
        NSNotificationCenter.defaultCenter().removeObserver(self)
        requestController.cancel()
    }
}