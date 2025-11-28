import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// Service để quét và trích xuất thông tin từ ảnh CCCD
class CccdOcrService {
  final TextRecognizer _textRecognizer;

  CccdOcrService() : _textRecognizer = TextRecognizer();

  /// Quét ảnh CCCD và trích xuất thông tin
  Future<CccdInfo?> scanCccdImage(Uint8List imageBytes) async {
    File? tempFile;
    try {
      // Lưu file tạm để sử dụng InputImage.fromFilePath
      // ML Kit fromBytes chỉ hỗ trợ nv21 (camera format), không hỗ trợ JPEG/PNG
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      tempFile = File('${tempDir.path}/cccd_scan_$timestamp.jpg');
      await tempFile.writeAsBytes(imageBytes);

      // Tạo InputImage từ file path
      final inputImage = InputImage.fromFilePath(tempFile.path);

      // Nhận diện text
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);

      // Phân tích và trích xuất thông tin (sử dụng blocks để chính xác hơn)
      return _parseCccdTextFromBlocks(recognizedText);
    } catch (e) {
      print('❌ [CccdOcrService] Lỗi khi quét CCCD: $e');
      return null;
    } finally {
      // Xóa file tạm
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        print('⚠️ [CccdOcrService] Không thể xóa file tạm: $e');
      }
    }
  }

  /// Phân tích text từ blocks để trích xuất thông tin CCCD (chính xác hơn)
  CccdInfo? _parseCccdTextFromBlocks(RecognizedText recognizedText) {
    if (recognizedText.text.isEmpty) return null;

    // Lấy toàn bộ text để log
    final fullText = recognizedText.text;
    print('📄 [CccdOcrService] Full text đã nhận diện: $fullText');
    print('📄 [CccdOcrService] Số blocks: ${recognizedText.blocks.length}');

    // Chuẩn hóa text: loại bỏ khoảng trắng thừa, chuyển thành chữ hoa
    final normalizedText = fullText
        .replaceAll(RegExp(r'\s+'), ' ')
        .toUpperCase()
        .trim();

    // Sắp xếp blocks theo vị trí Y (từ trên xuống dưới)
    final sortedBlocks = List<TextBlock>.from(recognizedText.blocks)
      ..sort((a, b) {
        final aTop = a.boundingBox.top;
        final bTop = b.boundingBox.top;
        return aTop.compareTo(bTop);
      });

    // Tìm họ tên từ blocks (thường ở block đầu tiên hoặc block có text dài nhất)
    String? fullName = _extractFullNameFromBlocks(sortedBlocks, normalizedText);

    return _parseCccdText(normalizedText, fullName);
  }

  /// Trích xuất họ tên từ blocks (chính xác hơn)
  String? _extractFullNameFromBlocks(List<TextBlock> blocks, String normalizedText) {
    // Danh sách các từ khóa không phải tên
    final excludeKeywords = [
      'CCCD', 'CMND', 'CĂN CƯỚC', 'CÔNG DÂN',
      'PHƯỜNG', 'QUẬN', 'HUYỆN', 'TỈNH', 'THÀNH PHỐ',
      'NGÀY SINH', 'NƠI SINH', 'QUỐC TỊCH', 'GIỚI TÍNH',
      'ĐỊA CHỈ', 'THƯỜNG TRÚ', 'TẠM TRÚ',
      'VIỆT NAM', 'VIET NAM', 'CỘNG HÒA', 'XÃ HỘI', 'CHỦ NGHĨA',
      'ĐỘC LẬP', 'TỰ DO', 'HẠNH PHÚC', 'INDEPENDENCE', 'FREEDOM', 'HAPPINESS',
      'SOCIALIST', 'REPUBLIC', 'CITIZEN', 'IDENTITY', 'CARD',
    ];

    // Pattern cho tên tiếng Việt (chấp nhận dấu và chữ cái)
    final vietnameseNamePattern = RegExp(
      r'^[A-ZÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ\s]{5,50}$',
      caseSensitive: false,
    );

    // Ưu tiên 1: Tìm block có chứa "HỌ TÊN" hoặc "HỌ VÀ TÊN" hoặc "FULL NAME"
    // Sau đó lấy block ngay sau đó làm tên (vì tên thường ở dòng riêng, chữ in hoa to)
    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final blockText = block.text.trim();
      final blockTextUpper = blockText.toUpperCase();
      
      // Kiểm tra xem block này có chứa label "HỌ TÊN" không
      final hasNameLabel = RegExp(
        r'(?:HỌ\s*TÊN|HỌ\s*VÀ\s*TÊN|FULL\s*NAME)',
        caseSensitive: false,
      ).hasMatch(blockTextUpper);
      
      if (hasNameLabel) {
        print('🔍 [CccdOcrService] Tìm thấy label ở block $i: $blockText');
        
        // Ưu tiên: Tìm trong các block tiếp theo (i+1, i+2, i+3)
        // Vì OCR có thể nhận diện sai thứ tự blocks hoặc tên có thể ở block không liền kề
        // Format: "Họ và tên / Full name:" (xuống dòng) "HOÀNG NGỌC MINH TRÍ"
        for (int offset = 1; offset <= 3 && i + offset < blocks.length; offset++) {
          final candidateBlock = blocks[i + offset];
          final candidateText = candidateBlock.text.trim();
          
          print('🔍 [CccdOcrService] Kiểm tra block $i+$offset: $candidateText');
          
          // Tách block thành các dòng (có thể có nhiều dòng trong cùng một block)
          final lines = candidateText.split(RegExp(r'[\n\r]+')).map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
          
          print('🔍 [CccdOcrService] Block có ${lines.length} dòng: ${lines.map((l) => '"$l"').join(", ")}');
          
          // Thử từng dòng, lấy dòng đầu tiên hợp lệ làm tên
          for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
            final lineText = lines[lineIndex];
            
            // Chuẩn hóa ký tự đặc biệt (ví dụ: İ → I, các ký tự OCR nhận diện sai)
            // İ (U+0130) → I (U+0049)
            // ı (U+0131) → i (U+0069)
            String normalizedLine = lineText
                .replaceAll('\u0130', 'I')  // İ (Latin Capital I with dot above)
                .replaceAll('\u0131', 'i')  // ı (Latin Small dotless i)
                .replaceAll('İ', 'I')       // Fallback cho trường hợp khác
                .replaceAll('ı', 'i');     // Fallback cho trường hợp khác
            
            print('🔍 [CccdOcrService] Kiểm tra dòng $lineIndex của block $i+$offset: "$normalizedLine" (length: ${normalizedLine.length})');
            
            // Kiểm tra xem dòng này có phải là tên không
            // Tên thường là chữ in hoa, không chứa số, không phải từ khóa loại trừ
            // Không chứa dấu ":" hoặc "/" (vì đó là dấu của label)
            final isNotLabel = !normalizedLine.contains(':') && !normalizedLine.contains('/');
            final hasValidLength = normalizedLine.length >= 5 && normalizedLine.length <= 50;
            final hasNoDigits = !RegExp(r'\d').hasMatch(normalizedLine);
            final hasNoExcludeKeywords = !excludeKeywords.any((keyword) => normalizedLine.toUpperCase().contains(keyword));
            
            // Kiểm tra pattern: chủ yếu là chữ cái và khoảng trắng
            final isMostlyLetters = RegExp(r'^[A-ZÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ\s]+$', caseSensitive: false).hasMatch(normalizedLine);
            
            print('🔍 [CccdOcrService] Validation dòng $lineIndex:');
            print('   - Is not label (no : or /): $isNotLabel');
            print('   - Length valid (5-50): $hasValidLength (${normalizedLine.length})');
            print('   - No digits: $hasNoDigits');
            print('   - No exclude keywords: $hasNoExcludeKeywords');
            print('   - Mostly letters: $isMostlyLetters');
            
            final isValidName = isNotLabel &&
                hasValidLength &&
                hasNoDigits &&
                hasNoExcludeKeywords &&
                isMostlyLetters;
            
            if (isValidName) {
              print('✅ [CccdOcrService] Tìm thấy tên ở dòng $lineIndex của block $i+$offset: $normalizedLine');
              return _normalizeVietnameseName(normalizedLine);
            }
          }
        }
        
        print('⚠️ [CccdOcrService] Không tìm thấy dòng hợp lệ trong các block tiếp theo (đã kiểm tra đến block ${i + 3 < blocks.length ? i + 3 : blocks.length - 1})');
        
        // Fallback: Tìm tên trong cùng block (chỉ nếu block tiếp theo không hợp lệ)
        final nameInSameBlock = RegExp(
          r'(?:HỌ\s*TÊN|HỌ\s*VÀ\s*TÊN|FULL\s*NAME)[:\s/]+([A-ZÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ\s]{5,50})',
          caseSensitive: false,
        ).firstMatch(blockTextUpper);
        
        if (nameInSameBlock != null) {
          final name = nameInSameBlock.group(1)?.trim();
          // Chỉ chấp nhận nếu tên đủ dài và hợp lệ (không phải chỉ là "L" hoặc "FULL NAME")
          if (name != null && 
              name.length >= 5 && 
              name.length <= 50 &&
              !name.contains(RegExp(r'\d')) &&
              !excludeKeywords.any((keyword) => name.contains(keyword)) &&
              vietnameseNamePattern.hasMatch(name) &&
              !name.contains('FULL') &&
              !name.contains('NAME') &&
              name != 'L') {
            print('✅ [CccdOcrService] Tìm thấy tên trong cùng block với label: $name');
            return _normalizeVietnameseName(name);
          }
        }
      }
    }

    // Ưu tiên 2: Tìm block đầu tiên có text dài và không chứa số
    // CHỈ tìm trong các block SAU block có label (nếu có)
    int startIndex = 0;
    for (int i = 0; i < blocks.length; i++) {
      final blockText = blocks[i].text.trim().toUpperCase();
      if (RegExp(r'(?:HỌ\s*TÊN|HỌ\s*VÀ\s*TÊN|FULL\s*NAME)').hasMatch(blockText)) {
        startIndex = i + 2; // Bắt đầu từ block sau block tên (nếu có)
        break;
      }
    }
    
    for (int i = startIndex; i < blocks.length; i++) {
      final block = blocks[i];
      final blockText = block.text.trim();
      final blockTextUpper = blockText.toUpperCase();
      
      // Chuẩn hóa ký tự đặc biệt
      String normalizedBlockText = blockText
          .replaceAll('İ', 'I')
          .replaceAll('ı', 'i');
      
      // Bỏ qua nếu quá ngắn hoặc quá dài
      if (normalizedBlockText.length < 5 || normalizedBlockText.length > 50) continue;
      
      // Bỏ qua nếu chứa số
      if (RegExp(r'\d').hasMatch(normalizedBlockText)) continue;
      
      // Bỏ qua nếu chứa dấu ":" hoặc "/" (thường là label)
      if (normalizedBlockText.contains(':') || normalizedBlockText.contains('/')) continue;
      
      // Bỏ qua nếu chứa từ khóa loại trừ
      if (excludeKeywords.any((keyword) => 
          blockTextUpper.contains(keyword))) {
        continue;
      }
      
      // Bỏ qua nếu không match pattern tên tiếng Việt
      if (!vietnameseNamePattern.hasMatch(normalizedBlockText)) continue;
      
      print('✅ [CccdOcrService] Tìm thấy tên từ block đầu tiên: $normalizedBlockText');
      return _normalizeVietnameseName(normalizedBlockText);
    }

    // Ưu tiên 3: Tìm trong toàn bộ text bằng pattern
    final namePatterns = [
      RegExp(r'(?:HỌ\s*TÊN|HỌ\s*VÀ\s*TÊN)[:\s]+([A-ZÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ\s]{5,50})', caseSensitive: false),
      RegExp(r'^([A-ZÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ\s]{5,50})', caseSensitive: false, multiLine: true),
    ];

    for (final pattern in namePatterns) {
      final match = pattern.firstMatch(normalizedText);
      if (match != null) {
        final name = match.group(1)?.trim();
        if (name != null && 
            name.length >= 5 && 
            name.length <= 50 &&
            !name.contains(RegExp(r'\d')) &&
            !excludeKeywords.any((keyword) => name.contains(keyword))) {
          print('✅ [CccdOcrService] Tìm thấy tên từ pattern: $name');
          return _normalizeVietnameseName(name);
        }
      }
    }

    return null;
  }

  /// Chuẩn hóa tên tiếng Việt (loại bỏ khoảng trắng thừa, giữ nguyên dấu)
  String _normalizeVietnameseName(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ') // Loại bỏ khoảng trắng thừa
        .replaceAll(RegExp(r'[^\w\sÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐđ]'), ''); // Loại bỏ ký tự đặc biệt không hợp lệ
  }

  /// Phân tích text đã nhận diện để trích xuất thông tin CCCD
  CccdInfo? _parseCccdText(String normalizedText, String? preExtractedName) {
    if (normalizedText.isEmpty) return null;

    // Trích xuất các thông tin
    String? fullName = preExtractedName; // Sử dụng tên đã trích xuất từ blocks
    String? nationalId;
    DateTime? dateOfBirth;
    String? address;
    String? gender;
    String? nationality;

    // Pattern để tìm CCCD/CMND (12 hoặc 13 chữ số)
    final idPattern = RegExp(r'\b\d{12,13}\b');
    final idMatch = idPattern.firstMatch(normalizedText);
    if (idMatch != null) {
      nationalId = idMatch.group(0);
    }

    // Pattern để tìm ngày sinh (dd/mm/yyyy hoặc dd/mm/yy)
    final dobPatterns = [
      RegExp(r'\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})\b'), // dd/mm/yyyy
      RegExp(r'\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{2})\b'), // dd/mm/yy
    ];

    for (final pattern in dobPatterns) {
      final dobMatch = pattern.firstMatch(normalizedText);
      if (dobMatch != null) {
        try {
          final day = int.parse(dobMatch.group(1)!);
          final month = int.parse(dobMatch.group(2)!);
          int year = int.parse(dobMatch.group(3)!);
          
          // Nếu năm chỉ có 2 chữ số, giả định là 19xx hoặc 20xx
          if (year < 100) {
            year = year < 50 ? 2000 + year : 1900 + year;
          }

          if (year >= 1900 && year <= DateTime.now().year &&
              month >= 1 && month <= 12 &&
              day >= 1 && day <= 31) {
            dateOfBirth = DateTime(year, month, day);
            // Kiểm tra xem ngày có hợp lệ không
            if (dateOfBirth.day == day && dateOfBirth.month == month) {
              break;
            }
          }
        } catch (e) {
          // Ignore parse errors
        }
      }
    }

    // Tìm giới tính (NAM/NỮ hoặc MALE/FEMALE)
    if (RegExp(r'\b(NAM|NỮ|MALE|FEMALE)\b').hasMatch(normalizedText)) {
      final genderMatch = RegExp(r'\b(NAM|NỮ|MALE|FEMALE)\b')
          .firstMatch(normalizedText);
      if (genderMatch != null) {
        final g = genderMatch.group(0)!;
        gender = (g == 'NAM' || g == 'MALE') ? 'Nam' : 'Nữ';
      }
    }

    // Tìm quốc tịch (VIỆT NAM hoặc VIET NAM)
    if (RegExp(r'\b(VIỆT\s*NAM|VIET\s*NAM)\b').hasMatch(normalizedText)) {
      nationality = 'Việt Nam';
    }

    // Nếu chưa có tên, thử tìm lại bằng pattern (fallback)
    if (fullName == null) {
      final namePatterns = [
        RegExp(r'(?:HỌ\s*TÊN|HỌ\s*VÀ\s*TÊN)[:\s]+([A-ZÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ\s]{5,50})', caseSensitive: false),
        RegExp(r'^([A-ZÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ\s]{5,50})', caseSensitive: false, multiLine: true),
      ];

      for (final pattern in namePatterns) {
        final nameMatch = pattern.firstMatch(normalizedText);
        if (nameMatch != null) {
          final name = nameMatch.group(1)?.trim();
          if (name != null && 
              name.length >= 5 && 
              name.length <= 50 &&
              !RegExp(r'\d').hasMatch(name) &&
              !name.contains('PHƯỜNG') &&
              !name.contains('QUẬN') &&
              !name.contains('HUYỆN') &&
              !name.contains('TỈNH') &&
              !name.contains('THÀNH PHỐ')) {
            fullName = _normalizeVietnameseName(name);
            break;
          }
        }
      }
    }

    // Chỉ trả về thông tin nếu có ít nhất CCCD hoặc họ tên
    if (nationalId != null || fullName != null) {
      return CccdInfo(
        fullName: fullName,
        nationalId: nationalId,
        dateOfBirth: dateOfBirth,
        gender: gender,
        nationality: nationality,
        address: address,
        rawText: normalizedText,
      );
    }

    return null;
  }

  void dispose() {
    _textRecognizer.close();
  }
}

/// Model chứa thông tin đã trích xuất từ CCCD
class CccdInfo {
  final String? fullName;
  final String? nationalId;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? nationality;
  final String? address;
  final String? rawText;

  CccdInfo({
    this.fullName,
    this.nationalId,
    this.dateOfBirth,
    this.gender,
    this.nationality,
    this.address,
    this.rawText,
  });

  @override
  String toString() {
    return 'CccdInfo{'
        'fullName: $fullName, '
        'nationalId: $nationalId, '
        'dateOfBirth: $dateOfBirth, '
        'gender: $gender, '
        'nationality: $nationality, '
        'address: $address'
        '}';
  }
}

