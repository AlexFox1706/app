import 'package:flutter/services.dart';

/// Тип звуков в системном выборе мелодии.
enum SoundKind {
  notification('Звуки уведомлений'),
  alarm('Мелодии будильника'),
  ringtone('Рингтоны');

  final String label;
  const SoundKind(this.label);
}

class PickedSound {
  final String uri;
  final String title;
  const PickedSound(this.uri, this.title);
}

/// Мост к нативному коду (MainActivity.kt): выбор звука, батарея, настройки.
class DeviceBridge {
  static const _ch = MethodChannel('task_reminder/device');

  /// Открывает системный выбор мелодии. null — пользователь отменил выбор.
  static Future<PickedSound?> pickSound({required SoundKind kind, String? currentUri}) async {
    final res = await _ch.invokeMapMethod<String, String>('pickSound', {
      'kind': kind.name,
      'current': currentUri,
    });
    if (res == null || res['uri'] == null) return null;
    return PickedSound(res['uri']!, res['title'] ?? 'Звук');
  }

  static Future<bool> isIgnoringBatteryOptimizations() async =>
      (await _ch.invokeMethod<bool>('isIgnoringBatteryOptimizations')) ?? false;

  static Future<void> requestIgnoreBatteryOptimizations() =>
      _ch.invokeMethod('requestIgnoreBatteryOptimizations');

  static Future<void> openAppSettings() => _ch.invokeMethod('openAppSettings');

  /// Android 14+: разрешены ли полноэкранные уведомления.
  static Future<bool> canUseFullScreenIntent() async =>
      (await _ch.invokeMethod<bool>('canUseFullScreenIntent')) ?? true;

  static Future<bool> isDeviceLocked() async =>
      (await _ch.invokeMethod<bool>('isDeviceLocked')) ?? false;

  /// Запрашивает доступ к аудиофайлам (нужен для мелодий из памяти телефона).
  static Future<bool> ensureAudioPermission() async =>
      (await _ch.invokeMethod<bool>('ensureAudioPermission')) ?? false;

  /// Экран напоминания закрыт: перестаём показываться поверх блокировки.
  /// Возвращает true, если телефон был заблокирован (приложение ушло в фон).
  static Future<bool> releaseLockScreen() async {
    try {
      return (await _ch.invokeMethod<bool>('releaseLockScreen')) ?? false;
    } on PlatformException {
      return false;
    }
  }
}
