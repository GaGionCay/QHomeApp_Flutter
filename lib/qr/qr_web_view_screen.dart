// ignore_for_file: use_build_context_synchronously
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';

import '../core/safe_state_mixin.dart';
class QrWebViewScreen extends StatefulWidget {
  const QrWebViewScreen({
    super.key,
    required this.url,
  });

  final String url;

  @override
  State<QrWebViewScreen> createState() => _QrWebViewScreenState();
}

class _QrWebViewScreenState extends State<QrWebViewScreen> with SafeStateMixin<QrWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _error;
  String? _pageTitle;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            log('🌐 WebView: Page started loading: $url');
            safeSetState(() {
              _isLoading = true;
              _error = null;
            });
          },
          onPageFinished: (String url) {
            log('🌐 WebView: Page finished loading: $url');
            safeSetState(() {
              _isLoading = false;
            });
            // Get page title
            _controller.getTitle().then((title) {
              if (mounted && title != null && title.isNotEmpty) {
                safeSetState(() {
                  _pageTitle = title;
                });
              }
            });
            // Refresh navigation buttons after page finishes
            Future.microtask(() {
              if (mounted) safeSetState(() {});
            });
          },
          onWebResourceError: (WebResourceError error) {
            log('❌ WebView error: ${error.description}');
            safeSetState(() {
              _isLoading = false;
              _error = error.description;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            log('🌐 WebView: Navigation request to ${request.url}');
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pageTitle ?? 'Đang tải...',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(CupertinoIcons.arrow_clockwise),
              onPressed: () {
                _controller.reload();
              },
              tooltip: 'Tải lại',
            ),
          IconButton(
            icon: const Icon(CupertinoIcons.square_arrow_up),
            onPressed: () async {
              final uri = Uri.parse(widget.url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Không thể mở URL trong trình duyệt'),
                  ),
                );
              }
            },
            tooltip: 'Mở trong trình duyệt',
          ),
        ],
      ),
      body: _error != null
          ? _buildErrorView(theme)
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  Container(
                    color: theme.scaffoldBackgroundColor,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primaryAqua,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Đang tải trang web...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: _buildBottomBar(theme),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 64,
              color: AppColors.danger,
            ),
            const SizedBox(height: 16),
            Text(
              'Không thể tải trang web',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Đã xảy ra lỗi không xác định',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                _controller.reload();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAqua,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              FutureBuilder<bool>(
                future: _controller.canGoBack(),
                builder: (context, snapshot) {
                  final canGoBack = snapshot.data ?? false;
                  return IconButton(
                    icon: const Icon(CupertinoIcons.chevron_left),
                    onPressed: canGoBack
                        ? () async {
                            if (await _controller.canGoBack()) {
                              _controller.goBack();
                            }
                            safeSetState(() {}); // Refresh buttons
                          }
                        : null,
                    tooltip: 'Quay lại',
                  );
                },
              ),
              FutureBuilder<bool>(
                future: _controller.canGoForward(),
                builder: (context, snapshot) {
                  final canGoForward = snapshot.data ?? false;
                  return IconButton(
                    icon: const Icon(CupertinoIcons.chevron_right),
                    onPressed: canGoForward
                        ? () async {
                            if (await _controller.canGoForward()) {
                              _controller.goForward();
                            }
                            safeSetState(() {}); // Refresh buttons
                          }
                        : null,
                    tooltip: 'Tiến tới',
                  );
                },
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.house),
                onPressed: () {
                  _controller.loadRequest(Uri.parse(widget.url));
                },
                tooltip: 'Trang chủ',
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.square_arrow_up),
                onPressed: () async {
                  final uri = Uri.parse(widget.url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Không thể mở URL trong trình duyệt'),
                        ),
                      );
                    }
                  }
                },
                tooltip: 'Mở trong trình duyệt',
              ),
            ],
          ),
        ),
      ),
    );
  }
}



