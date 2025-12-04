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
    this.author,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MarketplacePost.fromJson(Map<String, dynamic> json) {
    // Debug: Check author data
    if (json['author'] != null) {
      print('📝 [MarketplacePost] Author data: ${json['author']}');
    } else {
      print('⚠️ [MarketplacePost] Author is null for post: ${json['id']}');
    }
    
    final author = json['author'] != null
        ? MarketplaceResidentInfo.fromJson(json['author'])
        : null;
    
    if (author != null) {
      print('✅ [MarketplacePost] Parsed author - name: ${author.name}, residentId: ${author.residentId}');
    } else {
      print('❌ [MarketplacePost] Failed to parse author for post: ${json['id']}');
    }
    
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
        print('📞 [MarketplacePost] ContactInfo data: $contactInfoJson');
        if (contactInfoJson == null) {
          print('⚠️ [MarketplacePost] ContactInfo is null for post: ${json['id']}');
          return null;
        }
        if (contactInfoJson is Map) {
          final contactInfo = MarketplaceContactInfo.fromJson(Map<String, dynamic>.from(contactInfoJson));
          print('✅ [MarketplacePost] Parsed ContactInfo - phone: ${contactInfo.phone}, email: ${contactInfo.email}, showPhone: ${contactInfo.showPhone}, showEmail: ${contactInfo.showEmail}');
          return contactInfo;
        }
        print('⚠️ [MarketplacePost] ContactInfo is not a Map for post: ${json['id']}');
        return null;
      }(),
      location: json['location'],
      viewCount: json['viewCount'] ?? 0,
      commentCount: json['commentCount'] ?? 0,
      images: () {
        final imagesJson = json['images'];
        print('🖼️ [MarketplacePost] Images data: $imagesJson');
        if (imagesJson == null) {
          print('⚠️ [MarketplacePost] Images is null for post: ${json['id']}');
          return <MarketplacePostImage>[];
        }
        if (imagesJson is List) {
          print('✅ [MarketplacePost] Found ${imagesJson.length} images for post: ${json['id']}');
          final images = imagesJson.map((img) {
            print('🖼️ [MarketplacePost] Parsing image: $img');
            return MarketplacePostImage.fromJson(img);
          }).toList();
          return images;
        }
        print('⚠️ [MarketplacePost] Images is not a List for post: ${json['id']}');
        return <MarketplacePostImage>[];
      }(),
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
    // Debug: Check image data
    print('🖼️ [MarketplacePostImage] Parsing: $json');
    
    String imageUrl = json['imageUrl'] ?? json['url'] ?? '';
    String? thumbnailUrl = json['thumbnailUrl'];
    
    // Convert relative URL to absolute URL if needed
    if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
      try {
        // URL from backend is like /api/marketplace/uploads/...
        // We need to prepend base URL (http://host:port)
        // Since ApiClient.activeFileBaseUrl is http://host:port (without /api),
        // we need to keep the full path including /api
        imageUrl = _buildImageUrl(imageUrl);
        print('✅ [MarketplacePostImage] Converted imageUrl: $imageUrl');
      } catch (e) {
        print('⚠️ [MarketplacePostImage] Error converting URL: $e');
      }
    }
    
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty && !thumbnailUrl.startsWith('http')) {
      try {
        thumbnailUrl = _buildImageUrl(thumbnailUrl);
        print('✅ [MarketplacePostImage] Converted thumbnailUrl: $thumbnailUrl');
      } catch (e) {
        print('⚠️ [MarketplacePostImage] Error converting thumbnail URL: $e');
      }
    }
    
    print('🖼️ [MarketplacePostImage] Final - imageUrl: $imageUrl, thumbnailUrl: $thumbnailUrl');
    
    return MarketplacePostImage(
      id: json['id']?.toString() ?? '',
      postId: json['postId']?.toString() ?? '',
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
      sortOrder: json['sortOrder'] ?? 0,
    );
  }
  
  // Helper to build absolute image URL
  static String _buildImageUrl(String relativePath) {
    try {
      // Use ApiClient.activeFileBaseUrl if ApiClient is initialized
      // activeFileBaseUrl is http://host:port (without /api)
      // relativePath is like /api/marketplace/uploads/...
      // So we just concatenate them
      if (ApiClient.isInitialized) {
        final baseUrl = ApiClient.activeFileBaseUrl;
        // Ensure relativePath starts with /
        final path = relativePath.startsWith('/') ? relativePath : '/$relativePath';
        final fullUrl = '$baseUrl$path';
        print('🔗 [MarketplacePostImage] Building URL: baseUrl=$baseUrl, path=$path, fullUrl=$fullUrl');
        return fullUrl;
      } else {
        // Fallback: construct from known pattern
        const host = 'localhost';
        const port = 8989;
        final path = relativePath.startsWith('/') ? relativePath : '/$relativePath';
        return 'http://$host:$port$path';
      }
    } catch (e) {
      print('⚠️ [MarketplacePostImage] Error in _buildImageUrl: $e');
      // Fallback: assume localhost:8989
      final path = relativePath.startsWith('/') ? relativePath : '/$relativePath';
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
    print('🔍 [MarketplaceResidentInfo] Parsing: $json');
    final result = MarketplaceResidentInfo(
      residentId: json['residentId']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name'],
      avatarUrl: json['avatarUrl'],
      unitNumber: json['unitNumber'],
      buildingName: json['buildingName'],
      userId: json['userId']?.toString(),
    );
    print('✅ [MarketplaceResidentInfo] Parsed - name: ${result.name}, residentId: ${result.residentId}, userId: ${result.userId}, unitNumber: ${result.unitNumber}, buildingName: ${result.buildingName}');
    return result;
  }
}

