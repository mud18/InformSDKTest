//
//  INFPlaybackController.swift
//  TestFrameworkNew
//
//  Created by Mudit on 11/12/15.
//  Copyright © 2015 INFORM. All rights reserved.
//

import Foundation
import UIKit
import MBProgressHUD
import MediaPlayer

/**
 Attributes obtained in the div tag
 - DivClass: class Attribute. The "ndn_embed" class must be present in
 order to indicate that this element embeds an NDN product
 - DivId: id attribute. It has been added to the two video player
 products in order to distinguish and identify them
 - DataConfigDistributorId: (optional)The distributor database id
 provided to a partner that distributes our videos on their website.
 - Style: Provides Height & Width of the player
 - DataConfigHeight: may contain "w" variable to dynamically
 calculate the height based on the configurable <div> element's width
 - DataConfigType: The type of NDN product being embedded. To be ignored for iOS Native SDK
 - DataConfigTrackingGroup: This setting is required and identifies the distribution partner
 - VideoId: Attribute to fetch Video Id
 
 */

private enum DivAttributes:String{
    case DivClass = "class"
    case DivId = "id"
    case DataConfigDistributorId = "data-config-distributor-id"
    case Style = "style"
    case DataConfigHeight = "data-config-height"
    case DataConfigWidgetId = "data-config-widget-id"
    case DataConfigType = "data-config-type"
    case DataConfigTrackingGroup = "data-config-tracking-group"
    case VideoId = "videoId"
}

private enum IFrameAttributes : String {
    case VideoId = "videoId"
    case Source = "src"
    case PlayerType = "type"
    case WidgetId = "widgetId"
    case TrackingGroup = "trackingGroup"
    case TrackingGroupId = "TrackingGroupId"
    case Freewheel = "freewheel"
    case SiteSection = "siteSection"
    case Width = "width"
    case Height = "height"
}

////🎬 Playback Controller is responsible for parsing div tag, and providing video player to the application classes

@objc public class INFPlaybackController: NSObject, NSXMLParserDelegate, INFSessionProviderDelegate {
    
    private var parser = NSXMLParser()
    //Values to verify data Validity
    private var isTagCorrect = false
    private var isInvalidConfigurations = false
    private var isInvalidDimensions = false
    private var isInvalidWidgetId = false
    private var isInvalidTrackingGroupId = false
    //Default Error object
    private var errorInDiv = INFPlaybackControllerError.NoError
    //Default DIV Tag Values
    
    private var isDimensionInPixel = false
    lazy var playerConfigurations = INFPlayerConfigurations()
    //Custom View which will be shown on widget
    lazy var viewWithVideo = UIView()
    private var addressOfArticle : String?
    
    var mainView : INFVideoView?
    
    public var playbackControllerid:Int32!
    
    lazy var sessionProvider = INFSessionsProvider()
    //Minimum Threshold Height & Width
    private let thresholdWidth = 50
    private let thresholdHeight = 20
    
    private lazy var progressBar = MBProgressHUD()
    
    private var requestController : INFRequestController
    
    private var pageID : INFID? = nil;
    
    private var furl : String?
    private var embedCount : Int32?
    private var eo : String?
    private var isLoadedFromIFrame : Bool
    private var referer : String
    private var tagWithSetting : String?
    private var webpageURL : String?
    
    private var informAnalyticsTracker : INFAnalyticsTracker?
    
    internal init(let referer : String, widgetID playbackControllerId:Int32,
        isLoadedFromIFrame : Bool, webpageURL : String, userInfo : Dictionary<String, AnyObject>?) {
            
            self.isLoadedFromIFrame = isLoadedFromIFrame
            self.playbackControllerid = playbackControllerId
            self.requestController = INFRequestController()
            self.referer = referer
            self.webpageURL = webpageURL
            guard let _ = userInfo
                else{
                    return
            }
            self.addressOfArticle = userInfo!["addressOfArticle"] as? String
    }
    
    /**
     Initialize Widget Settings from the div tag
     
     - Parameter tag: Div tag obtained as an string from HTML
     
     - Throws: INFPlaybackControllerError (if any)
     */
    
    internal func initWidgetSettingsFromDiv(tagWithSettings tag:String) throws
    {
        self.tagWithSetting = tag
        self.sessionProvider.address(address: self.addressOfArticle!)
        NSNotificationCenter.defaultCenter().removeObserver(self)
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: Selector("readyToPlay:"), name: INFSDKNotifications.INFPlayerNewAccessLogs.rawValue,
            object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: Selector("stopPlayback:"), name: INFSDKNotifications.INFPlaybackEnd.rawValue,
            object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: Selector("startPlaybackButton:"), name: INFSDKNotifications.INFPlaybackStart.rawValue,
            object: nil)
        //Implementing NSXMLParser to parse the div tag
        parser = NSXMLParser(data: tag.dataUsingEncoding(NSUTF8StringEncoding)!)
        parser.delegate = self
        //let success:Bool = parser.parse()
        parser.parse()
        
        //INFLogger.info("Div tag parsed successfully " + success.description)
        guard self.isTagCorrect else{
            throw INFPlaybackControllerError.InvalidDivTag
        }
        guard !self.isInvalidConfigurations else{
            throw INFPlaybackControllerError.InvalidPlayerConfigurations
        }
        guard !self.isInvalidDimensions else{
            throw INFPlaybackControllerError.InvalidPlayerDimensions
        }
        guard !self.isInvalidTrackingGroupId else{
            throw INFPlaybackControllerError.InvalidTrackingGroupId
        }
        guard !self.isInvalidWidgetId else{
            throw INFPlaybackControllerError.InvalidWidgetId
        }
        // Div tag is a valid div tag, Initialize main view (Widget holder view)
        mainView = INFVideoView(width: self.playerConfigurations.playerWidth, height: self.playerConfigurations.playerHeight)
        
        if let _ = mainView {
            mainView!.showLoading()
        }
        self.sessionProvider.sessionProviderDelegate = self
    }
    
    func initWidgetWithPageID(let pageID : INFID, furl : String, embedCount : Int32, eo : String) {
        self.pageID = pageID
        self.furl = furl
        self.embedCount = embedCount
        self.eo = eo
        
        self.informAnalyticsTracker = INFAnalyticsTracker(insID: pageID.getPageID(), uut: pageID.getUID())
        
        // send page load event
        
        let pageLoadEvent : INFPageLoadEvent = INFPageLoadEvent()
        
        var pageLoadEventDictionary : Dictionary<InformEvent.EventParam, Any> = Dictionary<InformEvent.EventParam, Any>()
        
        pageLoadEventDictionary[InformEvent.EventParam.VW] = Int32(self.playerConfigurations.playerWidth)
        pageLoadEventDictionary[InformEvent.EventParam.VH] = Int32(self.playerConfigurations.playerHeight)
        pageLoadEventDictionary[InformEvent.EventParam.SW] = INFUIUtilities.getScreenWidth()
        pageLoadEventDictionary[InformEvent.EventParam.SH] = INFUIUtilities.getScreenHeight()
        pageLoadEventDictionary[InformEvent.EventParam.FURL] = self.furl
        pageLoadEventDictionary[InformEvent.EventParam.UA] = INFHttpGateway.getUserAgent()
        pageLoadEventDictionary[InformEvent.EventParam.EMBED_COUNT] = self.embedCount
        pageLoadEventDictionary[InformEvent.EventParam.EO] = self.referer
        pageLoadEventDictionary[InformEvent.EventParam.IFRAME] = self.isLoadedFromIFrame
        pageLoadEventDictionary[InformEvent.EventParam.FE] = false
        pageLoadEventDictionary[InformEvent.EventParam.FV] = "0"
        
        if (DEBUG) {
            pageLoadEventDictionary[InformEvent.EventParam.ENV] = INFConstants.DEV
        } else {
            pageLoadEventDictionary[InformEvent.EventParam.ENV] = INFConstants.EMPTY
        }
        pageLoadEventDictionary[InformEvent.EventParam.BN] = Int32(InformSDKVersionNumber)
        pageLoadEventDictionary[InformEvent.EventParam.REF] = self.webpageURL!
        
        pageLoadEvent.setValues(pageLoadEventDictionary)
        if self.informAnalyticsTracker != nil {
            self.informAnalyticsTracker!.trackEvent(pageLoadEvent, requestController:self.requestController)
        }
        self.loadWidget(nil, completion: {(viewWithPlayer : UIView, isSuccess : Bool, userInfo : Dictionary<String, AnyObject>?, thumbnail : UIImage?) -> Void in
            
            if isSuccess && self.mainView != nil {
                
                self.mainView!.setPlayer(viewWithPlayer)
                
                self.mainView!.showVideoThumbnailView(thumbnail, playButtonClicked: {()
                    // Play Video
                    do {
                        //
                        self.mainView!.showVideoPlayer()
                        try self.sessionProvider.playVideo()
                        self.mainView!.hideLoading()
                    } catch INFPlaybackError.PlayerStatusUnkown(let attributes){
                        INFLogger.info(attributes.Description)
                        //                        self.mainView?.showLoading("Loading", message: "Buffering Video...")
                    }
                    catch{
                        
                    }
                    return nil
                })
                
            } else if let _ = self.mainView {
                self.mainView!.showError("Network error")
            }
        })
    }
    
    //MARK:NSXMLParser Delegates
    public func parser(parser: NSXMLParser,didStartElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String : String]){
            if elementName == INFConstants.DIVTAGNAME &&
                attributeDict.keys.contains(DivAttributes.DivClass.rawValue) &&
                attributeDict[DivAttributes.DivClass.rawValue] == INFConstants.DIVCLASSVALUE
            {
                self.isTagCorrect = true;
                //Creating a widget Configuration
                guard let playerConfig = widgetConfgurationDivTag(attributesOftag: attributeDict) else
                {
                    return
                }
                self.playerConfigurations = playerConfig
            } else if (elementName == INFConstants.IFRAMETAGNAME &&
                attributeDict.keys.contains(IFrameAttributes.Source.rawValue) &&
                validateIframeTag(attributeDict[IFrameAttributes.Source.rawValue]!))
            {
                self.isTagCorrect = true;
                //Creating a widget Configuration
                guard let playerConfig = widgetConfgurationIFrameTag(attributesOftag: attributeDict) else
                {
                    return
                }
                self.playerConfigurations = playerConfig
            }
    }
    
    public func parser(parser: NSXMLParser, didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?) {
            //Nothing to retreive at the end of div tag
    }
    
    public func parser(parser: NSXMLParser, foundCharacters string: String) {
        //Nothing to retrieve from current character
    }
    
    public func parser(parser: NSXMLParser, parseErrorOccurred parseError: NSError) {
        self.isInvalidConfigurations = true;
    }
    
    private func validateIframeTag(iframeTag : String) -> Bool {
        var iframeValue : Array<String>?
        
        if DEBUG {
            iframeValue = INFConstants.IFRAMETAGVALUES_DEV
        } else {
            iframeValue = INFConstants.IFRAMETAGVALUES_PROD
        }
        
        if iframeValue != nil {
            for value in iframeValue! {
                if(iframeTag.lowercaseString.rangeOfString(value.lowercaseString) != nil) {
                    return true
                }
            }
        }
        
        return false
    }
    
    //MARK:Div tag parsing methods
    /**
    Creates widget Configuration object after parsing the attributes obtained from the div tag
    
    - Parameter attributesDictionary: Div tag obtained as an string from HTML
    
    - Returns: INFPlayerConfigurations object i.e., settings of the video
    player obtained from the div tag
    */
    private func widgetConfgurationDivTag(attributesOftag attributesDictionary: [String:String]) -> INFPlayerConfigurations?{
        let playerConfig = INFPlayerConfigurations()
        guard let _ = attributesDictionary[DivAttributes.DataConfigTrackingGroup.rawValue]
            else{
                self.isInvalidTrackingGroupId = true
                return nil
        }
        //TODO: Check for duplicate widget ID for same page, using Page instance ID Concept
        for (key, value) in attributesDictionary{ //Parsing attributes of div tag
            if key == DivAttributes.Style.rawValue{ //Obtaining Height & Width from Style Attributes
                let style = extractHeightWidthFromString(styleAttribute: value)
                if !style.isEmpty
                {
                    guard let _ = style["properties"]
                        //,
                        //let _ = attributesDictionary[DivAttributes.DataConfigType.rawValue]
                        else
                    {
                        //TODO: Add parsing for data-config-type
                        //return nil
                        break
                    }
                    
                    let properties = style["properties"]
                    
                    guard properties!.contains("width")
                        else{
                            self.isInvalidConfigurations = true
                            //return nil
                            break
                    }
                    guard properties!.contains("height")
                        else{
                            self.isInvalidConfigurations = true
                            //return nil
                            break
                    }
                    
                    var width : Int? = 0
                    var height : Int? = 0
                    
                    for (index, value) in style["properties"]!.enumerate()
                    {
                        if value=="width"
                        {
                            if Int(style["propertyValues"]![index]) > self.thresholdWidth{
                                width = Int(style["propertyValues"]![index])
                            }
                            else{
                                self.isInvalidDimensions = true
                                break
                            }
                        }
                        if value=="height"
                        {
                            if Int(style["propertyValues"]![index]) > self.thresholdHeight{
                                height = Int(style["propertyValues"]![index])
                            }
                            else{
                                self.isInvalidDimensions = true
                                break
                            }
                        }
                    }
                    
                    if !isInvalidDimensions {
                        let screenWidth : Int = Int(INFUIUtilities.getScreenWidth()) - (INFConstants.WIDTH_MARGIN * 2)
                        let screenHeight : Int = Int(INFUIUtilities.getScreenHeight())
                        
                        // If player width dimensions is greater than screen width, then adjust player width to screen width and player height to be calculated on 16:9 ratio. (width:height)
                        
                        if width > screenWidth  || height > screenHeight {
                            playerConfig.playerWidth = screenWidth
                            
                            let relativeHeight = Int((screenWidth * 9) / 16)
                            playerConfig.playerHeight = relativeHeight
                            
                            playerConfig.isSizeRelative = true
                        } else {
                            playerConfig.playerWidth = width
                            playerConfig.playerHeight = height
                        }
                    }
                }
                else
                {
                    return nil
                }
                
            }
            if key == DivAttributes.DivId.rawValue
            {
                playerConfig.playerId = value
            }
            if key == DivAttributes.VideoId.rawValue{
                if value != "" && value != " " && !value.isEmpty && INFHelperClass.validateValueIsInt(value) {
                    playerConfig.videoId = Int32(value)
                }
            }
            if key == DivAttributes.DataConfigTrackingGroup.rawValue{
                if value != "" && value != " " && !value.isEmpty {
                    if INFHelperClass.validateValueIsInt(value){
                        playerConfig.dataTrackingGroupId = Int32(value)!
                    }
                    else {
                        self.isInvalidTrackingGroupId = true
                        return nil
                    }
                } else {
                    self.isInvalidTrackingGroupId = true
                    return nil
                }
            }
            if key == DivAttributes.DataConfigWidgetId.rawValue{
                if value != "" && value != " " && !value.isEmpty {
                    if INFHelperClass.validateValueIsInt(value){
                        playerConfig.dataConfigWidgetId = Int32(value)!
                    }else{
                        self.isInvalidWidgetId = true
                        return nil
                    }
                } else {
                    
                    self.isInvalidWidgetId = true
                    return nil
                }
            }
            if key == DivAttributes.DataConfigType.rawValue{
                playerConfig.playerType = value
                if value == "VideoLauncher/Slider300x250"
                {
                    playerConfig.playerWidth = 300
                    playerConfig.playerHeight = 250
                }
            }
            /* TODO: Indentify Invalid Configurations case here, if any and assign
            isInvalidConfigurations to throw appropriate error
            */
        }
        //Condition to handle Player Dimensions in Pixel
        if self.isDimensionInPixel
        {
            playerConfig.isDimensionInPixel = isDimensionInPixel
        }
        return playerConfig
    }
    
    
    
    //MARK IFrame tag parsing methods
    /**
    Creates widget Configuration object after parsing the attributes obtained from the iFrame tag
    
    - Parameter attributesDictionary: Div tag obtained as an string from HTML
    
    - Returns: INFPlayerConfigurations object i.e., settings of the video
    player obtained from the div tag
    */
    private func widgetConfgurationIFrameTag(attributesOftag attributesDictionary: [String:String]) -> INFPlayerConfigurations? {
        let playerConfig = INFPlayerConfigurations()
        
        // Extract tracking group
        let httpAddress : String? = attributesDictionary[IFrameAttributes.Source.rawValue]
        
        if httpAddress == nil || httpAddress!.isEmpty {
            self.isInvalidConfigurations = true
            return nil
        }
        
        let urlComponents = NSURLComponents(string: httpAddress!)
        let queryItems = urlComponents!.queryItems
        
        guard let trackingGroupID = self.getQueryStringParameter(queryItems, name: IFrameAttributes.TrackingGroupId.rawValue)
            else{
                self.isInvalidTrackingGroupId = true
                return nil
        }
        
        if !trackingGroupID.isEmpty && INFHelperClass.validateValueIsInt(trackingGroupID) {
            playerConfig.dataTrackingGroupId = Int32(trackingGroupID)!
        } else {
            self.isInvalidTrackingGroupId = true
            return nil
        }
        
        let widgetID = self.getQueryStringParameter(queryItems, name: IFrameAttributes.WidgetId.rawValue)
        if widgetID == nil {
            self.isInvalidWidgetId = true
            return nil
        }
        
        if INFHelperClass.validateValueIsInt(widgetID!) {
            playerConfig.dataConfigWidgetId = Int32(widgetID!)!
        }
        
        // Dimensions
        // First consider the width and height value from iframe attribute
        var width = attributesDictionary[IFrameAttributes.Width.rawValue]
        
        let newWidth = self.getQueryStringParameter(queryItems, name: IFrameAttributes.Width.rawValue)
        if newWidth != nil {
            // Overide width of iframe attribute by height from attribute in src
            width = newWidth
        }
        
        if width == nil {
            self.isInvalidDimensions = true
        } else {
            // check is value in pixel
            if (width!.containsString("px")){
                self.isDimensionInPixel = true
                // remove px from string
                width = width!.stringByReplacingOccurrencesOfString("px", withString: "")
            } else {
                self.isDimensionInPixel = false
            }
            if (INFHelperClass.validateValueIsInt(width!)) {
                playerConfig.playerWidth = Int(width!)
            } else {
                self.isInvalidDimensions = true
            }
        }
        
        var height = attributesDictionary[IFrameAttributes.Height.rawValue]
        
        let newHeight = self.getQueryStringParameter(queryItems, name: IFrameAttributes.Height.rawValue)
        
        if newHeight != nil {
            // Overide height of iframe attribute by height from attribute in src
            height = newHeight
        }
        
        if (height == nil) {
            self.isInvalidDimensions = true
        } else {
            // check is value in pixel
            if (height!.containsString("px")){
                self.isDimensionInPixel = true
                // remove px from string
                height = height!.stringByReplacingOccurrencesOfString("px", withString: "")
            } else {
                self.isDimensionInPixel = false
            }
            if (INFHelperClass.validateValueIsInt(height!)) {
                playerConfig.playerHeight = Int(height!)
            } else {
                self.isInvalidDimensions = true
            }
        }
        
        if !isInvalidDimensions {
            let screenWidth : Int = Int(INFUIUtilities.getScreenWidth()) - (INFConstants.WIDTH_MARGIN * 2)
            let screenHeight : Int = Int(INFUIUtilities.getScreenHeight())
            
            // If player width or height dimensions is greater than screen width or height, then adjust player width to screen width and player height to be calculated on 16:9 ratio (width:height)
            
            if playerConfig.playerWidth > screenWidth  || playerConfig.playerHeight > screenHeight {
                playerConfig.playerWidth = screenWidth
                
                let relativeHeight = Int((screenWidth * 9) / 16)
                playerConfig.playerHeight = relativeHeight
                
                playerConfig.isSizeRelative = true
            }
        }
        
        let videoID = self.getQueryStringParameter(queryItems, name: IFrameAttributes.VideoId.rawValue)
        if (videoID != nil && INFHelperClass.validateValueIsInt(videoID!)) {
            playerConfig.videoId = Int32(videoID!)
        }
        
        let siteSection = self.getQueryStringParameter(queryItems, name: IFrameAttributes.SiteSection.rawValue)
        if (siteSection != nil && INFHelperClass.validateValueIsInt(siteSection!)) {
            playerConfig.siteSection = siteSection
        }
        
        let type = self.getQueryStringParameter(queryItems, name: IFrameAttributes.PlayerType.rawValue)
        if (type != nil) {
            playerConfig.playerType = type!
        }
        
        playerConfig.isDimensionInPixel = self.isDimensionInPixel
        
        return playerConfig
    }
    
    func getQueryStringParameter(queryItems: [NSURLQueryItem]?, name: String) -> String? {
        if (queryItems == nil) {
            return nil
        }
        
        for (var i : Int = 0 ; i < queryItems!.count ; i++) {
            let queryItem : NSURLQueryItem? = queryItems![i]
            if (queryItem != nil && queryItem!.name == name) {
                return queryItem!.value
            }
        }
        
        return nil;
    }
    /**
     Creates dictionary after parsing the attributes obtained from the div tag
     
     - Parameter styleValue: String obtained from the style attribute,
     right now it is considered that only two sub attributes
     will be there in Style attributes i.e., Width & Height, others are not considered
     
     - Returns: Dictionary containing two keys - properties:["Width","Height"] &
     propertyValues["<respective value as mentioned in tag>",
     "<respective value as mentioned in tag>"].
     Right now both only % & px value is supported
     */
    private func extractHeightWidthFromString(styleAttribute styleValue:String)
        -> Dictionary<String, [String]>
    {
        var propertiesWithValues = Dictionary<String, [String]>()
        //Values are in %
        if styleValue.containsString("%"){
            //Fetching all the sub attributes name viz., Width, Height
            var property = styleValue.componentsSeparatedByCharactersInSet(NSCharacterSet.lowercaseLetterCharacterSet().invertedSet)
            let properties = INFHelperClass.removeElements(arrayWithEmptyElements:&property, elementToRemove: "")
            
            //Fetching respective values for the sub attributes
            var digits = styleValue.componentsSeparatedByCharactersInSet(NSCharacterSet.decimalDigitCharacterSet().invertedSet)
            let propertyValues = INFHelperClass.removeElements(arrayWithEmptyElements:&digits, elementToRemove: "")
            
            propertiesWithValues["properties"]=properties
            propertiesWithValues["propertyValues"]=propertyValues
            
        }
        else if styleValue.containsString("px"){
            //Values are in px
            self.isDimensionInPixel = true;
            //Fetching all the sub attributes name viz., Width, Height
            var property = styleValue.componentsSeparatedByCharactersInSet(NSCharacterSet.lowercaseLetterCharacterSet().invertedSet)
            let properties = INFHelperClass.removeElements(arrayWithEmptyElements:&property, elementToRemove: "px")
            propertiesWithValues["properties"]=properties
            
            //Fetching respective values for the sub attributes
            var digits = styleValue.componentsSeparatedByCharactersInSet(NSCharacterSet.decimalDigitCharacterSet().invertedSet)
            let propertyValues = INFHelperClass.removeElements(arrayWithEmptyElements:&digits, elementToRemove: "")
            propertiesWithValues["propertyValues"]=propertyValues
        }
        else{
            self.isInvalidConfigurations = true
        }
        return propertiesWithValues
    }
    
    
    //MARK:LifeCycle Events of Widget - Load & Unload
    /**
    Closure for Loads Widget Event, on calling it provides view with video.
    It also internally calls method for Web Services calling.
    - Returns: nil
    - Parameter userInfo: Optional dictionary for providing any required information
    - Parameter completion: Completion Handler provides viewWithPlayer, isSuccess, userInfo
    */
    public func loadWidget(userInfo:Dictionary<String, AnyObject>?,
        completion:(viewWithPlayer: UIView, isSuccess:Bool,
        userInfo:Dictionary<String, AnyObject>?, thumbnail : UIImage?)->Void){
            INFUIUtilities.progressIndicatorOnView(viewWithPlayer: self.viewWithVideo,
                progressBar: self.progressBar)
            
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), {
                
                self.sessionProvider.requestDataForWidget(self.referer, widgetConfigurations: self.playerConfigurations,
                    requestController: self.requestController, isQueryParamsRequired: false, widgetId:self.playbackControllerid,
                    pageInstanceID: (self.getID()?.getPageID())!, userID: (self.getID()?.getUID())!, userInfo: nil, informAnalyticsTracker : self.informAnalyticsTracker, widgetIndex: self.embedCount!, furl: self.furl!){
                        (sessionForVideoId:INFBaseClass?, isSuccess:Bool, error:NSError?, viewWithPlayer:UIView?) in
                        
                        if isSuccess {
                            if let _ = sessionForVideoId  {
                                //INFLogger.info("Response \(response)")
                                
                                // Make widget laod analytics call
                                let informWidgetLoadEvent : INFWidgetLoadEvent = INFWidgetLoadEvent()
                                
                                var widgetLoadEventDictionary = Dictionary<InformEvent.EventParam, Any>()
                                
                                widgetLoadEventDictionary[InformEvent.EventParam.EI] = self.embedCount
                                widgetLoadEventDictionary[InformEvent.EventParam.WID] = self.playerConfigurations.dataConfigWidgetId
                                if sessionForVideoId != nil && sessionForVideoId!.siteSectionName != nil {
                                    widgetLoadEventDictionary[InformEvent.EventParam.SSID] = (sessionForVideoId!.siteSectionName)!
                                }
                                widgetLoadEventDictionary[InformEvent.EventParam.ANID] = self.playerConfigurations.dataTrackingGroupId
                                widgetLoadEventDictionary[InformEvent.EventParam.FURL] = self.furl
                                widgetLoadEventDictionary[InformEvent.EventParam.VW] = Int32(self.playerConfigurations.playerWidth)
                                widgetLoadEventDictionary[InformEvent.EventParam.VH] = Int32(self.playerConfigurations.playerHeight)
                                widgetLoadEventDictionary[InformEvent.EventParam.SW] = INFUIUtilities.getScreenWidth()
                                widgetLoadEventDictionary[InformEvent.EventParam.SH] = INFUIUtilities.getScreenHeight()
                                widgetLoadEventDictionary[InformEvent.EventParam.FE] = false
                                widgetLoadEventDictionary[InformEvent.EventParam.FV] = "0"
                                // TODO : Analytics : View port visibility
                                widgetLoadEventDictionary[InformEvent.EventParam.V] = true
                                // {"widgetId":"30024","type":"VideoLauncher/Slider","trackingGroup":"92263"}
                                let configuration = "{\"widgetId\":\"\(self.playerConfigurations.dataConfigWidgetId)\",\"type\":\"\(self.playerConfigurations.playerType)\",\"trackingGroup\":\"\(self.playerConfigurations.dataTrackingGroupId)\"}"
                                widgetLoadEventDictionary[InformEvent.EventParam.PCNFG] = configuration
                                widgetLoadEventDictionary[InformEvent.EventParam.CDE] = self.tagWithSetting
                                widgetLoadEventDictionary[InformEvent.EventParam.IFRAME] = self.isLoadedFromIFrame
                                informWidgetLoadEvent.setValues(widgetLoadEventDictionary)
                                if self.informAnalyticsTracker != nil {
                                    self.informAnalyticsTracker!.trackEvent(informWidgetLoadEvent, requestController: self.requestController)
                                }
                                self.setThumbnail(viewWithPlayer, siteSectionName: sessionForVideoId!.siteSectionName, completion: completion)
                                
                            } else {
                                if let _ = self.mainView {
                                    self.mainView!.showError("Not able to fetch content")
                                }
                            }
                        }
                        else{
                            if error!.code == -100{
                                // ??
                                // completion(viewWithPlayer: self.viewWithVideo, isSuccess: false, userInfo: nil, thumbnail: nil)
                            }
                            if self.mainView != nil {
                                self.mainView!.showError("Not able to fetch content")
                            }
                        }
                }
                
                //TODO: Handle error scenerios once Error Handling is implemented in loadSession
            })
    }
    
    private func setThumbnail(viewWithPlayer:UIView?, siteSectionName: String?, completion:(viewWithPlayer: UIView, isSuccess:Bool,
        userInfo:Dictionary<String, AnyObject>?, thumbnail : UIImage?)->Void) {
            // Take out thumnail url
            
            let playlists : INFPlaylists? = sessionProvider.currentPlaylistItem
            
            if (playlists != nil && playlists!.contents != nil && playlists!.contents?.count > 0) {
                
                let content : INFContents? = playlists!.contents![0]
                
                let assets : Array<INFAssets>? = content!.assets
                
                if (assets != nil && assets!.count > 0) {
                    
                    var thumbnailAsset : INFAssets? = nil
                    
                    for (_, element) in assets!.enumerate() {
                        
                        if (element.assetType == AssetType.StillFrameXL.rawValue) {
                            thumbnailAsset = element
                            break;
                        }
                    }
                    
                    if (thumbnailAsset != nil) {
                        // thumbnail present
                        INFVideoThumbnailService().makeRequest(thumbnailAsset!.assetLocation!, completionHandler: { (callbackType : INFCallbackType?, anyObject : AnyObject?) -> INFRequestController? in
                            
                            switch (callbackType!) {
                            case .RequestSuccess:
                                
                                if (anyObject != nil && anyObject is UIImage) {
                                    // got thumbail
                                    self.viewWithVideo = viewWithPlayer!
                                    completion(viewWithPlayer: self.viewWithVideo, isSuccess: true, userInfo: nil, thumbnail: anyObject as? UIImage)
                                } else {
                                    // failed in fetching thumnail
                                    self.viewWithVideo = viewWithPlayer!
                                    completion(viewWithPlayer: self.viewWithVideo, isSuccess: true, userInfo: nil, thumbnail: nil)
                                }
                                
                                // got player configuration from player services and configuration completed
                                // Make config complete analytics call
                                let informConfigCompleteEvent : INFConfigCompleteEvent = INFConfigCompleteEvent()
                                
                                var configCompleteEventDictionary = Dictionary<InformEvent.EventParam, Any>()
                                
                                configCompleteEventDictionary[InformEvent.EventParam.EI] = self.embedCount
                                configCompleteEventDictionary[InformEvent.EventParam.WID] = self.playerConfigurations.dataConfigWidgetId
                                if siteSectionName != nil {
                                    configCompleteEventDictionary[InformEvent.EventParam.SSID] = siteSectionName!
                                }
                                configCompleteEventDictionary[InformEvent.EventParam.ANID] = self.playerConfigurations.dataTrackingGroupId
                                configCompleteEventDictionary[InformEvent.EventParam.FURL] = self.furl
                                configCompleteEventDictionary[InformEvent.EventParam.VW] = Int32(self.playerConfigurations.playerWidth)
                                configCompleteEventDictionary[InformEvent.EventParam.VH] = Int32(self.playerConfigurations.playerHeight)
                                configCompleteEventDictionary[InformEvent.EventParam.SW] = INFUIUtilities.getScreenWidth()
                                configCompleteEventDictionary[InformEvent.EventParam.SH] = INFUIUtilities.getScreenHeight()
                                configCompleteEventDictionary[InformEvent.EventParam.FURL] = self.furl
                                // TODO : Analytics : View port visibility
                                configCompleteEventDictionary[InformEvent.EventParam.V] = true
                                // {"widgetId":"30024","type":"VideoLauncher/Slider","trackingGroup":"92263"}
                                let configuration = "{\"widgetId\":\"\(self.playerConfigurations.dataConfigWidgetId)\",\"type\":\"\(self.playerConfigurations.playerType)\",\"trackingGroup\":\"\(self.playerConfigurations.dataTrackingGroupId)\"}"
                                configCompleteEventDictionary[InformEvent.EventParam.CNFG] = configuration
                                
                                // TODO : Player type id table is not defined as per kinesis concepts doc
                                configCompleteEventDictionary[InformEvent.EventParam.PLT] = 0
                                
                                informConfigCompleteEvent.setValues(configCompleteEventDictionary)
                                if self.informAnalyticsTracker != nil {
                                    self.informAnalyticsTracker!.trackEvent(informConfigCompleteEvent, requestController: self.requestController)
                                }
                                break
                                
                            case .RequestFailure:
                                // failed in fetching thumnail
                                if self.mainView != nil {
                                    self.mainView!.showError("Network error")
                                }
                                break
                                
                            case .RequestCancel:
                                // Request cancelled
                                if self.mainView != nil {
                                    self.mainView!.showError("Network issue")
                                }
                                break
                                
                            case .RequestSend:
                                break
                                
                            case .RequestComplete:
                                break
                                
                            default:
                                break
                            }
                            
                            return self.requestController
                        })
                        
                        // call service to fetch the thumbnail
                        
                    } else {
                        // no thumbnail present
                        self.viewWithVideo = viewWithPlayer!
                        completion(viewWithPlayer: self.viewWithVideo, isSuccess: true, userInfo: nil, thumbnail: nil)
                        
                    }
                } else {
                    self.viewWithVideo = viewWithPlayer!
                    completion(viewWithPlayer: self.viewWithVideo, isSuccess: true, userInfo: nil, thumbnail: nil)
                }
            } else {
                if self.mainView != nil {
                    self.mainView!.showError("Not able to fetch content")
                }
            }
    }
    
    
    
    public func getID() -> INFID? {
        return self.pageID
    }
    
    public func getView() -> UIView {
        return mainView!
    }
    
    public func showError(let error : String) {
        if self.mainView != nil {
            mainView!.showError(error);
        }
    }
    
    func readyToPlay(notification:NSNotification){
        let userInfo = notification.userInfo as? Dictionary<String, AnyObject>
        guard let playerItems = userInfo
            else{
                return
        }
        if let playerItem = playerItems["playerItem"] as? AVPlayerItem{
            if (self.sessionProvider.videoPlayer?.videoPlayerItem) == playerItem{
                INFLogger.info("Widget with id \(self.playbackControllerid) is ready")
                if let _ = mainView{
                    mainView?.hideLoading()
                    INFUIUtilities.hideActivityIndicator(mainView!.activityindicatorInstance())
                    guard ((mainView?.tapReceivedToPlay()) != false)
                        else{
                            mainView?.videoLoadStatus(true)
                            return
                    }
                    do
                    {
                        // TODO: Adding patch
                        if self.sessionProvider.videoPlayer != nil && (!self.sessionProvider.videoPlayer!.isFullScreen) {
                            self.mainView!.showVideoPlayer()
                        }
                        try self.sessionProvider.playVideo()
                    }
                    catch{
                        mainView?.showLoading(NSLocalizedString("Loading", tableName: "INFLocalizable",
                            bundle: NSBundle(forClass: INFPlaybackController.self), comment: "Loading message"),
                            message: NSLocalizedString("Error_Occurred", tableName: "INFLocalizable",
                                bundle: NSBundle(forClass: INFPlaybackController.self), comment: "Error message"))
                    }
                }
            }
        }
    }
    
    func stopPlayback(notification:NSNotification){
        let userInfo = notification.userInfo as? Dictionary<String, AnyObject>
        guard let playerItems = userInfo
            else{
                return
        }
        if let playerItem = playerItems["playerItem"] as? AVPlayerItem{
            if (self.sessionProvider.videoPlayer?.videoPlayerItem) == playerItem{
                INFLogger.info("Widget with id \(self.playbackControllerid) is ready")
                if let _ = mainView{
                    guard ((mainView?.tapReceivedToPlay()) != false)
                        else{
                            
                            return
                    }
                    mainView?.setTapReceiedToPlay(false)
                }
            }
        }
    }
    
    func startPlaybackButton(notification:NSNotification){
        let userInfo = notification.userInfo as? Dictionary<String, AnyObject>
        guard let playerItems = userInfo
            else{
                return
        }
        if let playerItem = playerItems["playerItem"] as? AVPlayerItem{
            if (self.sessionProvider.videoPlayer?.videoPlayerItem) == playerItem{
                INFLogger.info("Widget with id \(self.playbackControllerid) is ready")
                if let _ = mainView{
                    mainView?.setTapReceiedToPlay(true)
                    
                    INFUIUtilities.showActivityIndicator(mainView!,
                        activityIndicator: mainView!.activityindicatorInstance(), isIndicatorInsideSquare: false)
                }
            }
        }
    }

    public func playbackFailed() {
        if let _ = mainView {
            mainView!.showError("Playback failed")
        }
    }
    
    deinit{
        self.requestController.cancel()
        NSNotificationCenter.defaultCenter().removeObserver(self)
        INFLogger.info("Playback Controller with ID \(self.playbackControllerid) removed")
        INFLogger.info("Playback Controller with ID \(self.description) removed")
    }
}