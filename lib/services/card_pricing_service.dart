import 'package:dio/dio.dart';
import '../auth/api_client.dart';

class CardPricingService {
  final Dio dio;

  CardPricingService(this.dio);

  /// Get active price for a card type
  /// Returns price in VND (BigDecimal from backend)
  Future<double> getCardPrice(String cardType) async {
    try {
      final baseUrl = ApiClient.buildServiceBase(port: 8083, path: '/api');
      final response = await dio.get(
        '$baseUrl/card-pricing/type/$cardType/price',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final price = data['price'];
        if (price is num) {
          return price.toDouble();
        }
      }
      
      // Fallback to default 30000 if API fails
      return 30000.0;
    } catch (e) {
      // Fallback to default 30000 if API fails
      return 30000.0;
    }
  }

  /// Get all card pricing configurations
  Future<Map<String, double>> getAllCardPrices() async {
    try {
      final baseUrl = ApiClient.buildServiceBase(port: 8083, path: '/api');
      final response = await dio.get(
        '$baseUrl/card-pricing',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data is List) {
        final List<dynamic> data = response.data;
        final Map<String, double> prices = {};
        
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            final cardType = item['cardType']?.toString();
            final price = item['price'];
            final isActive = item['isActive'] ?? true;
            
            if (cardType != null && price is num && isActive == true) {
              prices[cardType] = price.toDouble();
            }
          }
        }
        
        return prices;
      }
      
      // Fallback to defaults
      return {
        'VEHICLE': 30000.0,
        'RESIDENT': 30000.0,
        'ELEVATOR': 30000.0,
      };
    } catch (e) {
      // Fallback to defaults
      return {
        'VEHICLE': 30000.0,
        'RESIDENT': 30000.0,
        'ELEVATOR': 30000.0,
      };
    }
  }
}

