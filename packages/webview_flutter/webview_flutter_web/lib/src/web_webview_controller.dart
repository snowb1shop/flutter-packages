// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:collection';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/cupertino.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'content_type.dart';
import 'http_request_factory.dart';

/// An implementation of [PlatformWebViewControllerCreationParams] using Flutter
/// for Web API.
@immutable
class WebWebViewControllerCreationParams
    extends PlatformWebViewControllerCreationParams {
  /// Creates a new [AndroidWebViewControllerCreationParams] instance.
  WebWebViewControllerCreationParams({
    @visibleForTesting this.httpRequestFactory = const HttpRequestFactory(),
  }) : super();

  /// Creates a [WebWebViewControllerCreationParams] instance based on [PlatformWebViewControllerCreationParams].
  WebWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
    // Recommended placeholder to prevent being broken by platform interface.
    // ignore: avoid_unused_constructor_parameters
    PlatformWebViewControllerCreationParams params, {
    @visibleForTesting
    HttpRequestFactory httpRequestFactory = const HttpRequestFactory(),
  }) : this(httpRequestFactory: httpRequestFactory);

  static int _nextIFrameId = 0;

  /// Handles creating and sending URL requests.
  final HttpRequestFactory httpRequestFactory;

  /// The underlying element used as the WebView.
  @visibleForTesting
  final html.IFrameElement iFrame = html.IFrameElement()
    ..id = 'webView${_nextIFrameId++}'
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.border = 'none';
}

/// An implementation of [PlatformWebViewController] using Flutter for Web API.
class WebWebViewController extends PlatformWebViewController {
  /// Constructs a [WebWebViewController].
  WebWebViewController(PlatformWebViewControllerCreationParams params)
      : super.implementation(params is WebWebViewControllerCreationParams
            ? params
            : WebWebViewControllerCreationParams
                .fromPlatformWebViewControllerCreationParams(params));

  WebWebViewControllerCreationParams get _webWebViewParams =>
      params as WebWebViewControllerCreationParams;

  /// Mapping between channel names and message event handlers.
  HashMap<String, void Function(html.Event)> javascriptChannels =
      HashMap<String, void Function(html.Event)>();

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    // ignore: unsafe_html
    _webWebViewParams.iFrame.src = Uri.dataFromString(
      html,
      mimeType: 'text/html',
      encoding: utf8,
    ).toString();
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    if (!params.uri.hasScheme) {
      throw ArgumentError(
          'LoadRequestParams#uri is required to have a scheme.');
    }

    if (params.headers.isEmpty &&
        (params.body == null || params.body!.isEmpty) &&
        params.method == LoadRequestMethod.get) {
      // ignore: unsafe_html
      _webWebViewParams.iFrame.src = params.uri.toString();
    } else {
      await _updateIFrameFromXhr(params);
    }
  }

  /// Performs an AJAX request defined by [params].
  Future<void> _updateIFrameFromXhr(LoadRequestParams params) async {
    final html.HttpRequest httpReq =
        await _webWebViewParams.httpRequestFactory.request(
      params.uri.toString(),
      method: params.method.serialize(),
      requestHeaders: params.headers,
      sendData: params.body,
    );

    final String header =
        httpReq.getResponseHeader('content-type') ?? 'text/html';
    final ContentType contentType = ContentType.parse(header);
    final Encoding encoding = Encoding.getByName(contentType.charset) ?? utf8;

    // ignore: unsafe_html
    _webWebViewParams.iFrame.src = Uri.dataFromString(
      httpReq.responseText ?? '',
      mimeType: contentType.mimeType,
      encoding: encoding,
    ).toString();
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    void handler(html.Event event) {
      if (event is html.MessageEvent) {
        javaScriptChannelParams.onMessageReceived(
            JavaScriptMessage(message: event.data.toString()));
      }
    }

    javascriptChannels[javaScriptChannelParams.name] = handler;
    html.window.addEventListener('message', handler);
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    final void Function(html.Event)? handler =
        javascriptChannels[javaScriptChannelName];

    if (handler != null) {
      html.window.removeEventListener('message', handler);
    }
  }
}

/// An implementation of [PlatformWebViewWidget] using Flutter the for Web API.
class WebWebViewWidget extends PlatformWebViewWidget {
  /// Constructs a [WebWebViewWidget].
  WebWebViewWidget(PlatformWebViewWidgetCreationParams params)
      : super.implementation(params) {
    final WebWebViewController controller =
        params.controller as WebWebViewController;
    ui_web.platformViewRegistry.registerViewFactory(
      controller._webWebViewParams.iFrame.id,
      (int viewId) => controller._webWebViewParams.iFrame,
    );
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      key: params.key,
      viewType: (params.controller as WebWebViewController)
          ._webWebViewParams
          .iFrame
          .id,
    );
  }
}
