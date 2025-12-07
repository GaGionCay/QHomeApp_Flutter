import 'package:flutter/services.dart';

/// TextInputFormatter để format số với dấu phẩy phân cách hàng nghìn
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Nếu text rỗng, return empty
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Chỉ cho phép số
    String text = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // Nếu không có số nào, return empty
    if (text.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Format với dấu phẩy
    String formatted = _formatNumber(text);

    // Tính toán vị trí cursor mới
    // Lấy số ký tự số trong text cũ và mới (bỏ dấu phẩy)
    String oldTextDigits = oldValue.text.replaceAll(RegExp(r'[^\d]'), '');
    int oldDigitCount = oldTextDigits.length;
    int newDigitCount = text.length;
    
    int selectionIndex;
    
    // Nếu số ký tự số tăng lên (user đang thêm số), đặt cursor ở cuối
    if (newDigitCount > oldDigitCount) {
      selectionIndex = formatted.length;
    } else if (newDigitCount < oldDigitCount) {
      // User đang xóa, tính toán vị trí cursor dựa trên số ký tự số còn lại
      // Đếm số ký tự số trước cursor cũ
      String textBeforeCursor = oldValue.text.substring(0, oldValue.selection.baseOffset);
      int digitsBeforeCursor = textBeforeCursor.replaceAll(RegExp(r'[^\d]'), '').length;
      
      // Đảm bảo không vượt quá số ký tự số mới
      digitsBeforeCursor = digitsBeforeCursor > newDigitCount ? newDigitCount : digitsBeforeCursor;
      
      // Tìm vị trí tương ứng trong formatted text
      int currentDigitCount = 0;
      selectionIndex = formatted.length;
      for (int i = 0; i < formatted.length; i++) {
        if (formatted[i] != ',') {
          currentDigitCount++;
          if (currentDigitCount >= digitsBeforeCursor) {
            selectionIndex = i + 1;
            break;
          }
        }
      }
    } else {
      // Số ký tự số không đổi (có thể user đang paste hoặc thay thế)
      // Đếm số ký tự số trước cursor cũ
      String textBeforeCursor = oldValue.text.substring(0, oldValue.selection.baseOffset);
      int digitsBeforeCursor = textBeforeCursor.replaceAll(RegExp(r'[^\d]'), '').length;
      
      // Tìm vị trí tương ứng trong formatted text
      int currentDigitCount = 0;
      selectionIndex = formatted.length;
      for (int i = 0; i < formatted.length; i++) {
        if (formatted[i] != ',') {
          currentDigitCount++;
          if (currentDigitCount >= digitsBeforeCursor) {
            selectionIndex = i + 1;
            break;
          }
        }
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: selectionIndex),
    );
  }

  String _formatNumber(String number) {
    // Đảo ngược chuỗi để thêm dấu phẩy từ phải sang trái
    String reversed = number.split('').reversed.join();
    String formatted = '';
    
    for (int i = 0; i < reversed.length; i++) {
      if (i > 0 && i % 3 == 0) {
        formatted += ',';
      }
      formatted += reversed[i];
    }
    
    // Đảo ngược lại
    return formatted.split('').reversed.join();
  }
}

/// Helper để parse số từ formatted string (bỏ dấu phẩy)
double? parseFormattedNumber(String formattedNumber) {
  if (formattedNumber.isEmpty) return null;
  String cleanNumber = formattedNumber.replaceAll(',', '');
  return double.tryParse(cleanNumber);
}


