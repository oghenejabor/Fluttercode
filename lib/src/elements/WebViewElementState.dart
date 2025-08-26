import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

//import 'package:android_path_provider/android_path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

//flutter_downloader
//import 'package:flutter_downloader/flutter_downloader.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flyweb/i18n/i18n.dart';
import 'package:flyweb/src/elements/Loader.dart';
import 'package:flyweb/src/elements/WebViewElement.dart';
import 'package:flyweb/src/enum/connectivity_status.dart';
import 'package:flyweb/src/helpers/AdMobService.dart';
import 'package:flyweb/src/helpers/HexColor.dart';
import 'package:flyweb/src/models/setting.dart';
import 'package:flyweb/src/pages/OfflineScreen.dart';
import 'package:flyweb/src/position/PositionOptions.dart';
import 'package:flyweb/src/position/PositionResponse.dart';
import 'package:flyweb/src/services/theme_manager.dart';

//import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

//import 'package:location/location.dart' as Location hide LocationAccuracy;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

//import 'package:location/location.dart' hide LocationAccuracy;
//import 'package:store_redirect/store_redirect.dart';

class WebViewElementState extends State<WebViewElement>
    with AutomaticKeepAliveClientMixin<WebViewElement>, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;
  final ChromeSafariBrowser browser = new MyChromeSafariBrowser();

  //final GlobalKey webViewKey = GlobalKey();

  InAppWebViewController? webViewController;
  bool isLoading = true;
  String url = "";
  late PullToRefreshController pullToRefreshController;
  double progress = 0;
  final urlController = TextEditingController();

  // TODO: Add _bannerAd
  BannerAd? _bannerAd;

  bool isWasConnectionLoss = false;
  bool mIsPermissionGrant = false;
  bool mIsLocationPermissionGrant = false;

  late var _localPath;
  ReceivePort _port = ReceivePort();

  final Set<Factory<OneSequenceGestureRecognizer>> _gSet = [
    Factory<VerticalDragGestureRecognizer>(
        () => VerticalDragGestureRecognizer()),
    Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
    Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
  ].toSet();

  @override
  void initState() {
    super.initState();

    _getUserAgent();

    _bindBackgroundIsolate();

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: Colors.blue,
      ),
      onRefresh: () async {
        if (Platform.isAndroid) {
          webViewController?.reload();
        } else if (Platform.isIOS) {
          webViewController?.loadUrl(
              urlRequest: URLRequest(url: await webViewController?.getUrl()));
        }
      },
    );

    if (Setting.getValue(widget.settings.setting!, "ad_banner") == "true") {
      String bannerAdUnitId = Platform.isAndroid
          ? Setting.getValue(widget.settings.setting!, "admob_key_ad_banner")
          : Setting.getValue(
              widget.settings.setting!, "admob_key_ad_banner_ios");

      BannerAd(
        adUnitId: bannerAdUnitId,
        request: AdRequest(),
        size: AdSize.banner,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            setState(() {
              _bannerAd = ad as BannerAd;
            });
          },
          onAdFailedToLoad: (ad, err) {
            print('Failed to load a banner ad: ${err.message}');
            ad.dispose();
          },
        ),
      ).load();
    }

    if (Setting.getValue(widget.settings.setting!, "ad_interstitial") ==
        "true") {
      String adInterstitialId = Platform.isAndroid
          ? Setting.getValue(
              widget.settings.setting!, "admob_key_ad_interstitial")
          : Setting.getValue(
              widget.settings.setting!, "admob_key_ad_interstitial_ios");

      AdMobService.interstitialAdId = adInterstitialId;

      AdMobService.createInterstitialAd();

      Timer.periodic(
          new Duration(
              seconds: int.parse(
                  Setting.getValue(widget.settings.setting!, "admob_dealy"))),
          (timer) {
        AdMobService.showInterstitialAd();
      });
    }
  }

  Future<void> _getUserAgent() async {
    final defaultUserAgent = await InAppWebViewController.getDefaultUserAgent();
    print("Default User Agent: $defaultUserAgent ");
  }

  void _bindBackgroundIsolate() {
    bool isSuccess = IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    if (!isSuccess) {
      _unbindBackgroundIsolate();
      _bindBackgroundIsolate();
      return;
    }
  }

  @override
  void dispose() {
    _unbindBackgroundIsolate();
    super.dispose();
  }

  void _unbindBackgroundIsolate() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }

  bool contains(List<String> list, String item) {
    for (String i in list) {
      if (item.contains(i)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    var themeProvider = Provider.of<ThemeNotifier>(context);

    var connectionStatus = Provider.of<ConnectivityStatus>(context);
    if (connectionStatus == ConnectivityStatus.Offline)
      return OfflineScreen(settings: widget.settings);

    InAppWebViewSettings settings = InAppWebViewSettings(
      clearCache: true,
      useHybridComposition: false,
      geolocationEnabled: true,
      supportZoom: false,
      useShouldOverrideUrlLoading: true,
      useOnDownloadStart: true,
      mediaPlaybackRequiresUserGesture: false,
      cacheEnabled: true,
      allowFileAccess: true,
      allowContentAccess: true,
      userAgent: Platform.isAndroid
          ? widget.userAgent!.valueAndroid!
          : widget.userAgent!.valueIOS!,
      allowsInlineMediaPlayback: true,

      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      cacheMode: CacheMode.LOAD_CACHE_ELSE_NETWORK,
      allowsBackForwardNavigationGestures: true,
      isInspectable: true,
      //WebRTC
      iframeAllow: "camera; microphone",
      // for camera and microphone permissions
      iframeAllowFullscreen: true, // if you need fullscreen support
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Column(children: [
          Expanded(
              child: InAppWebView(
                  initialSettings: settings,
                  initialUrlRequest:
                      URLRequest(url: WebUri(widget.initialUrl!)),
                  //onCreateWindow: _onCreateWindow,
                  gestureRecognizers: _gSet,
                  onGeolocationPermissionsShowPrompt:
                      (InAppWebViewController controller, String origin) async {
                    await Permission.location.request();
                    return Future.value(GeolocationPermissionShowPromptResponse(
                        origin: origin, allow: true, retain: true));
                  },
                  pullToRefreshController: widget.pullRefresh == "true"
                      ? pullToRefreshController
                      : null,
                  onLoadStart: (controller, url) {
                    setState(() {
                      this.url = url.toString();
                      isLoading = true;
                    });
                  },
                  onLoadStop: (controller, url) async {
                    pullToRefreshController.endRefreshing();

                    /** CSS and Javascript */
                    webViewController!.injectCSSCode(source: widget.customCss!);
                    webViewController!
                        .evaluateJavascript(source: widget.customJavascript!);

                    this.setState(() {
                      this.url = url.toString();
                      isLoading = false;
                    });
                    if (widget.onLoadEnd != null) {
                      widget.onLoadEnd!();
                    }
                  },
                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                    var uri = navigationAction.request.url;
                    var url = navigationAction.request.url.toString();
                    if (Platform.isAndroid && url.contains("intent")) {
                      if (url.contains("maps")) {
                        var mNewURL = url.replaceAll("intent://", "https://");
                        if (await canLaunchUrl(Uri.parse(mNewURL))) {
                          await launchUrl(Uri.parse(mNewURL));
                          return NavigationActionPolicy.CANCEL;
                        }
                      } else {
                        String id = url.substring(
                            url.indexOf('id%3D') + 5, url.indexOf('#Intent'));
                        return NavigationActionPolicy.CANCEL;
                      }
                    } else if (contains(widget.nativeApplication!, url)) {
                      url = Uri.encodeFull(url);
                      try {
                        if (await canLaunchUrl(Uri.parse(url))) {
                          launchUrl(Uri.parse(url),
                              mode: LaunchMode.externalApplication);
                        } else {
                          launchUrl(Uri.parse(url),
                              mode: LaunchMode.externalApplication);
                        }
                        return NavigationActionPolicy.CANCEL;
                      } catch (e) {
                        launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication);
                        return NavigationActionPolicy.CANCEL;
                      }
                    } else if (![
                      "http",
                      "https",
                      "chrome",
                      "data",
                      "javascript",
                      "about"
                    ].contains(uri!.scheme)) {
                      if (await canLaunchUrl(Uri.parse(url))) {
                        await launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication);
                        return NavigationActionPolicy.CANCEL;
                      }
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  /* shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                    //return NavigationActionPolicy.ALLOW;
                    var uri = navigationAction.request.url;
                    var url = navigationAction.request.url.toString();
                    print("URL" + url.toString());

                    if (Platform.isAndroid && url.contains("intent")) {
                      if (url.contains("maps")) {
                        var mNewURL = url.replaceAll("intent://", "https://");
                        if (await canLaunchUrl(Uri.parse(mNewURL))) {
                          await launchUrl(Uri.parse(mNewURL), mode: LaunchMode.externalApplication);
                          return NavigationActionPolicy.CANCEL;
                        }
                      } else {
                        String id = url.substring(
                            url.indexOf('id%3D') + 5, url.indexOf('#Intent'));
                        print(id);
                        //await StoreRedirect.redirect(androidAppId: id);
                        return NavigationActionPolicy.CANCEL;
                      }
                    } else if (contains(widget.nativeApplication!, url)) {
                      print('url');
                      //print(url);
                      //url = Uri.encodeFull(url);
                      try {
                        if (await canLaunchUrl(Uri.parse(url))) {
                          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        } else {
                          throw 'Could not launch $url';
                        }
                        return NavigationActionPolicy.CANCEL;
                      } catch (e) {
                        //launchUrl(Uri.parse(url!));
                        return NavigationActionPolicy.CANCEL;
                      }
                    } else if (![
                      "http",
                      "https",
                      "chrome",
                      "data",
                      "javascript",
                      "about"
                    ].contains(uri!.scheme)) {
                      if (await canLaunchUrl(Uri.parse(url!))) {
                        await launchUrl(Uri.parse(url!));
                        return NavigationActionPolicy.CANCEL;
                      }
                    }
                    return NavigationActionPolicy.ALLOW;
                  },*/
                  onDownloadStartRequest: (controller, url) async {
                    //flutter_downloader

                    await browser.open(
                        url: WebUri(url.url.toString()),
                        settings: ChromeSafariBrowserSettings(
                            shareState: CustomTabsShareState.SHARE_STATE_ON,
                            barCollapsingEnabled: true));

                    setState(() {
                      isLoading = false;
                    });
                  },
                  onReceivedError: (controller, request, error) {
                    pullToRefreshController?.endRefreshing();
                  },
                  onProgressChanged: (controller, progress) {
                    if (progress == 100) {
                      pullToRefreshController.endRefreshing();
                    }
                  },
                  onUpdateVisitedHistory: (controller, url, androidIsReload) {
                    setState(() {
                      this.url = url.toString();
                    });
                  },
                  onConsoleMessage: (controller, consoleMessage) {
                    print(consoleMessage);
                  },
                  onPermissionRequest: (InAppWebViewController controller,
                      PermissionRequest request) async {
                    List resources = request.resources;
                    if (resources.length >= 1) {
                    } else {
                      resources.forEach((element) async {
                        if (element.contains("AUDIO_CAPTURE")) {
                          await Permission.microphone.request();
                        }
                        if (element.contains("VIDEO_CAPTURE")) {
                          await Permission.camera.request();
                        }
                      });
                    }
                    return PermissionResponse(
                        resources: request.resources,
                        action: PermissionResponseAction.GRANT);
                  },
                  onWebViewCreated: (InAppWebViewController controller) {
                    webViewController = controller;
                  })),
          if (_bannerAd != null)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            ),
        ]),
        (isLoading && widget.loader != "empty")
            ? Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                left: 0,
                child: Loader(
                    type: widget.loader!,
                    color: themeProvider.isLightTheme
                        ? HexColor(widget.loaderColor!)
                        : themeProvider.darkTheme.primaryColor))
            : Container()
      ],
    );
  }

  int? parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;

    return int.tryParse(value) ?? null;
  }

  Future<bool?> goBack() async {
    if (webViewController != null) {
      if (await webViewController!.canGoBack()) {
        webViewController!.goBack();
        return false;
      } else {
        return showDialog(
          context: context,
          builder: (context) => new AlertDialog(
            title: new Text(I18n.current!.closeApp),
            content: new Text(I18n.current!.sureCloseApp),
            actions: <Widget>[
              new TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: new Text(I18n.current!.cancel),
              ),
              SizedBox(height: 16),
              new TextButton(
                onPressed: () => exit(0),
                child: new Text(I18n.current!.ok),
              ),
            ],
          ),
        );
      }
    }
    return false;
  }

  void reloadWebView(url) {
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<bool?> _onCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction createWindowAction,
  ) async {
    return false;
  }
}

class MyChromeSafariBrowser extends ChromeSafariBrowser {
  @override
  void onOpened() {
    print("ChromeSafari browser opened");
  }

  @override
  void onClosed() {
    print("ChromeSafari browser closed");
  }
}
