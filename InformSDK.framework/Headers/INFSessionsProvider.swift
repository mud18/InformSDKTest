//
//  INFSessionsHandler.swift
//  InformSDK
//
//  Created by Mudit on 15/12/15.
//  Copyright © 2015 INFORM. All rights reserved.
//

import Foundation
import MediaPlayer
import Argo

/**
 All possible Asset types that can be obtained in LPS Service Response
 */
public enum AssetType : String{
    case StillFrame                 = "stillFrame"
    case StillFrameXL               = "StillFrameXL"
    case Thumbnail                  = "thumbnail"
    case Video_mp4                  = "video/mp4"
    case Application_xmpeg          = "application/x-mpeg"
    case Application_xmpegURL       = "application/x-mpegURL"
    case Video_f4m                  = "video/f4m"
    case Video_xflv                 = "video/x-flv"
    case Video_progressive          = "video/progressive"
    
}

private enum KeysValueToModify : String{
    case LogoURL169         = "LogoURL169"
    case LogoURL43          = "LogoURL43"
    case Playlists          = "Playlists"
    case Contents           = "Contents"
    case ProducerLogo       = "ProducerLogo"
    case Assets             = "Assets"
    case AssetLocation      = "AssetLocation"
    case AssetMimeType      = "AssetMimeType"
    case AssetType          = "AssetType"
}

@objc public protocol INFSessionProviderDelegate
{
    func playbackFailed()
}

public class INFSessionsProvider: NSObject, INFVideoViewDelegate,
INFVideoPlayerEventsDelegate, INFVideoPlaybackEventsDelegate {
    static let DEFAULTPLAYLISTID = 9999999
    static let DEFAULTPLAYLISTTITLE = "default playlist"
    static let DEFAULTPLAYLISTOREDER = 0
    var sessionHandlerId : Int32! //SessionHandlerId should be playlistId ot Tracking group Id
    var sessions = [INFSessionData]?() //Property to maintain Sessions
    var videoPlayer : INFVideoPlayerView?
    //= INFVideoPlayerView()
    lazy var sessionForVideo = INFSession()
    var currentlyPlayingVideo : INFVideo?
    lazy var currentPlaylistItem = INFPlaylists()
    var currentPlaylist : [INFVideo]?
    var currentVideoPosition : Int = -999
    var currentPlayingContent : INFContents?
    var playerConfigurations: INFPlayerConfigurations?
    lazy var adsVideoPlayer = INFAdsPlayer()
    var pageInstanceId : String?
    var userId : String?
    var widgetIndex : Int32?
    var furl : String?
    var siteSectionName : String?
    private var addressOfArticle : String?
    var comscoreTracker : ComScoreAnalyticsTracker?
    var informAnalyticsTracker : INFAnalyticsTracker?
    
    // Cache player view for analytics view port tracking
    var videoView : UIView?
    
    var requestController : INFRequestController?
    
    var fullScreenController : INFVideoViewController?
    
    var sessionProviderDelegate : INFSessionProviderDelegate?
    
    private func videoPlayerFromFactory(isPlaylist playlist:Bool){
        self.videoPlayer = INFVideoPlayerView(address: self.addressOfArticle!)
        self.videoPlayer!.videoPlayer = INFVideoPlayerManager.videoPlayer(reuseVideoPlayer: playlist)
    }
    
    private func adsPlayerFromFactory(isSinglePlayer singlePlayer:Bool){
        self.adsVideoPlayer.adsPlayer = INFVideoPlayerManager.adsPlayer(reuseAdsPlayer: singlePlayer)
    }
    
    internal func requestDataForWidget(referer : String, widgetConfigurations:INFPlayerConfigurations,
        requestController:INFRequestController, isQueryParamsRequired: Bool, widgetId:Int32,
        pageInstanceID:String, userID:String, userInfo:Dictionary<String, AnyObject>?, informAnalyticsTracker : INFAnalyticsTracker?, widgetIndex : Int32, furl : String,
        completion:(sessionForVideoId:INFBaseClass?, isSuccess:Bool, error:NSError?, viewWithPlayer:UIView?) -> Void) {
            self.playerConfigurations = widgetConfigurations
            self.widgetIndex = widgetIndex
            self.furl = furl
            self.requestController = requestController
            self.informAnalyticsTracker = informAnalyticsTracker
            
            videoPlayerFromFactory(isPlaylist: false)
            
            //Auto Play Logic Handling
            /*TODO: Recognise type of Video Player Widget required based on
                PlayerConfiguration.playerType, and create URL for request
            */
            
            let lpsService = INFLPSService(trackingGroup: widgetConfigurations.dataTrackingGroupId,
                widgetID: widgetConfigurations.dataConfigWidgetId,
                playlistID: widgetConfigurations.playlistId,
                videoID: widgetConfigurations.videoId,
                playlistVideoCount: widgetConfigurations.playListCount, queryParams: queryParamteres(isQueryParamsRequired))
            
            lpsService.makeRequest({
                (callbackType : INFCallbackType?, response : AnyObject?) -> INFRequestController? in
                
                switch (callbackType!) {
                case .RequestSuccess:
                    var json: AnyObject? = try? NSJSONSerialization.JSONObjectWithData(response as! NSData,
                        options: NSJSONReadingOptions(rawValue: 0))
                    json = self.assetBaseURL(json as! Dictionary<String, AnyObject>, isHTTPS: false)
                    if let j: AnyObject = json {
                        let lpsServiceResponse : INFBaseClass = decode(j)!
                        let playerView = self.loadSession(referer, pageId: pageInstanceID, uId: userID,
                            widgetId: widgetId, lpsResponse: lpsServiceResponse)
                        self.siteSectionName = lpsServiceResponse.siteSectionName
                        if let _ = playerView{
                            completion(sessionForVideoId: lpsServiceResponse, isSuccess: true, error: nil, viewWithPlayer:playerView)
                        }
                        else{
                            completion(sessionForVideoId: lpsServiceResponse, isSuccess: false,
                                error: INFError.errorWithCode(INFError.PlaybackErrorCode.PlayerNotInitialized.rawValue,
                                    failureReason: "Player Not Available"), viewWithPlayer:playerView)
                        }
                        
                    } else {
                        // Json is nil
                        
                        completion(sessionForVideoId: nil, isSuccess: false,
                            error: INFError.errorWithCode(INFError.NetworkError.NetworkInvalidData.rawValue,
                                failureReason: "Json is nil"), viewWithPlayer:nil)
                    }
                    break
                    
                case .RequestFailure:
                    if let responseOfFailure  = response as? INFGatewayError {
                        completion(sessionForVideoId: nil, isSuccess: false,
                            error: responseOfFailure.errorWithCode(), viewWithPlayer:nil)
                    }
                    
                    break
                    
                case .RequestCancel:
                    completion(sessionForVideoId: nil, isSuccess: false,
                        error: INFError.errorWithCode(INFError.NetworkError.NetworkRequestCanceled.rawValue,
                            failureReason: "Request Failure"), viewWithPlayer:nil)
                    break
                    
                default:
                    break
                }
                
                return requestController
            })
    }
    
    private func initializeComscore(referer : String, distributorName : String, mediaProviderName : String,
        siteSection : String?, pageURL : String, providerName : String, articleNo : String, pluginVersion : String, contentAssetID : String) {
            // Initialize comscore tracker
            do {
                
                try self.comscoreTracker = ComScoreAnalyticsTracker(distributionPartnerName: distributorName, mediaProviderName: mediaProviderName, siteSection: siteSection, pageURL: pageURL, providerName: "Inform Player Suite", articleNo: articleNo, pluginVersion: pluginVersion, contentAssetID: contentAssetID)
                
            } catch {
                INFLogger.error("Comscore tracker initialization failed")
            }
    }
    
    
    private func queryParamteres(isParamRequired : Bool) -> Dictionary<INFLPSService.QueryParams, String>?{
        if isParamRequired{
            var lpsQueryParams = Dictionary<INFLPSService.QueryParams, String>()
            if let pageId = self.pageInstanceId , let uId = self.userId{
                lpsQueryParams[INFLPSService.QueryParams.UniqueUserToken] = uId
                lpsQueryParams[INFLPSService.QueryParams.PageInstanceID] = pageId
            }
            lpsQueryParams[INFLPSService.QueryParams.BuildEnvironment] = INFSDKWidgetManager.buildEnvironment
            if let widgetIndexValue = self.widgetIndex{
                lpsQueryParams[INFLPSService.QueryParams.EmbedIndex] = String(widgetIndexValue)
            }
            lpsQueryParams[INFLPSService.QueryParams.EpochTime] = String(INFHelperClass.epochOfCurrentTime())
            lpsQueryParams[INFLPSService.QueryParams.TimeRequestStarted] = String(INFHelperClass.epochOfCurrentTime())
            lpsQueryParams[INFLPSService.QueryParams.PlayerBuildVersion] = String(InformSDKVersionNumber)
            
            
            return lpsQueryParams
        }
        else{
            return nil
        }
    }
    /**
     defaultPlaylistItem selects default playlist to be played by Widget
     - Parameter Response: Model Class containing LPS Service Response
     - Returns INFPlaylists: Containing default playlist for AVPlayer instance
     */
    
    private func defaultPlaylistItem(lpsResponse : INFBaseClass){
        var isDefaultPlaylistEmpty = false
        for playlistItem in lpsResponse.playlists! {
            if playlistItem.playlistid == INFSessionsProvider.DEFAULTPLAYLISTID &&
                playlistItem.title == INFSessionsProvider.DEFAULTPLAYLISTTITLE &&
                playlistItem.playlistOrder == INFSessionsProvider.DEFAULTPLAYLISTOREDER{
                    if let _ = playlistItem.contents{
                        if playlistItem.contents?.count != 0{
                            self.currentPlaylistItem = playlistItem
                        }
                        else{
                            isDefaultPlaylistEmpty = true
                        }
                        break
                    }
                    
                    
            }
        }
        if isDefaultPlaylistEmpty{
            for playlistItem in lpsResponse.playlists! {
                if playlistItem.playlistid != INFSessionsProvider.DEFAULTPLAYLISTID &&
                    playlistItem.title != INFSessionsProvider.DEFAULTPLAYLISTTITLE &&
                    playlistItem.contents != nil{
                        self.currentPlaylistItem = playlistItem
                }
            }
        }
        
    }
    //MARK:Method to load session (i.e, AVPlayer instance, make WS Calls for Video and Metadata)
    /**
    Provides view instance conatining Video Player loaded with Video
    - Returns UIView: containing AVPlayer instance
    */
    func loadSession(referer : String, pageId : String, uId : String, widgetId : Int32, lpsResponse:INFBaseClass) -> UIView?{
        //TODO: Make Video WS Call here and fill response to INFVideo Model Class & throw Error
        //TODO: Provide belowmentioned bool value based on the inputs obtained from WebService
        
        defaultPlaylistItem(lpsResponse)
        guard let _ = self.videoPlayer
            else{
                return nil
        }
        self.videoPlayer!.videoViewEventDelegate = self
        self.videoPlayer!.videoPlayerEventsDelegate = self
        self.videoPlayer!.videoPlaybackEventDelegate = self
        self.pageInstanceId =  pageId
        self.userId = uId
        
        self.currentPlayingContent = self.videoPlayer!.setupContentPlayer(videoData: self.currentPlaylistItem,
            videoPlayerFrame: CGRect(x: 0, y: 0,
                width: (self.playerConfigurations?.playerWidth)!,
                height: (self.playerConfigurations?.playerHeight)!), userInfo: nil, eventType : INFVideoPlayerView.SetContentPlayerEvent.LOAD_SESSION)
        
        
        //Add Video Player to a custom View
        let viewWithPlayer = playerView()
        
        // Initialize comscore
        initializeComscore(referer, distributorName: (lpsResponse.distributorName)!, mediaProviderName: currentPlayingContent!.producerName!, siteSection: lpsResponse.siteSectionName, pageURL: (lpsResponse.landingURL)!, providerName: "Inform Player Suite", articleNo: referer, pluginVersion: String(InformSDKVersionNumber), contentAssetID: String(currentPlayingContent!.contentID!))
        
        // TODO run time error break
        // self.currentlyPlayingVideo = self.currentPlaylist![self.currentVideoPosition]
        return viewWithPlayer
    }
    
    //Method to return Video Player View
    private func playerView() -> UIView? {
        self.videoView = UIView(frame: CGRect(x: 0, y: 0,
            width: (self.playerConfigurations?.playerWidth)!,
            height: (self.playerConfigurations?.playerHeight)!))
        
        if let _ = self.videoPlayer, let _ = self.videoPlayer!.videoPlayerLayer{
            self.videoView!.layer.addSublayer(self.videoPlayer!.videoPlayerLayer!)
            self.videoPlayer!.viewWithTitle(self.currentPlaylistItem, viewWithPlayer: self.videoView!,
                userInfo: ["isFullScreen":(self.playerConfigurations?.isFullScreen)!])
            
            UIView.transitionWithView(self.videoView!, duration: 2.0, options: UIViewAnimationOptions.TransitionCurlUp,
                animations: {
                    self.videoPlayer!.viewWithPlaybackControls(self.videoView!)
                    
                    self.videoPlayer!.viewWithSeekbar(self.videoView!)
                    self.videoView!.alpha = 1.0
                }, completion: {
                    finishedAnimatingView in
                    print("Finished animating view \(finishedAnimatingView)")
            })
            return self.videoView!
        }
        else{
            return nil
        }
    }
    
    //Mark: Video Player Playback Events
    /**
    Starts Playback of Video
    - Returns: Void
    - Throws: Different types of Playback Errors, depending on situation i.e., -
    - PlaybackFailed
    - PlayerNotInitialized
    - PlayerStatusUnkown
    - PlayerUnknownError - In case Error is not known and is not handled
    */
    public func playVideo() throws -> Void
    {
        do{
            try  self.videoPlayer!.play()
        }
        catch INFPlaybackError.PlaybackFailed(let attributes){
            print(attributes.Code)
            print(attributes.Domain)
            print(attributes.Description)
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch INFPlaybackError.PlayerStatusUnkown(let attributes){
            print(attributes.Code)
            print(attributes.Domain)
            print(attributes.Description)
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch INFPlaybackError.PlayerNotInitialized(let attributes){
            print(attributes.Code)
            print(attributes.Domain)
            print(attributes.Description)
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch{
            print("Unknown Error")
            throw INFError.errorWithCode(INFError.PlaybackErrorCode.PlayerUnknownError.rawValue, failureReason: "Error Not Known")
        }
    }
    
    /**
     Pauses Playback of Video
     - Throws: Different types of Playback Errors, depending on situation i.e., -
     - PlayerNotInitialized
     - PlayerUnknownError - In case Error is not known and is not handled
     */
    func pauseVideo() throws
    {
        do{
            let currentTime = try self.videoPlayer!.pause()
            self.currentlyPlayingVideo?.videoCurrentTime = currentTime
            self.currentPlaylist?[self.currentVideoPosition] = self.currentlyPlayingVideo!
        }
        catch INFPlaybackError.PlayerNotInitialized(let attributes){
            print(attributes.Code)
            print(attributes.Domain)
            print(attributes.Description)
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch{
            print("Unknown Error")
            throw INFError.errorWithCode(INFError.PlaybackErrorCode.PlayerUnknownError.rawValue, failureReason: "Error Not Known")
        }
    }
    
    func stopVideo() throws
    {
        do{
            try self.videoPlayer!.stop()
            //self.currentPlaylist?[self.currentVideoPosition] = self.currentlyPlayingVideo!
        }
        catch INFPlaybackError.PlayerNotInitialized(let attributes){
            print(attributes.Code)
            print(attributes.Domain)
            print(attributes.Description)
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch INFPlaybackError.StopFailed(let attributes)
        {
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch{
            print("Unknown Error")
            throw INFError.errorWithCode(INFError.PlaybackErrorCode.PlayerUnknownError.rawValue, failureReason: "Error Not Known")
        }
    }
    
    public func fullScreenEvent(isFullScreen : Bool) throws {
        
        if (!isFullScreen) {
            fullScreenController = INFVideoViewController(videoPlayerViewHolder: self.videoPlayer!, videoView: self.videoView!, playerConfiguration : self.playerConfigurations!)
            
            fullScreenController?.showView(isFullScreen)
        } else {
            fullScreenController?.showView(isFullScreen)
        }
    }
    
    
    //Method to return UIVIew with Ads Video Player
    func adsView() -> UIView{
        let viewWithAd = UIView()
        let adsPlayerLayer = AVPlayerLayer(player: self.adsVideoPlayer.adsPlayer)
        viewWithAd.layer.addSublayer(adsPlayerLayer)
        return viewWithAd
    }
    
    //MARK:VideoView Delegate implementation - To catch the %age of Video Compeleted
    public func currentVideoViewPercent(videoViewPercent videoView: INFViewPercent, currentPlayTime : Float64) {
        print("videoViewPercent", String(videoView.rawValue))
        //Make Analytics call here
        //Make Ads Calls here, if any
        
        // Make analytics call for video load hit event
        let informVideoViewEvent : INFVideoViewEvent = INFVideoViewEvent()
        var videoViewEventDictionary = Dictionary<InformEvent.EventParam, Any>()
        
        videoViewEventDictionary[InformEvent.EventParam.EI] = self.widgetIndex
        
        // Fetch video load index
        var videoLoadIndex : Int = -1
        
        if (self.currentPlaylistItem.contents != nil) {
            for (var i = 0 ; i < self.currentPlaylistItem.contents!.count ; i++) {
                if (self.currentPlaylistItem.contents![i].contentID! !=  self.currentPlayingContent!.contentID!) {
                    videoLoadIndex = i
                }
            }
        }
        
        if self.playerConfigurations != nil {
            videoViewEventDictionary[InformEvent.EventParam.ANID] = self.playerConfigurations!.dataTrackingGroupId
            videoViewEventDictionary[InformEvent.EventParam.CP] = self.playerConfigurations!.continuousPlay
            videoViewEventDictionary[InformEvent.EventParam.VW] = Int32(self.playerConfigurations!.playerWidth)
            videoViewEventDictionary[InformEvent.EventParam.VH] = Int32(self.playerConfigurations!.playerHeight)
            videoViewEventDictionary[InformEvent.EventParam.PW] = Int32(self.playerConfigurations!.playerWidth)
            videoViewEventDictionary[InformEvent.EventParam.PH] = Int32(self.playerConfigurations!.playerHeight)
            videoViewEventDictionary[InformEvent.EventParam.WGT] = self.playerConfigurations!.dataConfigWidgetId
            
        }
        
        if videoLoadIndex != -1 {
            videoViewEventDictionary[InformEvent.EventParam.VLI] = Int32(videoLoadIndex)
        }
        if self.furl != nil {
            videoViewEventDictionary[InformEvent.EventParam.FURL] = self.furl!
        }
        if self.siteSectionName != nil {
            videoViewEventDictionary[InformEvent.EventParam.SSID] = self.siteSectionName!
        }
        
        if currentPlayingContent != nil && currentPlayingContent!.contentID != nil{
            videoViewEventDictionary[InformEvent.EventParam.VID] = Int32(currentPlayingContent!.contentID!)
        }
        
        if self.currentPlaylistItem.playlistid != nil {
            videoViewEventDictionary[InformEvent.EventParam.PLAYLIST_ID] = Int32(self.currentPlaylistItem.playlistid!)
        }
        
        videoViewEventDictionary[InformEvent.EventParam.PERCENTPLAYED] = Int32(videoView.rawValue)
        
        videoViewEventDictionary[InformEvent.EventParam.TIMEPLAYED] = currentPlayTime
        
        // TODO : Analytics : Need to verify widgetIndex
        if self.widgetIndex != -1 {
            videoViewEventDictionary[InformEvent.EventParam.PLORDER] = self.widgetIndex
        }
        
        videoViewEventDictionary[InformEvent.EventParam.SW] = INFUIUtilities.getScreenWidth()
        videoViewEventDictionary[InformEvent.EventParam.SH] = INFUIUtilities.getScreenHeight()
        
        videoViewEventDictionary[InformEvent.EventParam.FE] = false
        videoViewEventDictionary[InformEvent.EventParam.FV] = "0"
        
        videoViewEventDictionary[InformEvent.EventParam.V] = true
        
        videoViewEventDictionary[InformEvent.EventParam.VT] = INFConstants.VIDEOTYPE_HTML5
        
        informVideoViewEvent.setValues(videoViewEventDictionary)
        if informAnalyticsTracker != nil && requestController != nil {
            informAnalyticsTracker!.trackEvent(informVideoViewEvent, requestController: requestController!)
        }
    }
    
    public func currentVideoViewHit(hitDuration: Int) {
        print(hitDuration)
        
        do{
            if comscoreTracker != nil {
                try comscoreTracker!.trackEvent(ComscoreVideoPlayEvent())
            } else {
                INFLogger.error("Comscore initialization not done")
            }
        }
        catch ComScoreAnalyticsTracker.ComscoreError.InitializationNotDone {
            INFLogger.error("Comscore initialization not done")
        } catch {
            INFLogger.error("Unknown error, comscore play event traking")
        }
    }
    
    //MARK: Video Player Events Delegate implementation
    public func playbackCompleted(videoURL url: NSURL) throws{
        //TODO:Current code support only Single Video, in case of multiple videos next video should get loaded
        INFLogger.info("Playack Completed \(url)")
        do{
            try self.videoPlayer!.stop()
            self.videoPlayer!.setupContentPlayer(videoData: self.currentPlaylistItem,
                videoPlayerFrame: CGRect(x: 0, y: 0,
                    width: (self.playerConfigurations?.playerWidth)!,
                    height: (self.playerConfigurations?.playerHeight)!), userInfo: nil, eventType : INFVideoPlayerView.SetContentPlayerEvent.PLAYBACK_COMPLETED_EVENT)
        }
        catch INFPlaybackError.PlayerNotInitialized(let attributes){
            INFLogger.error("Player not Initialized")
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch INFPlaybackError.StopFailed(let attributes)
        {
            INFLogger.error("Play back error stop failed")
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch{
            INFLogger.error("Unknown Error")
            throw INFError.errorWithCode(INFError.PlaybackErrorCode.PlayerUnknownError.rawValue, failureReason: "Error Not Known")
        }
    }
    
    public func failedToPlay(videoURL url: NSURL) {
        INFLogger.info("failedToPlay \(url)")
        if self.sessionProviderDelegate != nil {
            self.sessionProviderDelegate!.playbackFailed()
        }
    }
    
    public func playbackJumped(videoURL url: NSURL) {
        INFLogger.info("playbackJumped \(url)")
    }
    
    public func playbackStalled(videoURL url: NSURL) {
        INFLogger.info("playbackStalled \(url)")
    }
    
    public func playerAccessLogsAvailable(videoURL url: NSURL) {
        INFLogger.info("playerAccessLogsAvailable \(url)")
        
        
        // Make analytics call for video load hit event
        let informVideoLoadEvent : INFVideoLoadEvent = INFVideoLoadEvent()
        
        var videoLoadEventDictionary = Dictionary<InformEvent.EventParam, Any>()
        videoLoadEventDictionary[InformEvent.EventParam.EI] = self.widgetIndex
        
        if self.playerConfigurations != nil {
            videoLoadEventDictionary[InformEvent.EventParam.WID] = self.playerConfigurations!.dataConfigWidgetId
            videoLoadEventDictionary[InformEvent.EventParam.ANID] = self.playerConfigurations!.dataTrackingGroupId
            videoLoadEventDictionary[InformEvent.EventParam.PW] = Int32((self.playerConfigurations!.playerWidth)!)
            videoLoadEventDictionary[InformEvent.EventParam.PH] = Int32((self.playerConfigurations!.playerHeight)!)
        }
        
        
        if self.siteSectionName != nil {
            videoLoadEventDictionary[InformEvent.EventParam.SSID] = self.siteSectionName!
        }
        videoLoadEventDictionary[InformEvent.EventParam.FURL] = self.furl
        
        if currentPlayingContent != nil && currentPlayingContent!.contentID != nil {
            videoLoadEventDictionary[InformEvent.EventParam.VID] = Int32(currentPlayingContent!.contentID!)
        }
        
        videoLoadEventDictionary[InformEvent.EventParam.SOUND] = true
        
        if currentPlaylistItem.playlistid != nil {
            videoLoadEventDictionary[InformEvent.EventParam.PLAYLIST_ID] = Int32(currentPlaylistItem.playlistid!)
        }
        // TODO : Analytics : Need to check player behaviour : Player behaviour table is not defined
        //videoLoadEventDictionary[InformEvent.EventParam.PB] = 0
        
        // TODO : Analytics : View port visibility
        videoLoadEventDictionary[InformEvent.EventParam.V] = true
        informVideoLoadEvent.setValues(videoLoadEventDictionary)
        
        if self.informAnalyticsTracker != nil && self.requestController != nil {
            self.informAnalyticsTracker!.trackEvent(informVideoLoadEvent, requestController: self.requestController!)
        }
    }
    
    public func playerErrorLogsAvailable(videoURL url: NSURL) {
        INFLogger.info("playerErrorLogsAvailable \(url)")
    }
    
    //MARK: Video Playback Events Delegates Defined
    public func playEvent() throws {
        do{
            try  self.videoPlayer!.play()
            if comscoreTracker != nil {
                try comscoreTracker!.trackEvent(ComscoreVideoPlayEvent())
            } else {
                INFLogger.error("Comscore initialization not done")
            }
        }
        catch ComScoreAnalyticsTracker.ComscoreError.InitializationNotDone {
            INFLogger.error("Comscore initialization not done")
        }
        catch INFPlaybackError.PlaybackFailed(let attributes){
            INFLogger.error("\(attributes.Code)")
            INFLogger.error(attributes.Domain)
            INFLogger.error(attributes.Description)
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch INFPlaybackError.PlayerStatusUnkown(let attributes){
            INFLogger.error("\(attributes.Code)")
            INFLogger.error(attributes.Domain)
            INFLogger.error(attributes.Description)
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch INFPlaybackError.PlayerNotInitialized(let attributes){
            INFLogger.error("\(attributes.Code)")
            INFLogger.error(attributes.Domain)
            INFLogger.error(attributes.Description)
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch{
            print("Unknown Error")
            throw INFError.errorWithCode(INFError.PlaybackErrorCode.PlayerUnknownError.rawValue, failureReason: "Error Not Known")
        }
    }
    
    public func pauseEvent() throws {
        do{
            let currentTime = try self.videoPlayer!.pause()
            if comscoreTracker != nil {
                try comscoreTracker!.trackEvent(ComscoreVideoPauseEvent())
            } else {
                INFLogger.error("Comscore initialization not done")
            }
            
            self.currentlyPlayingVideo?.videoCurrentTime = currentTime
            self.currentPlaylist?[self.currentVideoPosition] = self.currentlyPlayingVideo!
        }
        catch ComScoreAnalyticsTracker.ComscoreError.InitializationNotDone {
            INFLogger.error("Comscore initialization not done")
        }
        catch INFPlaybackError.PlayerNotInitialized(let attributes){
            INFLogger.error("\(attributes.Code)")
            INFLogger.error(attributes.Domain)
            INFLogger.error(attributes.Description)
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch{
            INFLogger.error("Unknown Error : pauseEvent")
            throw INFError.errorWithCode(INFError.PlaybackErrorCode.PlayerUnknownError.rawValue, failureReason: "Error Not Known")
        }
    }
    
    public func stopEvent() throws {
        do{
            try self.videoPlayer!.stop()
            //self.currentlyPlayingVideo?.videoCurrentTime = currentTime
            //self.currentPlaylist?[self.currentVideoPosition] = self.currentlyPlayingVideo!
            self.videoPlayer!.setupContentPlayer(videoData: self.currentPlaylistItem,
                videoPlayerFrame: CGRect(x: 0, y: 0,
                    width: (self.playerConfigurations?.playerWidth)!,
                    height: (self.playerConfigurations?.playerHeight)!), userInfo: nil, eventType : INFVideoPlayerView.SetContentPlayerEvent.STOP_EVENT)
            
        }
        catch INFPlaybackError.PlayerNotInitialized(let attributes){
            print(attributes.Code)
            print(attributes.Domain)
            print(attributes.Description)
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch INFPlaybackError.StopFailed(let attributes)
        {
            INFLogger.error("Play back error stop failed")
            throw INFError.errorWithCode(attributes.Code, failureReason: attributes.Description)
        }
        catch{
            INFLogger.error("Unknown Error")
            throw INFError.errorWithCode(INFError.PlaybackErrorCode.PlayerUnknownError.rawValue, failureReason: "Error Not Known")
        }
    }
    
    //MARK: Method to create a fully qualified URL
    /**
    Creates the fully qualified URL for the LPS Service Response by list of pre-defined BASE PATH URLs
    - Parameter jsonResponse: value received in the Web Service Response
    - Parameter assetType: Type of asset, so as to append corresponding URL
    - Parameter isHTTPS: If HTTPS URLs are required, set it to true else false
    - Return JSONResponse: Edited JSON Response with Fully Qualified URL(s)
    
    */
    private func baseURLs()->Dictionary<String, [String]>{
        var baseURLs = Dictionary<String, [String]>()
        
        baseURLs[KeysValueToModify.ProducerLogo.rawValue] = ["http://assets.newsinc.com","https://assets-s.newsinc.com"]
        baseURLs[AssetType.StillFrame.rawValue] = ["http://content-img.newsinc.com","https://content-img-s.newsinc.com"]
        baseURLs[AssetType.Thumbnail.rawValue] = ["http://content-img.newsinc.com","https://content-img-s.newsinc.com"]
        baseURLs[AssetType.Video_mp4.rawValue] = ["http://content-mp4.newsinc.com","https://content-s.newsinc.com"]
        baseURLs[AssetType.Application_xmpeg.rawValue] = ["http://ndn_mp4-vh.akamaihd.net","https://ndn_mp4-vh.akamaihd.net"]
        baseURLs[AssetType.Application_xmpegURL.rawValue] = ["http://ndnmedia-vh.akamaihd.net","https://ndnmedia-vh.akamaihd.net"]
        baseURLs[AssetType.Video_f4m.rawValue] = ["http://ndnmedia-vh.akamaihd.net","https://ndnmedia-vh.akamaihd.net"]
        baseURLs[AssetType.Video_xflv.rawValue] = ["rtmp://cp98516.edgefcs.net","rtmp://cp98516.edgefcs.net"]
        baseURLs[AssetType.Video_progressive.rawValue] = ["http://ndnmedia-a.akamaihd.net", "https://ndnmedia-a.akamaihd.net"]
        
        return baseURLs
    }
    
    /**
     Creates the fully qualified URL for the LPS Service Response by list of pre-defined BASE PATH URLs
     - Parameter jsonResponse: value received in the Web Service Response
     - Parameter isHTTPS: If HTTPS URLs are required, set it to true else false
     - Return JSONResponse: Edited JSON Response with Fully Qualified URL(s)
     
     */
    private func assetBaseURL(jsonResponse:Dictionary<String, AnyObject>, isHTTPS:Bool) -> AnyObject?{
        let baseUrls = baseURLs()
        var jsonWithBaseURL = Dictionary<String, AnyObject>()
        for (key, value) in jsonResponse{
            if value is String{
                var newValue = (value as! String)
                switch key
                {
                case KeysValueToModify.LogoURL43.rawValue:
                    newValue = (isHTTPS ? baseUrls[KeysValueToModify.ProducerLogo.rawValue]![1]
                        :  baseUrls[KeysValueToModify.ProducerLogo.rawValue]![0]) + (value as! String)
                    break
                case KeysValueToModify.LogoURL169.rawValue:
                    newValue = (isHTTPS ? baseUrls[KeysValueToModify.ProducerLogo.rawValue]![1]
                        : baseUrls[KeysValueToModify.ProducerLogo.rawValue]![0]) + (value as! String)
                    break
                default:
                    break
                }
                jsonWithBaseURL[key] = newValue
            }
            else if key == KeysValueToModify.Playlists.rawValue{
                let newValue = value as! [AnyObject]
                jsonWithBaseURL[key] = playlistWithURL(newValue, isHTTPS: isHTTPS, baseUrls: baseUrls)
                //jsonWithBaseURL[key] = newValue
            }
            else{
                jsonWithBaseURL[key] = value
            }
            
            
            
        }
        
        return jsonWithBaseURL
    }
    
    /**
     Creates the fully qualified URL for the Playlists inside LPS Service Response by list of pre-defined BASE PATH URLs
     - Parameter jsonResponse: value received in the Web Service Response
     - Parameter isHTTPS: If HTTPS URLs are required, set it to true else false
     - Return Playlists: Array of Playlist with modified URL(s), contianing Contents & Assets
     
     */
    private func playlistWithURL( playlists: [AnyObject], isHTTPS:Bool, baseUrls:Dictionary<String, [String]>) -> [Dictionary<String, AnyObject>]
    {
        var playlistsWithModifiedURL = [Dictionary<String, AnyObject>]()
        var playbackDataWithModifiedURL = Dictionary<String, AnyObject>()
        for playbackData in playlists{
            for (key, value) in playbackData as! Dictionary<String, AnyObject>{
                if key == KeysValueToModify.Contents.rawValue{
                    print("Contents  ", value)
                    var arrayOfContents = [Dictionary<String, AnyObject>]()
                    var singleContentWithModifiedURL = Dictionary<String, AnyObject>()
                    for singleContent in value as! [Dictionary<String, AnyObject>]{
                        for (key, value) in singleContent {
                            if KeysValueToModify.Assets.rawValue == key{
                                singleContentWithModifiedURL[KeysValueToModify.Assets.rawValue] =
                                    self.assetsWithURL(value as! [Dictionary<String, AnyObject>], isHTTPS: isHTTPS)
                            }
                            else if key == KeysValueToModify.ProducerLogo.rawValue{
                                singleContentWithModifiedURL[KeysValueToModify.ProducerLogo.rawValue] =
                                    (isHTTPS ? baseUrls[KeysValueToModify.ProducerLogo.rawValue]![1]
                                        :  baseUrls[KeysValueToModify.ProducerLogo.rawValue]![0]) + (value as! String)
                            }
                            else{
                                singleContentWithModifiedURL[key] = value
                            }
                        }
                        arrayOfContents.append(singleContentWithModifiedURL)
                    }
                    playbackDataWithModifiedURL[key] = arrayOfContents
                }
                else{
                    playbackDataWithModifiedURL[key] = value
                }
            }
            playlistsWithModifiedURL.append(playbackDataWithModifiedURL)
        }
        
        return playlistsWithModifiedURL
    }
    /**
     Creates the fully qualified URL for the Assets inside LPS Service Response by list of pre-defined BASE PATH URLs
     - Parameter assetes: value received in the Web Service Response
     - Parameter assetType: Type of asset, so as to append corresponding URL
     - Parameter isHTTPS: If HTTPS URLs are required, set it to true else false
     - Return Assets: Array of Asset with modified URL(s), based on the AssetMimeType & AssetType
     
     */
    private func assetsWithURL(assets:[Dictionary<String, AnyObject>], isHTTPS:Bool) -> [Dictionary<String, AnyObject>]{
        let baseUrls = baseURLs()
        var assetsWithModifiedURL = [Dictionary<String, AnyObject>]()
        
        for asset in assets{
            var assetWithModifiedURL = Dictionary<String, AnyObject>()
            
            // Fill existing asset locations
            for (key, value) in asset {
                if key == KeysValueToModify.AssetLocation.rawValue{
                    assetWithModifiedURL[key] = value
                }
            }
            
            // Append base url to existing assets location
            for (key, value) in asset
            {
                if key == KeysValueToModify.AssetMimeType.rawValue {
                    switch value as! String{
                    case AssetType.Video_f4m.rawValue:
                        var location = assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] as! String
                        location = (isHTTPS ? baseUrls[AssetType.Video_f4m.rawValue]![1]
                            :  baseUrls[AssetType.Video_f4m.rawValue]![0]) + location
                        assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] = location
                        break
                    case AssetType.Application_xmpeg.rawValue:
                        var location = assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] as! String
                        location = (isHTTPS ? baseUrls[AssetType.Application_xmpeg.rawValue]![1]
                            :  baseUrls[AssetType.Application_xmpeg.rawValue]![0]) + location
                        assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] = location
                        break
                    case AssetType.Application_xmpegURL.rawValue:
                        var location = assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] as! String
                        location = (isHTTPS ? baseUrls[AssetType.Application_xmpegURL.rawValue]![1]
                            :  baseUrls[AssetType.Application_xmpegURL.rawValue]![0]) + location
                        assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] = location
                        break
                    case AssetType.Video_mp4.rawValue:
                        var location = assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] as! String
                        location = (isHTTPS ? baseUrls[AssetType.Video_mp4.rawValue]![1]
                            :  baseUrls[AssetType.Video_mp4.rawValue]![0]) + location
                        assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] = location
                        break
                    case AssetType.Video_progressive.rawValue:
                        var location = assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] as! String
                        location = (isHTTPS ? baseUrls[AssetType.Video_mp4.rawValue]![1]
                            :  baseUrls[AssetType.Video_mp4.rawValue]![0]) + location
                        assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] = location
                        break
                        
                    case AssetType.Video_xflv.rawValue:
                        var location = assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] as! String
                        location = (isHTTPS ? baseUrls[AssetType.Video_mp4.rawValue]![1]
                            :  baseUrls[AssetType.Video_mp4.rawValue]![0]) + location
                        assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] = location
                        break
                        
                    default:
                        if asset[KeysValueToModify.AssetType.rawValue] as! String == AssetType.StillFrame.rawValue{
                            var location = assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] as! String
                            location = (isHTTPS ? baseUrls[AssetType.StillFrame.rawValue]![1]
                                :  baseUrls[AssetType.StillFrame.rawValue]![0]) + location
                            assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] = location
                        }
                        if asset[KeysValueToModify.AssetType.rawValue] as! String == AssetType.StillFrameXL.rawValue{
                            var location = assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] as! String
                            location = (isHTTPS ? baseUrls[AssetType.StillFrame.rawValue]![1]
                                :  baseUrls[AssetType.StillFrame.rawValue]![0]) + location
                            assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] = location
                        }
                        if asset[KeysValueToModify.AssetType.rawValue] as! String == AssetType.Thumbnail.rawValue{
                            var location = assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] as! String
                            location = (isHTTPS ? baseUrls[AssetType.StillFrame.rawValue]![1]
                                :  baseUrls[AssetType.StillFrame.rawValue]![0]) + location
                            assetWithModifiedURL[KeysValueToModify.AssetLocation.rawValue] = location
                        }
                        break
                    }
                    assetWithModifiedURL[key] = value
                }
                else if key != KeysValueToModify.AssetLocation.rawValue {
                    assetWithModifiedURL[key] = value
                }
            }
            assetsWithModifiedURL.append(assetWithModifiedURL)
        }
        
        return assetsWithModifiedURL
    }
    
    internal func address(address articleAddress : String){
        self.addressOfArticle = articleAddress
    }
    
    deinit{
        self.sessionProviderDelegate = nil
        INFLogger.info("Session Provider removed")
    }
}