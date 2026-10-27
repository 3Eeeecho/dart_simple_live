import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';

class MpvOptionsService {
  static const int maxLookbackMinutes = 15;
  static const int lookbackMebibytesPerMinute = 80;
  static const int androidLookbackMebibytesPerMinute = 32;
  static const String androidFsrAsset = 'assets/mpv/fsr_easu.glsl';

  static const Map<String, String> profileLabels = {
    "performance": "流畅",
    "balanced": "均衡",
    "quality": "画质",
  };

  static int clampLookbackMinutes(int minutes) {
    if (minutes < 0) {
      return 0;
    }
    if (minutes > maxLookbackMinutes) {
      return maxLookbackMinutes;
    }
    return minutes;
  }

  /// Byte cap for already-played data. Zero minutes keeps the old 8MiB back buffer.
  static String lookbackBackBytesLabel(
    int minutes, {
    int? mebibytesPerMinute,
  }) {
    final clamped = clampLookbackMinutes(minutes);
    if (clamped == 0) {
      return "8MiB";
    }
    final perMinute = mebibytesPerMinute ?? lookbackMebibytesPerMinute;
    return "${clamped * perMinute}MiB";
  }

  static String lookbackMaxBytesLabel(
    int minutes, {
    int? mebibytesPerMinute,
  }) {
    final clamped = clampLookbackMinutes(minutes);
    if (clamped == 0) {
      return "16MiB";
    }
    final perMinute = mebibytesPerMinute ?? lookbackMebibytesPerMinute;
    return "${clamped * perMinute + 32}MiB";
  }

  static int lookbackMebibytesForPlatform() {
    return Platform.isAndroid
        ? androidLookbackMebibytesPerMinute
        : lookbackMebibytesPerMinute;
  }

  static String windowsHwdec({required bool nvidiaSuperResolution}) {
    return nvidiaSuperResolution ? "d3d11va" : "d3d11va-copy";
  }

  static String androidSuperResolutionHwdec({required bool hardwareDecode}) {
    return hardwareDecode ? "mediacodec-copy" : "no";
  }

  static bool androidSuperResolutionActive(AppSettingsController settings) {
    return Platform.isAndroid &&
        settings.androidSuperResolution.value &&
        !settings.powerSaveMode.value;
  }

  static const Map<String, Map<String, String>> desktopProfiles = {
    "performance": {
      "profile": "fast",
      "hwdec": "auto-safe",
      "vo": "gpu",
      "scale": "bilinear",
      "cscale": "bilinear",
      "dscale": "bilinear",
      "correct-downscaling": "no",
      "sigmoid-upscaling": "no",
      "deband": "no",
    },
    "balanced": <String, String>{},
    "balancedDesktop": {
      "profile": "gpu-hq",
      "hwdec": "auto-safe",
      "vo": "gpu",
      "scale": "spline36",
      "cscale": "spline36",
      "dscale": "mitchell",
      "deband": "no",
    },
    "quality": {
      "profile": "gpu-hq",
      "hwdec": "auto-safe",
      "vo": "gpu-next",
      "scale": "ewa_lanczossharp",
      "cscale": "ewa_lanczossoft",
      "dscale": "mitchell",
      "correct-downscaling": "yes",
      "sigmoid-upscaling": "yes",
      "deband": "yes",
    },
    // 省电模式下的画质档替代：spline36 缩放，避开 gpu-next 与
    // EWA/sigmoid/deband 等每帧额外着色器 pass
    "qualityPowerSave": {
      "hwdec": "auto-safe",
      "vo": "gpu",
      "scale": "spline36",
      "cscale": "spline36",
      "dscale": "mitchell",
      "correct-downscaling": "no",
      "sigmoid-upscaling": "no",
      "deband": "no",
    },
  };

  static Map<String, String> effectiveOptions() {
    return effectiveOptionsWithSource().options;
  }

  static MpvEffectiveOptions effectiveOptionsWithSource() {
    final settings = AppSettingsController.instance;
    final profile = settings.mpvProfile.value;
    final profileOptions = _profileOptionsForPlatform(profile);
    final options = <String, String>{...profileOptions};
    final source = <String, String>{
      for (final key in profileOptions.keys) key: "profile:$profile",
    };
    if (settings.customPlayerOutput.value) {
      final vo = settings.videoOutputDriver.value.trim();
      final hwdec = settings.videoHardwareDecoder.value.trim();
      final ao = settings.audioOutputDriver.value.trim();
      if (vo.isNotEmpty) {
        options["vo"] = vo;
        source["vo"] = "custom";
      }
      if (hwdec.isNotEmpty) {
        options["hwdec"] = hwdec;
        source["hwdec"] = "custom";
      }
      if (ao.isNotEmpty) {
        options["ao"] = ao;
        source["ao"] = "custom";
      }
    }
    if ((Platform.isWindows || Platform.isAndroid) &&
        settings.lookbackLimitMinutes.value > 0) {
      final minutes = settings.lookbackLimitMinutes.value;
      final perMinute = lookbackMebibytesForPlatform();
      options["demuxer-max-back-bytes"] = lookbackBackBytesLabel(
        minutes,
        mebibytesPerMinute: perMinute,
      );
      options["demuxer-max-bytes"] = lookbackMaxBytesLabel(
        minutes,
        mebibytesPerMinute: perMinute,
      );
      source["demuxer-max-back-bytes"] = "lookback";
      source["demuxer-max-bytes"] = "lookback";
    }
    if (Platform.isWindows && settings.nvidiaSuperResolution.value) {
      options["vf"] = "d3d11vpp=scale=2:scaling-mode=nvidia";
      options["gpu-api"] = "d3d11";
      source["vf"] = "nvidia-vsr";
      source["gpu-api"] = "nvidia-vsr";
    }
    final advancedOptions = parseOptions(settings.mpvAdvancedOptions.value);
    options.addAll(advancedOptions);
    for (final key in advancedOptions.keys) {
      source[key] = "advanced";
    }
    final confOptions = parseConfFile(settings.importedMpvConfPath.value);
    options.addAll(confOptions);
    for (final key in confOptions.keys) {
      source[key] = "conf";
    }
    return MpvEffectiveOptions(options, source);
  }

  static VideoControllerConfiguration videoControllerConfiguration() {
    final settings = AppSettingsController.instance;
    if (androidSuperResolutionActive(settings)) {
      return VideoControllerConfiguration(
        vo: "gpu",
        hwdec: androidSuperResolutionHwdec(
          hardwareDecode: settings.hardwareDecode.value,
        ),
        // scale > 1 asks the Android surface to grow beyond the source,
        // up to this factor and the current screen. The FSR hook only runs
        // when that output is larger than the luma plane.
        scale: 2.0,
        enableHardwareAcceleration: settings.hardwareDecode.value,
        androidAttachSurfaceAfterVideoParameters: true,
      );
    }
    if (settings.playerCompatMode.value && Platform.isAndroid) {
      return const VideoControllerConfiguration(
        vo: 'mediacodec_embed',
        hwdec: 'mediacodec',
      );
    }
    final effectiveOptions = effectiveOptionsWithSource();
    final options = effectiveOptions.options;
    if (!Platform.isAndroid) {
      return VideoControllerConfiguration(
        hwdec: _desktopVideoControllerHwdec(effectiveOptions),
        enableHardwareAcceleration: settings.hardwareDecode.value,
      );
    }
    return VideoControllerConfiguration(
      vo: options["vo"],
      hwdec: options["hwdec"],
      enableHardwareAcceleration: settings.hardwareDecode.value,
      // Fix Issue #57: 安卓全屏后画面卡死 - 延迟attach避免surface race condition
      androidAttachSurfaceAfterVideoParameters: true,
    );
  }

  /// 网络重连与缓存默认参数（移动端直播防断流）。
  /// 用户在高级参数/mpv.conf 中设置的同名参数会覆盖这些默认值。
  static const Map<String, String> networkDefaultOptions = {
    'network-timeout': '30',
    'stream-lavf-o':
        'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=10',
    'cache': 'yes',
    'demuxer-readahead-secs': '2',
    'demuxer-max-bytes': '16MiB',
    'demuxer-max-back-bytes': '8MiB',
  };

  static Future<void> applyToPlayer(Player player) async {
    if (player.platform is! NativePlayer) {
      return;
    }
    final nativePlayer = player.platform as dynamic;
    // iOS 的视频管线固定，只应用网络默认参数；audio-exclusive 使 mpv 不使用
    // MixWithOthers，与 AppDelegate 的 .playback 类别保持一致。
    if (Platform.isIOS) {
      final iosOptions = <String, String>{
        ...networkDefaultOptions,
        'audio-exclusive': 'yes',
      };
      for (final entry in iosOptions.entries) {
        try {
          await nativePlayer.setProperty(entry.key, entry.value);
        } catch (e) {
          Log.d("mpv ios option skipped: ${entry.key}=${entry.value} $e");
        }
      }
      return;
    }
    final options = Map<String, String>.from(networkDefaultOptions)
      ..addAll(effectiveOptions())
      ..remove("vo")
      ..remove("hwdec");
    final settings = AppSettingsController.instance;
    if (androidSuperResolutionActive(settings) &&
        !options.containsKey("glsl-shaders")) {
      final shader = await ensureAndroidFsrShader();
      if (shader != null) {
        options["glsl-shaders"] = shader;
      }
    }
    for (final entry in options.entries) {
      try {
        await nativePlayer.setProperty(entry.key, entry.value);
      } catch (e) {
        Log.d("mpv option skipped: ${entry.key}=${entry.value} $e");
      }
    }
  }

  static Future<String?> ensureAndroidFsrShader() async {
    try {
      final support = await getApplicationSupportDirectory();
      final file = File(p.join(support.path, "mpv", "fsr_easu.glsl"));
      if (!await file.exists() || await file.length() < 1000) {
        final data = await rootBundle.load(androidFsrAsset);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      return file.path;
    } catch (e, stackTrace) {
      Log.e("准备安卓超分着色器失败: $e", stackTrace);
      return null;
    }
  }

  static Map<String, String> _profileOptionsForPlatform(String profile) {
    Map<String, String> base;
    final powerSave = AppSettingsController.instance.powerSaveMode.value;
    if (powerSave) {
      // 省电模式：均衡→bilinear，画质→spline36，流畅档本就是 bilinear 不变
      final powerSaveKey = profile == "balanced"
          ? "performance"
          : profile == "quality"
          ? "qualityPowerSave"
          : profile;
      base =
          desktopProfiles[powerSaveKey] ?? desktopProfiles["performance"]!;
    } else if (profile == "balanced") {
      base = Platform.isWindows
          ? desktopProfiles["balanced"]!
          : desktopProfiles["balancedDesktop"]!;
    } else {
      base = desktopProfiles[profile] ?? desktopProfiles["balanced"]!;
    }
    // Windows: d3d11va-copy avoids #115 zero-copy black screen on slim mpv.
    if (Platform.isWindows) {
      base = {
        ...base,
        "hwdec": windowsHwdec(
          nvidiaSuperResolution:
              AppSettingsController.instance.nvidiaSuperResolution.value,
        ),
      };
    }
    return base;
  }

  static String? _desktopVideoControllerHwdec(MpvEffectiveOptions options) {
    return options.options["hwdec"];
  }

  static String diagnosticsSummary() {
    final effectiveOptions = effectiveOptionsWithSource();
    final options = effectiveOptions.options;
    String value(String key) {
      final optionValue = options[key];
      final source = effectiveOptions.source[key];
      if (optionValue == null || optionValue.isEmpty) {
        return "default";
      }
      return source == null ? optionValue : "$optionValue($source)";
    }

    return "profile=${AppSettingsController.instance.mpvProfile.value}, "
        "powerSave=${AppSettingsController.instance.powerSaveMode.value}, "
        "hardwareDecode=${AppSettingsController.instance.hardwareDecode.value}, "
        "vo=${value("vo")}, hwdec=${value("hwdec")}, "
        "mpvOptions=${options.length}";
  }

  static Map<String, String> parseOptions(String raw) {
    final result = <String, String>{};
    for (final rawLine in raw.split(RegExp(r"\r?\n"))) {
      final line = _stripComment(rawLine).trim();
      if (line.isEmpty) {
        continue;
      }
      final entry = _parseLine(line);
      if (entry != null) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  static Map<String, String> parseConfFile(String path) {
    if (path.trim().isEmpty) {
      return const {};
    }
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return const {};
      }
      return parseOptions(file.readAsStringSync());
    } catch (e) {
      Log.d("read mpv.conf failed: $e");
      return const {};
    }
  }

  static Future<String?> importMpvConf() async {
    final picked = await FilePicker.platform.pickFiles(
      allowedExtensions: ["conf"],
      type: FileType.custom,
    );
    final sourcePath = picked?.files.single.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      return null;
    }
    final supportDir = await getApplicationSupportDirectory();
    final targetDir = Directory(p.join(supportDir.path, "mpv"));
    await targetDir.create(recursive: true);
    final targetPath = p.join(targetDir.path, "mpv.conf");
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  static MapEntry<String, String>? _parseLine(String line) {
    final normalized =
        line.startsWith("--") ? line.substring(2).trimLeft() : line;
    final equalIndex = normalized.indexOf("=");
    if (equalIndex > 0) {
      return MapEntry(
        normalized.substring(0, equalIndex).trim(),
        normalized.substring(equalIndex + 1).trim(),
      );
    }
    final match = RegExp(r"^([^\s]+)\s+(.+)$").firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return MapEntry(match.group(1)!.trim(), match.group(2)!.trim());
  }

  static String _stripComment(String line) {
    final index = line.indexOf("#");
    if (index < 0) {
      return line;
    }
    return line.substring(0, index);
  }
}

class MpvEffectiveOptions {
  final Map<String, String> options;
  final Map<String, String> source;

  const MpvEffectiveOptions(this.options, this.source);
}
