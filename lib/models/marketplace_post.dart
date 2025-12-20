import '../auth/api_client.dart';

class MarketplacePost {
  final String id;
  final String residentId;
  final String buildingId;
  final String title;
  final String description;
  final double? price;
  final String category;
  final String categoryName; // Tên category để hiển thị
  final String status; // ACTIVE, SOLD, DELETED
  final String? scope; // BUILDING, ALL, or BOTH
  final MarketplaceContactInfo? contactInfo;
  final String? location; // Tòa nhà, tầng, căn hộ
  final int viewCount;
  final int commentCount;
  final List<MarketplacePostImage> images;
  final String? videoUrl; // URL to video in data-docs-service
  final MarketplaceResidentInfo? author; // Thông tin người đăng
  final DateTime createdAt;
  final DateTime updatedAt;

  MarketplacePost({
    required this.id,
    required this.residentId,
    required this.buildingId,
    required this.title,
    required this.description,
    this.price,
    required this.category,
    required this.categoryName,
    required this.status,
    this.scope,
    this.contactInfo,
    this.location,
    required this.viewCount,
    required this.commentCount,
    required this.images,
    this.videoUrl,
    this.author,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MarketplacePost.fromJson(Map<String, dynamic> json) {
    final author = json['author'] != null
        ? MarketplaceResidentInfo.fromJson(json['author'])
        : null;
    
    return MarketplacePost(
      id: json['id']?.toString() ?? '',
      residentId: json['residentId']?.toString() ?? '',
      buildingId: json['buildingId']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      price: json['price'] != null ? (json['price'] is num ? json['price'].toDouble() : double.tryParse(json['price'].toString())) : null,
      category: json['category'] ?? '',
      categoryName: json['categoryName'] ?? json['category'] ?? '',
      status: json['status'] ?? 'ACTIVE',
      scope: json['scope'],
      contactInfo: () {
        final contactInfoJson = json['contactInfo'];
        if (contactInfoJson == null) return null;
        if (contactInfoJson is Map) {
          return MarketplaceContactInfo.fromJson(Map<String, dynamic>.from(contactInfoJson));
        }
        return null;
      }(),
      location: json['location'],
      viewCount: json['viewCount'] ?? 0,
      commentCount: json['commentCount'] ?? 0,
      images: () {
        final imagesJson = json['images'];
        if (imagesJson == null) return <MarketplacePostImage>[];
        if (imagesJson is List) {
          return imagesJson.map((img) => MarketplacePostImage.fromJson(img)).toList();
        }
        return <MarketplacePostImage>[];
      }(),
      videoUrl: json['videoUrl'] != null ? _normalizeVideoUrl(json['videoUrl']!.toString()) : null,
      author: author,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'residentId': residentId,
      'buildingId': buildingId,
      'title': title,
      'description': description,
      'price': price,
      'category': category,
      'status': status,
      'contactInfo': contactInfo?.toJson(),
      'location': location,
      'images': images.map((img) => img.toJson()).toList(),
    };
  }

  bool get isActive => status == 'ACTIVE';
  bool get isSold => status == 'SOLD';
  bool get isDeleted => status == 'DELETED';
  
  String get priceDisplay {
    if (price == null) return 'Thỏa thuận';
    return '${price!.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} đ';
  }

  // Helper to normalize video URL to absolute URL using API Gateway
  static String? _normalizeVideoUrl(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    
    // If URL is already absolute, return as-is
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    // Backend returns relative path: /api/videos/stream/{videoId}
    // Normalize it to use API Gateway base URL
    try {
      if (url.startsWith('/api/')) {
        // Remove /api prefix and prepend API Gateway base URL (which already includes /api)
        final apiGatewayBase = ApiClient.buildServiceBase();
        final pathWithoutApi = url.substring(4); // Remove /api prefix
        return '$apiGatewayBase$pathWithoutApi';
      } else if (url.startsWith('/')) {
        // Already relative but doesn't start with /api, prepend API Gateway base
        final apiGatewayBase = ApiClient.buildServiceBase();
        return '$apiGatewayBase$url';
      } else {
        // Not a valid URL format, try to construct from API Gateway
        final apiGatewayBase = ApiClient.buildServiceBase();
        return '$apiGatewayBase/$url';
      }
    } catch (e) {
      // If normalization fails, return original URL
      return url;
    }
  }
}

class MarketplacePostImage {
  final String id;
  final String postId;
  final String imageUrl;
  final String? thumbnailUrl;
  final int sortOrder;

  MarketplacePostImage({
    required this.id,
    required this.postId,
    required this.imageUrl,
    this.thumbnailUrl,
    required this.sortOrder,
  });

  factory MarketplacePostImage.fromJson(Map<String, dynamic> json) {
    String imageUrl = json['imageUrl'] ?? json['url'] ?? '';
    String? thumbnailUrl = json['thumbnailUrl'];
    
    // Convert relative URL to absolute URL if needed
    if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
      try {
        imageUrl = _buildImageUrl(imageUrl);
      } catch (e) {
        // Keep original URL on error
      }
    }
    
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty && !thumbnailUrl.startsWith('http')) {
      try {
        thumbnailUrl = _buildImageUrl(thumbnailUrl);
      } catch (e) {
        // Keep original URL on error
      }
    }
    
    return MarketplacePostImage(
      id: json['id']?.toString() ?? '',
      postId: json['postId']?.toString() ?? '',
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
      sortOrder: json['sortOrder'] ?? 0,
    );
  }
  
  // Helper to normalize video URL to absolute URL using API Gateway
  static String? _normalizeVideoUrl(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    
    // If URL is already absolute, return as-is
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    // Backend returns relative path: /api/videos/stream/{videoId}
    // Normalize it to use API Gateway base URL
    try {
      if (url.startsWith('/api/')) {
        // Remove /api prefix and prepend API Gateway base URL (which already includes /api)
        final apiGatewayBase = ApiClient.buildServiceBase();
        final pathWithoutApi = url.substring(4); // Remove /api prefix
        return '$apiGatewayBase$pathWithoutApi';
      } else if (url.startsWith('/')) {
        // Already relative but doesn't start with /api, prepend API Gateway base
        final apiGatewayBase = ApiClient.buildServiceBase();
        return '$apiGatewayBase$url';
      } else {
        // Not a valid URL format, try to construct from API Gateway
        final apiGatewayBase = ApiClient.buildServiceBase();
        return '$apiGatewayBase/$url';
      }
    } catch (e) {
      // If normalization fails, return original URL
      return url;
    }
  }

  // Helper to build absolute image URL
  static String _buildImageUrl(String url) {
    try {
      // If URL is already absolute, return as-is
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return url;
      }
      
      // Use ApiClient.activeFileBaseUrl if ApiClient is initialized
      if (ApiClient.isInitialized) {
        final baseUrl = ApiClient.activeFileBaseUrl;
        final path = url.startsWith('/') ? url : '/$url';
        return '$baseUrl$path';
      } else {
        // Fallback: construct from known pattern
        const host = 'localhost';
        const port = 8989;
        final path = url.startsWith('/') ? url : '/$url';
        return 'http://$host:$port$path';
      }
    } catch (e) {
      // If URL is already absolute, return as-is even on error
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return url;
      }
      // Fallback: assume localhost:8989
      final path = url.startsWith('/') ? url : '/$url';
      return 'http://localhost:8989$path';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'postId': postId,
      'imageUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
      'sortOrder': sortOrder,
    };
  }
}

class MarketplaceContactInfo {
  final String? phone;
  final String? email;
  final bool showPhone;
  final bool showEmail;

  MarketplaceContactInfo({
    this.phone,
    this.email,
    this.showPhone = true,
    this.showEmail = false,
  });

  factory MarketplaceContactInfo.fromJson(Map<String, dynamic> json) {
    return MarketplaceContactInfo(
      phone: json['phone'],
      email: json['email'],
      showPhone: json['showPhone'] ?? true,
      showEmail: json['showEmail'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'phone': phone,
      'email': email,
      'showPhone': showPhone,
      'showEmail': showEmail,
    };
  }

  String get phoneDisplay {
    if (phone == null || !showPhone) return '';
    if (phone!.length <= 4) return phone!;
    return '***${phone!.substring(phone!.length - 4)}';
  }
}

class MarketplaceResidentInfo {
  final String residentId;
  final String? name;
  final String? avatarUrl;
  final String? unitNumber; // Số căn hộ
  final String? buildingName; // Tên tòa nhà (e.g., "Tòa A", "Tòa B")
  final String? userId; // User ID for blocking functionality

  MarketplaceResidentInfo({
    required this.residentId,
    this.name,
    this.avatarUrl,
    this.unitNumber,
    this.buildingName,
    this.userId,
  });

  factory MarketplaceResidentInfo.fromJson(Map<String, dynamic> json) {
    return MarketplaceResidentInfo(
      residentId: json['residentId']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name'],
      avatarUrl: json['avatarUrl'],
      unitNumber: json['unitNumber'],
      buildingName: json['buildingName'],
      userId: json['userId']?.toString(),
    );
  }
}


