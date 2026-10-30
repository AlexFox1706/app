// Дописывает в android/app/build.gradle(.kts) то, что нужно плагину
// flutter_local_notifications: core library desugaring.
// Запуск из корня проекта:  dart run tool/patch_android.dart
import 'dart:io';

void main() {
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final file = kts.existsSync() ? kts : groovy;
  if (!file.existsSync()) {
    stderr.writeln('Не найден android/app/build.gradle(.kts). Сначала выполните flutter create (см. README).');
    exit(1);
  }
  final isKts = file.path.endsWith('.kts');
  var s = file.readAsStringSync();

  if (s.contains('desugar_jdk_libs')) {
    stdout.writeln('Уже настроено: ${file.path}');
    return;
  }

  final enable = isKts ? 'isCoreLibraryDesugaringEnabled = true' : 'coreLibraryDesugaringEnabled true';
  final dep = isKts
      ? 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
      : "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'";

  // 1. compileOptions { isCoreLibraryDesugaringEnabled = true }
  final co = RegExp(r'compileOptions\s*\{');
  if (co.hasMatch(s)) {
    s = s.replaceFirstMapped(co, (m) => '${m[0]}\n        $enable');
  } else {
    final android = RegExp(r'android\s*\{');
    s = s.replaceFirstMapped(android, (m) => '${m[0]}\n    compileOptions {\n        $enable\n    }');
  }

  // 2. dependencies { coreLibraryDesugaring(...) }
  final deps = RegExp(r'\ndependencies\s*\{');
  if (deps.hasMatch(s)) {
    s = s.replaceFirstMapped(deps, (m) => '${m[0]}\n    $dep');
  } else {
    s = '${s.trimRight()}\n\ndependencies {\n    $dep\n}\n';
  }

  file.writeAsStringSync(s);
  stdout.writeln('Готово: ${file.path} — включён desugaring.');
}
