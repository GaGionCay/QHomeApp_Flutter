/// App configuration for development
/// Set your ngrok URL here if automatic discovery fails
class AppConfig {
  /// Manual ngrok URL override
  /// Set this to your ngrok URL if automatic discovery fails
  /// Example: 'https://porsha-provisionless-jocelynn.ngrok-free.dev'
  /// Leave null to use automatic discovery
  static const String? manualNgrokUrl = null; // Auto-discovery enabled
  
  /// Enable debug logging for backend discovery
  static const bool debugDiscovery = true;
}
