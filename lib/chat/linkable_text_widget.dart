import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

/// Widget to display text with clickable links
/// Automatically detects URLs and makes them clickable
class LinkableText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Color? linkColor;
  final TextAlign? textAlign;

  const LinkableText({
    super.key,
    required this.text,
    this.style,
    this.linkColor,
    this.textAlign,
  });

  /// Regular expression to detect URLs
  /// Supports:
  /// - http://, https://, ftp://
  /// - www. prefix
  /// - Common domains (facebook.com, tiktok.com, youtube.com, etc.)
  /// - IP addresses
  /// - Short URLs
  static final RegExp _urlRegex = RegExp(
    r'(?:(?:https?|ftp):\/\/)?(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)|(?:https?:\/\/)?(?:www\.)?(?:facebook\.com|fb\.com|tiktok\.com|youtube\.com|youtu\.be|instagram\.com|twitter\.com|x\.com|linkedin\.com|pinterest\.com|reddit\.com|snapchat\.com|whatsapp\.com|telegram\.org|discord\.com|zoom\.us|meet\.google\.com|vimeo\.com|dailymotion\.com|twitch\.tv|spotify\.com|soundcloud\.com|apple\.com|microsoft\.com|google\.com|amazon\.com|netflix\.com|github\.com|stackoverflow\.com|medium\.com|wikipedia\.org|quora\.com|tumblr\.com|flickr\.com|imgur\.com|giphy\.com|bit\.ly|tinyurl\.com|t\.co|goo\.gl|ow\.ly|buff\.ly|short\.link)\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*',
    caseSensitive: false,
  );

  /// Detect all URLs in the text
  List<_TextSegment> _parseText() {
    final List<_TextSegment> segments = [];
    int lastIndex = 0;

    for (final match in _urlRegex.allMatches(text)) {
      // Add text before the URL
      if (match.start > lastIndex) {
        segments.add(_TextSegment(
          text: text.substring(lastIndex, match.start),
          isLink: false,
        ));
      }

      // Add the URL
      String url = match.group(0)!;
      // Ensure URL has protocol
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      segments.add(_TextSegment(
        text: match.group(0)!,
        isLink: true,
        url: url,
      ));

      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < text.length) {
      segments.add(_TextSegment(
        text: text.substring(lastIndex),
        isLink: false,
      ));
    }

    // If no URLs found, return the whole text as a single segment
    if (segments.isEmpty) {
      segments.add(_TextSegment(text: text, isLink: false));
    }

    return segments;
  }

  /// Launch URL with Android chooser
  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      
      // Check if URL can be launched
      if (!await canLaunchUrl(uri)) {
        throw Exception('Cannot launch URL: $url');
      }

      // Launch URL with external application mode to show Android chooser
      await launchUrl(
        uri,
        mode: Platform.isAndroid 
            ? LaunchMode.externalApplication 
            : LaunchMode.platformDefault,
      );
    } catch (e) {
      debugPrint('❌ [LinkableText] Error launching URL: $e');
      // Optionally show error to user
      // You can add a callback here if needed
    }
  }

  @override
  Widget build(BuildContext context) {
    final segments = _parseText();
    final linkColor = this.linkColor ?? 
        (style?.color != null 
            ? (style!.color!.computeLuminance() > 0.5 
                ? Colors.blue.shade700 
                : Colors.blue.shade300)
            : Colors.blue);

    if (segments.length == 1 && !segments.first.isLink) {
      // No links found, return simple text
      return Text(
        text,
        style: style,
        textAlign: textAlign,
      );
    }

    // Build RichText with clickable links
    return RichText(
      textAlign: textAlign ?? TextAlign.start,
      text: TextSpan(
        children: segments.map((segment) {
          if (segment.isLink) {
            return TextSpan(
              text: segment.text,
              style: (style ?? const TextStyle()).copyWith(
                color: linkColor,
                decoration: TextDecoration.underline,
                decorationColor: linkColor,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchUrl(segment.url!),
            );
          } else {
            return TextSpan(
              text: segment.text,
              style: style,
            );
          }
        }).toList(),
      ),
    );
  }
}

/// Internal class to represent text segments
class _TextSegment {
  final String text;
  final bool isLink;
  final String? url;

  _TextSegment({
    required this.text,
    required this.isLink,
    this.url,
  });
}


