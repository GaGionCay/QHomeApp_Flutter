import 'package:dio/dio.dart';

class CardPricingService {
  final Dio dio;

  CardPricingService(this.dio);

  /// Get active price for a card type
  /// Returns price in VND (BigDecimal from backend)
  Future<double> getCardPrice(String cardType) async {
    try {
      // Use dio's baseUrl (already configured to use API Gateway)
      // API Gateway will route /api/card-pricing/* to services-card-service
      final response = await dio.get(
        '/card-pricing/type/$cardType/price',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final price = data['price'];
        
        // Handle different price formats from backend
        if (price is num) {
          return price.toDouble();
        } else if (price is String) {
          final parsed = double.tryParse(price);
          if (parsed != null && parsed > 0) {
            return parsed;
          }
        }
      }
      
      // Fallback to default 30000 if API fails or price is invalid
      return 30000.0;
    } catch (e) {
      // Fallback to default 30000 if API fails
      return 30000.0;
    }
  }

  /// Get all card pricing configurations
  Future<Map<String, double>> getAllCardPrices() async {
    try {
      // Use dio's baseUrl (already configured to use API Gateway)
      // API Gateway will route /api/card-pricing/* to services-card-service
      final response = await dio.get(
        '/card-pricing',
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
            
            // Handle different price formats from backend
            double? parsedPrice;
            if (price is num) {
              parsedPrice = price.toDouble();
            } else if (price is String) {
              parsedPrice = double.tryParse(price);
            }
            
            if (cardType != null && parsedPrice != null && parsedPrice > 0 && isActive == true) {
              prices[cardType] = parsedPrice;
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

