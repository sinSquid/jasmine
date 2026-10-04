import 'package:jasmine/basic/ui_action.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../basic/commons.dart';
import 'init_screen.dart';

class UnlockBrowserScreen extends StatefulWidget {
  const UnlockBrowserScreen({Key? key}) : super(key: key);

  @override
  State<UnlockBrowserScreen> createState() => _UnlockBrowserScreenState();
}

class _UnlockBrowserScreenState extends State<UnlockBrowserScreen> {
  static const _defaultUrl = 'https://www.bing.com/';

  final TextEditingController _addressController =
      TextEditingController(text: _defaultUrl);
  final FocusNode _addressFocusNode = FocusNode();

  InAppWebViewController? _webViewController;
  String _currentUrl = _defaultUrl;
  double _progress = 0;

  @override
  void dispose() {
    _addressController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  String _normalize(String input) {
    return input.trim();
  }

  bool _isActivationUrl(String url) {
    final uri = Uri.tryParse(_normalize(url));
    return uri != null &&
        uri.scheme == 'jm' &&
        uri.host == 'start' &&
        (uri.path.isEmpty || uri.path == '/') &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  Uri _toUri(String input) {
    final raw = _normalize(input);
    if (raw.isEmpty) return Uri.parse('about:blank');
    final uri = Uri.tryParse(raw);
    if (uri == null) return Uri.parse('about:blank');
    if (uri.hasScheme) return uri;
    return Uri.parse('https://$raw');
  }

  bool _activating = false;

  Future<void> _activate() async {
    if (!mounted || _activating) return;
    _activating = true;
    try {
      await activateApp(context);
    } catch (_) {
      if (mounted) defaultToast(context, '进入失败，请重试');
    } finally {
      _activating = false;
    }
  }

  Future<void> _loadFromAddressBar(String value) =>
      runUiAction(context, () async {
        if (_isActivationUrl(value)) {
          await _activate();
          return;
        }
        final uri = _toUri(value);
        await _webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(uri.toString())),
        );
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: TextField(
          controller: _addressController,
          focusNode: _addressFocusNode,
          textInputAction: TextInputAction.go,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: '输入网址',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: theme.cardColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          onSubmitted: (value) async {
            await _loadFromAddressBar(value);
          },
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _webViewController?.reload(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '菜单',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) {
                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(value: _progress),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useShouldOverrideUrlLoading: true,
                mediaPlaybackRequiresUserGesture: true,
                allowsInlineMediaPlayback: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              shouldOverrideUrlLoading: (controller, action) async {
                final url = action.request.url?.toString() ?? '';
                if (_isActivationUrl(url)) {
                  unawaited(_activate());
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onLoadStart: (controller, url) {
                if (!mounted) return;
                final u = url?.toString() ?? '';
                setState(() {
                  _currentUrl = u.isEmpty ? _currentUrl : u;
                  _addressController.text = _currentUrl;
                });
              },
              onLoadStop: (controller, url) async {
                if (!mounted) return;
                final u = url?.toString() ?? '';
                setState(() {
                  _currentUrl = u.isEmpty ? _currentUrl : u;
                  _addressController.text = _currentUrl;
                  _progress = 0;
                });
              },
              onProgressChanged: (controller, progress) {
                if (!mounted) return;
                setState(() {
                  _progress = progress / 100.0;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
