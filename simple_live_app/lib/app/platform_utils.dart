import 'dart:io';

class PlatformUtils {
  PlatformUtils._();

  static bool get isMobileApp => Platform.isAndroid || Platform.isIOS;

  /// 同屏多开。桌面端优先开独立窗口，手机和平板进入应用内同屏页。
  static bool get supportsInlineMultiRoom => true;
}
