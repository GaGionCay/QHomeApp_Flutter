import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'post_dto.dart';

class PostSocketService {
  final _channel = IOWebSocketChannel.connect('ws://192.168.100.33:8080/ws');

  void Function(PostCommentDto)? _commentCallback;
  void Function(PostLikeDto)? _likeCallback;
  void Function(Map<String, dynamic>)? _shareCallback;

  PostSocketService() {
    _channel.stream.listen((event) {
      try {
        final data = jsonDecode(event);
        final type = data['type'];
        final payload = data['payload'];
        // debug
        print('WS message received: $data');

        switch (type) {
          case 'comment':
            if (_commentCallback != null) {
              _commentCallback!(PostCommentDto.fromJson(payload));
            }
            break;
          case 'like':
            if (_likeCallback != null) {
              _likeCallback!(PostLikeDto.fromJson(payload));
            }
            break;
          case 'share':
            if (_shareCallback != null) {
              _shareCallback!(payload);
            }
            break;
        }
      } catch (e) {
        print('WebSocket parse error: $e');
      }
    });
  }

  void listenComments(void Function(PostCommentDto) callback) {
    _commentCallback = callback;
  }

  void listenLikes(void Function(PostLikeDto) callback) {
    _likeCallback = callback;
  }

  void listenShares(void Function(Map<String, dynamic>) callback) {
    _shareCallback = callback;
  }

  void dispose() {
    _channel.sink.close();
  }
}
