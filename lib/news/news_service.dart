// import 'package:dio/dio.dart';

// class NewsService {
//   final Dio dio;
//   NewsService(this.dio);

//   Future<Response> list({String? category, int page = 0, int size = 20}) {
//     return dio.get('/news', queryParameters: {'category': category, 'page': page, 'size': size});
//   }

//   Future<Response> getOne(int id) => dio.get('/news/$id');
//   Future<Response> markRead(int id) => dio.post('/news/$id/read');
//   Future<Response> unreadCount() => dio.get('/news/unread-count');
// }
