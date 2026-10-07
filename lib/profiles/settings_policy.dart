class SettingsPolicy {
  static const playerMode = 'NON_GYRO';
  static const inputMode = 'TOUCH_ONLY';
  static const weapons = ['M416', 'AUG', 'SCAR-L', 'AKM', 'ACE32', 'UMP45', 'DP-28'];
  static const scopes = ['Iron Sight', 'Red Dot', 'Holo', '2x', '3x', '4x', '6x', '8x'];
  static const allowedSettings = {
    'ads', 'camera', 'fireButtonSize', 'fireButtonX', 'fireButtonY',
    'joystickSize', 'joystickX', 'joystickY', 'sprintActivation',
    'peekButtonSize', 'peekButtonX', 'peekButtonY', 'throwableCamera',
    'throwButtonSize', 'throwButtonX', 'throwButtonY', 'cookButtonSize',
    'cancelButtonSize', 'fov',
  };
  static void validate(Map<String, double> settings) {
    for (final entry in settings.entries) {
      final parts = entry.key.split('::');
      if (parts.length != 2 || parts.first.split('|').length != 4 ||
          !allowedSettings.contains(parts.last) ||
          !entry.value.isFinite || entry.value < 0 || entry.value > 400) {
        throw ArgumentError('إعداد غير مسموح أو قيمة غير صحيحة: ${entry.key}');
      }
      final context = parts.first.split('|');
      final distance = double.tryParse(context.last);
      if (context.take(3).any((s) => s.trim().isEmpty) ||
          distance == null || !distance.isFinite || distance <= 0) {
        throw ArgumentError('يلزم سلاح وسكوب وملحق ومسافة موجبة.');
      }
    }
  }
  static Map<String, dynamic> get nonGyro => {
    'playerMode': playerMode, 'inputMode': inputMode,
    'gyroscope': false, 'adsGyroscope': false,
  };
}
