import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/services/android_video_output_size.dart';
import 'package:simple_live_app/services/live_subtitle_service.dart';
import 'package:simple_live_app/services/lookback_span.dart';
import 'package:simple_live_app/widgets/superchat_card.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:window_manager/window_manager.dart';

Widget playerControls(
  VideoState videoState,
  LiveRoomController controller,
) {
  return Obx(() {
    if (controller.fullScreenState.value) {
      return buildFullControls(
        videoState,
        controller,
      );
    }
    return buildControls(
      videoState.context.orientation == Orientation.portrait,
      videoState,
      controller,
    );
  });
}

EdgeInsets _fullScreenControlPadding(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  if (Platform.isIOS && mediaQuery.orientation == Orientation.landscape) {
    final padding = mediaQuery.viewPadding;
    return EdgeInsets.only(left: padding.left, right: padding.right);
  }
  return mediaQuery.padding;
}

Widget buildFullControls(
  VideoState videoState,
  LiveRoomController controller,
) {
  final padding = _fullScreenControlPadding(videoState.context);
  final volumeButtonKey = GlobalKey();
  final controls = _buildPlayerMouseRegion(
    videoState: videoState,
    controller: controller,
    child: Stack(
      children: [
        const SizedBox.expand(),
        buildDanmuView(videoState, controller),
        _buildPlayerSuperChatOverlay(controller),
        _buildBufferingIndicator(videoState),
        _buildGestureLayer(
          controller,
          enableQuickAccessLongPress: true,
        ),
        _buildLiveSubtitleOverlay(videoState.context, controller),
        _buildFullTopBar(
          controller,
          padding: padding,
        ),
        _buildFullBottomBar(
          controller,
          padding: padding,
          volumeButtonKey: volumeButtonKey,
        ),
        _buildSideLockButton(
          controller,
          padding: padding,
          alignLeft: false,
        ),
        _buildSideLockButton(
          controller,
          padding: padding,
          alignLeft: true,
        ),
        _buildGestureTip(controller),
      ],
    ),
  );

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return DragToMoveArea(child: controls);
  }
  return controls;
}

Widget buildLockButton(LiveRoomController controller) {
  return Obx(
    () => Center(
      child: InkWell(
        onTap: controller.setLockState,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: AppStyle.radius8,
          ),
          width: 40,
          height: 40,
          child: Center(
            child: Icon(
              controller.lockControlsState.value
                  ? Icons.lock_outline_rounded
                  : Icons.lock_open_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget buildControls(
  bool isPortrait,
  VideoState videoState,
  LiveRoomController controller,
) {
  final volumeButtonKey = GlobalKey();
  return _buildPlayerMouseRegion(
    videoState: videoState,
    controller: controller,
    child: Stack(
      children: [
        const SizedBox.expand(),
        buildDanmuView(videoState, controller),
        _buildPlayerSuperChatOverlay(controller),
        _buildBufferingIndicator(videoState),
        _buildGestureLayer(controller),
        _buildLiveSubtitleOverlay(videoState.context, controller),
        _buildNormalBottomBar(
          controller,
          isPortrait: isPortrait,
          volumeButtonKey: volumeButtonKey,
        ),
        _buildGestureTip(controller),
      ],
    ),
  );
}

Widget _buildPlayerMouseRegion({
  required VideoState videoState,
  required LiveRoomController controller,
  required Widget child,
}) {
  return Obx(
    () => MouseRegion(
      cursor: controller.hideMouseCursorState.value
          ? SystemMouseCursors.none
          : SystemMouseCursors.basic,
      onEnter: controller.onEnter,
      onExit: controller.onExit,
      onHover: (event) {
        controller.resetHideMouseCursorTimer();
        controller.showMouseCursor();
        controller.onHover(event, videoState.context);
      },
      child: child,
    ),
  );
}

Widget _buildPlayerSuperChatOverlay(LiveRoomController controller) {
  return Obx(() {
    if (!AppSettingsController.instance.playershowSuperChat.value) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 24,
      bottom: 24,
      child: PlayerSuperChatOverlay(controller: controller),
    );
  });
}

Widget _buildLiveSubtitleOverlay(
  BuildContext _,
  LiveRoomController controller,
) =>
    _LiveSubtitleOverlay(controller: controller);

class _LiveSubtitleOverlay extends StatefulWidget {
  final LiveRoomController controller;

  const _LiveSubtitleOverlay({
    required this.controller,
  });

  @override
  State<_LiveSubtitleOverlay> createState() => _LiveSubtitleOverlayState();
}

class _LiveSubtitleOverlayState extends State<_LiveSubtitleOverlay> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (!LiveSubtitleService.instance.uiEnabled) {
      return const SizedBox.shrink();
    }
    return Obx(() {
      final controller = widget.controller;
      final settings = AppSettingsController.instance;
      if (!settings.liveSubtitleEnable.value ||
          settings.liveSubtitleModelPath.value.trim().isEmpty ||
          LiveSubtitleService.instance.subtitleText.value.trim().isEmpty) {
        return const SizedBox.shrink();
      }

      final mediaQuery = MediaQuery.of(context);
      final padding = controller.fullScreenState.value
          ? _fullScreenControlPadding(context)
          : mediaQuery.padding;
      final alignment = Alignment(
        settings.liveSubtitleOffsetX.value * 2 - 1,
        settings.liveSubtitleOffsetY.value * 2 - 1,
      );
      final positionedPadding = EdgeInsets.only(
        left: padding.left + 24,
        right: padding.right + 24,
        top: padding.top + 24,
        bottom: padding.bottom + 24,
      );
      final subtitleColor = Color(settings.liveSubtitleColor.value);
      final locked = settings.liveSubtitlePositionLocked.value;
      final showUnlockButton = locked && _hovering;

      return Positioned.fill(
        child: Padding(
          padding: positionedPadding,
          child: Align(
            alignment: alignment,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onLongPress: locked
                    ? () {
                        settings.setLiveSubtitlePositionLocked(false);
                        SmartDialog.showToast("字幕位置已解锁");
                      }
                    : null,
                onPanUpdate: locked
                    ? null
                    : (details) {
                        final size = mediaQuery.size;
                        if (size.width <= 0 || size.height <= 0) {
                          return;
                        }
                        settings.setLiveSubtitleOffset(
                          x: settings.liveSubtitleOffsetX.value +
                              details.delta.dx / size.width,
                          y: settings.liveSubtitleOffsetY.value +
                              details.delta.dy / size.height,
                        );
                      },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: settings.liveSubtitleBackgroundEnable.value
                              ? Colors.black.withAlpha(140)
                              : Colors.transparent,
                          borderRadius: AppStyle.radius8,
                        ),
                        child: Padding(
                          padding: AppStyle.edgeInsetsA8,
                          child: Text(
                            LiveSubtitleService.instance.subtitleText.value,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: settings.liveSubtitleFontSize.value,
                              fontWeight:
                                  settings.liveSubtitleResolvedFontWeight,
                              shadows: const [
                                Shadow(
                                  color: Colors.black,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (showUnlockButton)
                      Positioned(
                        right: -12,
                        top: -12,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              settings.setLiveSubtitlePositionLocked(false);
                              SmartDialog.showToast("字幕位置已解锁");
                            },
                            child: const SizedBox(
                              width: 32,
                              height: 32,
                              child: Icon(
                                Icons.lock_open_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

Widget _buildBufferingIndicator(VideoState videoState) {
  return Center(
    child: StreamBuilder<bool>(
      stream: videoState.widget.controller.player.stream.buffering,
      initialData: videoState.widget.controller.player.state.buffering,
      builder: (_, snapshot) {
        if (!(snapshot.data ?? false)) {
          return const SizedBox.shrink();
        }
        return const CircularProgressIndicator();
      },
    ),
  );
}

Widget _buildGestureLayer(
  LiveRoomController controller, {
  bool enableQuickAccessLongPress = false,
}) {
  return Positioned.fill(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : Get.width,
          constraints.hasBoundedHeight ? constraints.maxHeight : Get.height,
        );
        return Obx(() {
          final gestureEnabled =
              AppSettingsController.instance.playerGestureControlEnable.value;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: controller.onTap,
            onDoubleTap: controller.onDoubleTap,
            onLongPress: !enableQuickAccessLongPress
                ? null
                : () {
                    if (controller.lockControlsState.value) {
                      return;
                    }
                    showQuickAccess(controller);
                  },
            onVerticalDragStart: gestureEnabled
                ? (details) => controller.onVerticalDragStart(
                      details,
                      viewportSize: viewportSize,
                    )
                : null,
            onVerticalDragUpdate:
                gestureEnabled ? controller.onVerticalDragUpdate : null,
            onVerticalDragEnd:
                gestureEnabled ? controller.onVerticalDragEnd : null,
            onVerticalDragCancel:
                gestureEnabled ? controller.onVerticalDragCancel : null,
            child: const SizedBox.expand(),
          );
        });
      },
    ),
  );
}

Widget _buildFullTopBar(
  LiveRoomController controller, {
  required EdgeInsets padding,
}) {
  return Obx(() {
    final visible = controller.showControlsState.value &&
        !controller.lockControlsState.value;
    final detail = controller.detail.value;
    final title = detail?.title ?? "直播间";
    final userName = detail?.userName ?? "";
    final displayTitle = userName.isEmpty ? title : "$title - $userName";

    return AnimatedPositioned(
      left: 0,
      right: 0,
      top: visible ? 0 : -(48 + padding.top),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: _glassBar(
        child: Container(
          height: 48 + padding.top,
          padding: EdgeInsets.only(
            left: padding.left + 12,
            right: padding.right + 12,
            top: padding.top,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black26,
                Colors.black54,
              ],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  if (controller.smallWindowState.value) {
                    controller.exitSmallWindow();
                  } else {
                    controller.exitFull();
                  }
                },
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              AppStyle.hGap12,
              Expanded(
                child: Text(
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
              AppStyle.hGap12,
              if (!controller.smallWindowState.value)
                IconButton(
                  onPressed: controller.saveScreenshot,
                  icon: const Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              if (!controller.smallWindowState.value)
                IconButton(
                  onPressed: () => showQuickAccess(controller),
                  icon: const Icon(
                    Remix.play_list_2_line,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              if (Platform.isAndroid)
                IconButton(
                  onPressed: controller.enablePIP,
                  icon: const Icon(
                    Icons.picture_in_picture,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              IconButton(
                onPressed: () => showPlayerSettings(controller),
                icon: const Icon(
                  Icons.more_horiz,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  });
}

Widget _buildFullBottomBar(
  LiveRoomController controller, {
  required EdgeInsets padding,
  required GlobalKey volumeButtonKey,
}) {
  return Obx(() {
    final visible = controller.showControlsState.value &&
        !controller.lockControlsState.value;
    final showDanmaku = controller.showDanmakuState.value;
    final smallWindow = controller.smallWindowState.value;

    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom:
          visible ? 0 : -(80 + padding.bottom + _lookbackAndSrExtraHeight()),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: _glassBar(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black26,
                Colors.black54,
              ],
            ),
          ),
          padding: EdgeInsets.only(
            left: padding.left + (smallWindow ? 4 : 12),
            right: padding.right + (smallWindow ? 4 : 12),
            bottom: padding.bottom,
          ),
          child: smallWindow
              ? _buildSmallWindowBottomBar(controller, showDanmaku)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _androidSrChip(controller),
                    _lookbackSlider(controller),
                    _fitPlayerControls(
                      children: [
                        IconButton(
                          onPressed: controller.refreshRoom,
                          icon: const Icon(
                            Remix.refresh_line,
                            color: Colors.white,
                          ),
                        ),
                        Obx(
                          () => IconButton(
                            onPressed: controller.togglePlayPauseWithRefresh,
                            icon: Icon(
                              controller.playingState.value
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        ..._lookbackButtons(controller),
                        IconButton(
                          onPressed: () {
                            controller.setDanmakuVisible(!showDanmaku);
                          },
                          icon: ImageIcon(
                            AssetImage(
                              showDanmaku
                                  ? 'assets/icons/icon_danmaku_close.png'
                                  : 'assets/icons/icon_danmaku_open.png',
                            ),
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          onPressed: () => showDanmakuSettings(controller),
                          icon: const ImageIcon(
                            AssetImage('assets/icons/icon_danmaku_setting.png'),
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            controller.liveDuration.value,
                            style: const TextStyle(
                                fontSize: 14, color: Colors.white),
                          ),
                        ),
                        const Expanded(child: SizedBox()),
                        if (!Platform.isAndroid && !Platform.isIOS)
                          IconButton(
                            key: volumeButtonKey,
                            onPressed: () {
                              final context = volumeButtonKey.currentContext;
                              if (context == null) {
                                return;
                              }
                              controller.showVolumeSlider(
                                context,
                                keepAlive: true,
                              );
                            },
                            icon: Icon(
                              controller.mutedState.value
                                  ? Icons.volume_off
                                  : Icons.volume_down,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        IconButton(
                          onPressed: controller.toggleMute,
                          icon: Icon(
                            controller.mutedState.value
                                ? Icons.volume_off
                                : Icons.volume_up,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                        TextButton(
                          onPressed: () => showQualitesInfo(controller),
                          child: Text(
                            controller.currentQualityInfo.value,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                          ),
                        ),
                        TextButton(
                          onPressed: () => showLinesInfo(controller),
                          child: Text(
                            controller.currentLineInfo.value,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                          ),
                        ),
                        if (!Platform.isAndroid && !Platform.isIOS)
                          IconButton(
                            onPressed: controller.enterSmallWindow,
                            icon: const Icon(
                              Icons.picture_in_picture,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        IconButton(
                          onPressed: () {
                            if (controller.smallWindowState.value) {
                              controller.exitSmallWindow();
                            } else {
                              controller.exitFull();
                            }
                          },
                          icon: const Icon(
                            Remix.fullscreen_exit_fill,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  });
}

double _lookbackAndSrExtraHeight() {
  var extra = 0.0;
  final settings = AppSettingsController.instance;
  if ((Platform.isWindows || Platform.isAndroid) &&
      settings.lookbackLimitMinutes.value > 0) {
    extra += 36;
  }
  if (Platform.isAndroid && settings.androidSuperResolution.value) {
    extra += 32;
  }
  return extra;
}

/// Wide windows keep the controls spread out. Narrow phones scroll the same buttons.
Widget _fitPlayerControls({required List<Widget> children}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 720) {
        return Row(children: children);
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final child in children)
              if (child is! Expanded) child,
          ],
        ),
      );
    },
  );
}

List<Widget> _lookbackButtons(LiveRoomController controller) {
  if ((!Platform.isWindows && !Platform.isAndroid) ||
      AppSettingsController.instance.lookbackLimitMinutes.value <= 0) {
    return const [];
  }
  Widget button(String label, Duration by) {
    return TextButton(
      onPressed: () => controller.seekBackward(by),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(40, 36),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      child: Text(label),
    );
  }

  return [
    button("-10秒", const Duration(seconds: 10)),
    button("-30秒", const Duration(seconds: 30)),
    button("-60秒", const Duration(seconds: 60)),
    TextButton(
      onPressed: controller.refreshRoom,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(40, 36),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      child: const Text("回到直播"),
    ),
  ];
}

/// 小窗模式的紧凑底部栏：窗口太小，只保留常用按钮
Widget _buildSmallWindowBottomBar(
  LiveRoomController controller,
  bool showDanmaku,
) {
  const compactDensity = VisualDensity.compact;
  return Row(
    children: [
      IconButton(
        onPressed: controller.togglePlayPauseWithRefresh,
        visualDensity: compactDensity,
        padding: const EdgeInsets.all(4),
        icon: Icon(
          controller.playingState.value ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
          size: 20,
        ),
      ),
      IconButton(
        onPressed: () {
          controller.setDanmakuVisible(!showDanmaku);
        },
        visualDensity: compactDensity,
        padding: const EdgeInsets.all(4),
        icon: ImageIcon(
          AssetImage(
            showDanmaku
                ? 'assets/icons/icon_danmaku_close.png'
                : 'assets/icons/icon_danmaku_open.png',
          ),
          size: 20,
          color: Colors.white,
        ),
      ),
      IconButton(
        onPressed: controller.toggleMute,
        visualDensity: compactDensity,
        padding: const EdgeInsets.all(4),
        icon: Icon(
          controller.mutedState.value ? Icons.volume_off : Icons.volume_up,
          color: Colors.white,
          size: 20,
        ),
      ),
      const Spacer(),
      IconButton(
        onPressed: controller.exitSmallWindow,
        visualDensity: compactDensity,
        padding: const EdgeInsets.all(4),
        icon: const Icon(
          Remix.fullscreen_exit_fill,
          color: Colors.white,
          size: 20,
        ),
      ),
    ],
  );
}

Widget _buildNormalBottomBar(
  LiveRoomController controller, {
  required bool isPortrait,
  required GlobalKey volumeButtonKey,
}) {
  return Obx(() {
    final showDanmaku = controller.showDanmakuState.value;
    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: controller.showControlsState.value
          ? 0
          : -(48 + _lookbackAndSrExtraHeight()),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: _glassBar(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black26,
                Colors.black54,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _androidSrChip(controller),
              _lookbackSlider(controller),
              _fitPlayerControls(
                children: [
                  IconButton(
                    onPressed: controller.refreshRoom,
                    icon: const Icon(
                      Remix.refresh_line,
                      color: Colors.white,
                    ),
                  ),
                  Obx(
                    () => IconButton(
                      onPressed: controller.togglePlayPauseWithRefresh,
                      icon: Icon(
                        controller.playingState.value
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  ..._lookbackButtons(controller),
                  IconButton(
                    onPressed: () {
                      controller.setDanmakuVisible(!showDanmaku);
                    },
                    icon: ImageIcon(
                      AssetImage(
                        showDanmaku
                            ? 'assets/icons/icon_danmaku_close.png'
                            : 'assets/icons/icon_danmaku_open.png',
                      ),
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () => showDanmakuSettings(controller),
                    icon: const ImageIcon(
                      AssetImage('assets/icons/icon_danmaku_setting.png'),
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      controller.liveDuration.value,
                      style:
                          const TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                  if (!Platform.isAndroid && !Platform.isIOS)
                    IconButton(
                      key: volumeButtonKey,
                      onPressed: () {
                        final context = volumeButtonKey.currentContext;
                        if (context == null) {
                          return;
                        }
                        controller.showVolumeSlider(
                          context,
                          keepAlive: true,
                        );
                      },
                      icon: Icon(
                        controller.mutedState.value
                            ? Icons.volume_off
                            : Icons.volume_down,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  IconButton(
                    onPressed: controller.toggleMute,
                    icon: Icon(
                      controller.mutedState.value
                          ? Icons.volume_off
                          : Icons.volume_up,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                  if (!isPortrait)
                    TextButton(
                      onPressed: () => showQualitesInfo(controller),
                      child: Text(
                        controller.currentQualityInfo.value,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                  if (!isPortrait)
                    TextButton(
                      onPressed: () => showLinesInfo(controller),
                      child: Text(
                        controller.currentLineInfo.value,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                  if (!Platform.isAndroid && !Platform.isIOS)
                    IconButton(
                      onPressed: controller.enterSmallWindow,
                      icon: const Icon(
                        Icons.picture_in_picture,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  IconButton(
                    onPressed: controller.enterFullScreen,
                    icon: const Icon(
                      Remix.fullscreen_line,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  });
}

Widget _androidSrChip(LiveRoomController controller) {
  if (!Platform.isAndroid) {
    return const SizedBox.shrink();
  }
  return Obx(() {
    final settings = AppSettingsController.instance;
    if (!settings.androidSuperResolution.value) {
      return const SizedBox.shrink();
    }
    final sourceWidth = controller.videoSourceWidth.value;
    final sourceHeight = controller.videoSourceHeight.value;
    final compareOff = controller.androidFsrCompareOff.value;
    final powerSave = settings.powerSaveMode.value;
    var label = "超分等待画面";
    var canCompare = false;
    if (powerSave) {
      label = "省电中，超分关闭";
    } else if (sourceWidth >= 2 && sourceHeight >= 2) {
      final output = androidSuperResolutionOutputForCurrentScreen(
        sourceWidth,
        sourceHeight,
      );
      final upscaling =
          output != null && output.$1 > sourceWidth && output.$2 > sourceHeight;
      if (!upscaling) {
        label = "未放大 $sourceWidth×$sourceHeight";
      } else if (compareOff) {
        label = "原图 $sourceWidth×$sourceHeight";
        canCompare = true;
      } else {
        label = "超分 $sourceWidth×$sourceHeight→${output.$1}×${output.$2}";
        canCompare = true;
      }
    }
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          if (canCompare)
            TextButton(
              onPressed: controller.toggleAndroidFsrCompare,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white24,
                minimumSize: const Size(64, 28),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(compareOff ? "看超分" : "看原图"),
            ),
        ],
      ),
    );
  });
}

Widget _lookbackSlider(LiveRoomController controller) {
  if (!Platform.isWindows && !Platform.isAndroid) {
    return const SizedBox.shrink();
  }
  return Obx(() {
    if (AppSettingsController.instance.lookbackLimitMinutes.value <= 0) {
      return const SizedBox.shrink();
    }
    final span = controller.lookbackSpan.value;
    final scrubbing = controller.lookbackScrubbing.value;
    final shown = scrubbing
        ? controller.lookbackScrubPosition.value
        : (span?.position ?? Duration.zero);
    final enabled = span != null && span.canScrub;
    final fraction = enabled ? _fractionInSpan(span, shown) : 1.0;
    final behind = span == null ? Duration.zero : span.end - shown;
    final label = enabled ? lookbackBehindLabel(behind) : "缓存中";
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 4,
                activeTrackColor: Colors.white,
                // 播放头右侧 = 前方缓冲（落后直播前沿的秒数），调亮让它可读
                inactiveTrackColor: Colors.white54,
                thumbColor: Colors.white,
                disabledActiveTrackColor: Colors.white24,
                disabledInactiveTrackColor: Colors.white24,
                disabledThumbColor: Colors.white54,
                overlayColor: Colors.white24,
                trackShape: _LookbackTrackShape(),
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: fraction.clamp(0.0, 1.0),
                onChanged: !enabled
                    ? null
                    : (value) {
                        controller.lookbackScrubbing.value = true;
                        controller.lookbackScrubPosition.value =
                            span.positionForFraction(value);
                      },
                onChangeEnd: !enabled
                    ? null
                    : (value) {
                        controller
                            .seekLookback(span.positionForFraction(value));
                      },
              ),
            ),
          ),
          TextButton(
            onPressed: controller.refreshRoom,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(40, 28),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text("直播"),
          ),
        ],
      ),
    );
  });
}

double _fractionInSpan(LookbackSpan span, Duration position) {
  if (!span.canScrub) {
    return 1;
  }
  final raw =
      (position - span.start).inMilliseconds / span.length.inMilliseconds;
  if (raw.isNaN) {
    return 1;
  }
  return raw.clamp(0.0, 1.0);
}

Widget _buildSideLockButton(
  LiveRoomController controller, {
  required EdgeInsets padding,
  required bool alignLeft,
}) {
  return Obx(() {
    final visible = controller.lockControlsState.value
        ? controller.showLockEdgeState.value
        : controller.showControlsState.value;
    final offset = -(64 + (alignLeft ? padding.left : padding.right));
    return AnimatedPositioned(
      top: 0,
      bottom: 0,
      left: alignLeft ? (visible ? padding.left + 12 : offset) : null,
      right: alignLeft ? null : (visible ? padding.right + 12 : offset),
      duration: const Duration(milliseconds: 200),
      child: buildLockButton(controller),
    );
  });
}

Widget _buildGestureTip(LiveRoomController controller) {
  return Obx(() {
    final text = controller.gestureTipText.value.trim();
    if (!controller.showGestureTip.value || text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, color: Colors.white),
        ),
      ),
    );
  });
}

Widget buildDanmuView(VideoState videoState, LiveRoomController controller) {
  var padding = controller.fullScreenState.value
      ? _fullScreenControlPadding(videoState.context)
      : MediaQuery.of(videoState.context).padding;
  return Positioned.fill(
    top: padding.top,
    bottom: padding.bottom,
    child: Obx(
      () {
        controller.danmakuViewVersion.value;

        final settings = AppSettingsController.instance;

        return Offstage(
          offstage: !controller.showDanmakuState.value,
          child: Padding(
            padding: controller.fullScreenState.value
                ? EdgeInsets.only(
                    top: AppSettingsController.instance.danmuTopMargin.value,
                    bottom:
                        AppSettingsController.instance.danmuBottomMargin.value,
                  )
                : EdgeInsets.zero,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewportHeight = constraints.maxHeight > 0
                    ? constraints.maxHeight
                    : MediaQuery.sizeOf(context).height;
                controller.updateDanmakuViewportHeight(viewportHeight);

                final resolvedLineCount = settings.resolveDanmuTargetLineCount(
                  viewportHeight: viewportHeight,
                  area: settings.danmuArea.value,
                  fontSize: settings.danmuSize.value,
                  lineCount: settings.danmuLineCount.value,
                );
                final hideDanmu = resolvedLineCount <= 0;
                return DanmakuScreen(
                  key: controller.globalDanmuKey,
                  createdController: controller.initDanmakuController,
                  option: DanmakuOption(
                    fontSize: settings.danmuSize.value,
                    fontFamily: Platform.isWindows ? "Microsoft YaHei" : null,
                    area: settings.resolveDanmuEffectiveArea(
                      viewportHeight: viewportHeight,
                      area: settings.danmuArea.value,
                      fontSize: settings.danmuSize.value,
                      lineCount: settings.danmuLineCount.value,
                    ),
                    lineHeight: settings.resolveDanmuLineHeight(
                      viewportHeight: viewportHeight,
                      area: settings.danmuArea.value,
                      fontSize: settings.danmuSize.value,
                      lineCount: settings.danmuLineCount.value,
                    ),
                    duration: settings.danmuSpeed.value.toInt(),
                    opacity: settings.danmuOpacity.value,
                    fontWeight: settings.danmuFontWeight.value,
                    showStroke: settings.effectiveDanmuStroke,
                    strokeWidth: settings.danmuStrokeWidth.value,
                    maxFps: settings.effectiveDanmuMaxFps,
                    hideTop: hideDanmu,
                    hideBottom: hideDanmu,
                    hideScroll: hideDanmu,
                    hideSpecial: hideDanmu,
                  ),
                );
              },
            ),
          ),
        );
      },
    ),
  );
}

void showLinesInfo(LiveRoomController controller) {
  if (controller.useBottomSheetPlayerMenus) {
    controller.showPlayUrlsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "线路选择",
    useSystem: true,
    child: ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: controller.playUrls.length,
      itemBuilder: (_, i) {
        return ListTile(
          selected: controller.currentLineIndex == i,
          title: Text.rich(
            TextSpan(
              text: "线路${i + 1}",
              children: [
                WidgetSpan(
                    child: Container(
                  decoration: BoxDecoration(
                    borderRadius: AppStyle.radius4,
                    border: Border.all(
                      color: Colors.grey,
                    ),
                  ),
                  padding: AppStyle.edgeInsetsH4,
                  margin: AppStyle.edgeInsetsL8,
                  child: Text(
                    controller.playUrls[i].contains(".flv") ? "FLV" : "HLS",
                    style: const TextStyle(
                      fontSize: 12,
                    ),
                  ),
                )),
              ],
            ),
            style: const TextStyle(fontSize: 14),
          ),
          minLeadingWidth: 16,
          onTap: () {
            Utils.hideRightDialog();
            //controller.currentLineIndex = i;
            //controller.setPlayer();
            controller.changePlayLine(i);
          },
        );
      },
    ),
  );
}

void showQualitesInfo(LiveRoomController controller) {
  if (controller.useBottomSheetPlayerMenus) {
    controller.showQualitySheet();
    return;
  }
  Utils.showRightDialog(
    title: "清晰度",
    useSystem: true,
    child: ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: controller.qualites.length,
      itemBuilder: (_, i) {
        var item = controller.qualites[i];
        return ListTile(
          selected: controller.currentQuality == i,
          title: Text(
            item.quality,
            style: const TextStyle(fontSize: 14),
          ),
          minLeadingWidth: 16,
          onTap: () {
            Utils.hideRightDialog();
            controller.currentQuality = i;
            // 保存清晰度记忆。
            if (i >= 0 && i < controller.qualites.length) {
              AppSettingsController.instance.saveQualityMemory(
                siteId: controller.site.id,
                qualityName: controller.qualites[i].quality,
                offsetFromTop: i,
              );
            }
            controller.getPlayUrl();
          },
        );
      },
    ),
  );
}

void showDanmakuSettings(LiveRoomController controller) {
  if (controller.useBottomSheetPlayerMenus) {
    controller.showDanmuSettingsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "弹幕设置",
    width: 400,
    useSystem: true,
    child: ListView(
      padding: AppStyle.edgeInsetsA12,
      children: [
        DanmuSettingsView(
          danmakuController: controller.danmakuController,
          siteId: controller.site.id,
          previewViewportHeight: controller.danmakuViewportHeight.value,
        ),
      ],
    ),
  );
}

void showPlayerSettings(LiveRoomController controller) {
  if (controller.useBottomSheetPlayerMenus) {
    controller.showPlayerSettingsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "设置",
    width: 320,
    useSystem: true,
    child: Obx(
      () => RadioGroup(
        groupValue: AppSettingsController.instance.scaleMode.value,
        onChanged: (e) {
          AppSettingsController.instance.setScaleMode(e ?? 0);
          controller.updateScaleMode();
        },
        child: ListView(
          padding: AppStyle.edgeInsetsV12,
          children: [
            Padding(
              padding: AppStyle.edgeInsetsH16,
              child: Text(
                "画面尺寸",
                style: Get.textTheme.titleMedium,
              ),
            ),
            const RadioListTile(
              value: 0,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("适应"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 1,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("拉伸"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 2,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("铺满"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 3,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("16:9"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 4,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("4:3"),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    ),
  );
}

void showQuickAccess(LiveRoomController controller) {
  final keys = controller.enabledQuickAccessKeys;
  if (keys.isEmpty) {
    SmartDialog.showToast("没有东西可展示");
    return;
  }
  if (keys.length == 1) {
    _openQuickAccessItem(controller, keys.single);
    return;
  }
  if (controller.useBottomSheetPlayerMenus) {
    controller.showQuickAccessSheet();
    return;
  }

  Utils.showRightDialog(
    title: "快捷入口",
    width: 320,
    useSystem: true,
    child: ListView(
      padding: AppStyle.edgeInsetsV12,
      children:
          keys.map((key) => _buildQuickAccessTile(controller, key)).toList(),
    ),
  );
}

Widget _buildQuickAccessTile(LiveRoomController controller, String key) {
  final item = Constant.allLiveRoomQuickAccess[key]!;
  final enabled =
      key != "recommendation" || controller.hasCategoryRecommendation;
  return ListTile(
    leading: Icon(item.iconData),
    title: Text(controller.quickAccessTitle(key)),
    subtitle: Text(controller.quickAccessSubtitle(key)),
    enabled: enabled,
    onTap: !enabled
        ? null
        : () async {
            await Utils.switchRightDialog(() async {
              _openQuickAccessItem(controller, key);
            });
          },
  );
}

void _openQuickAccessItem(LiveRoomController controller, String key) {
  switch (key) {
    case "follow":
      showFollowUser(controller);
      break;
    case "history":
      controller.openHistoryPage();
      break;
    case "recommendation":
      controller.openCategoryRecommendation();
      break;
    case "contribution_rank":
      controller.showContributionRankSheet();
      break;
  }
}

void showFollowUser(LiveRoomController controller) {
  if (controller.useBottomSheetPlayerMenus) {
    controller.showFollowUserSheet();
    return;
  }

  Utils.showRightDialog(
    title: "关注列表",
    width: 400,
    useSystem: true,
    child: controller.buildFollowUserSelection(
      onClose: Utils.hideRightDialog,
      scrollController: controller.liveRoomFollowDialogScrollController,
    ),
  );
}

class PlayerSuperChatCard extends StatefulWidget {
  final LiveSuperChatMessage message;
  final VoidCallback onExpire;
  final int duration;
  final VoidCallback? onUserTap;
  final VoidCallback? onUserLongPress;
  const PlayerSuperChatCard(
      {required this.message,
      required this.onExpire,
      required this.duration,
      this.onUserTap,
      this.onUserLongPress,
      Key? key})
      : super(key: key);
  @override
  State<PlayerSuperChatCard> createState() => _PlayerSuperChatCardState();
}

class _PlayerSuperChatCardState extends State<PlayerSuperChatCard> {
  Timer? timer;
  late int countdown;
  @override
  void initState() {
    super.initState();
    _restartCountdown();
  }

  void _restartCountdown() {
    timer?.cancel();
    countdown = widget.duration;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (countdown <= 1) {
        widget.onExpire();
        timer?.cancel();
        return;
      }
      setState(() {
        countdown = (countdown - 1).clamp(0, 1 << 30).toInt();
      });
    });
  }

  @override
  void didUpdateWidget(covariant PlayerSuperChatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.duration != widget.duration) {
      _restartCountdown();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.65,
      child: SuperChatCard(
        widget.message,
        onExpire: () {},
        customCountdown: countdown,
        onUserTap: widget.onUserTap,
        onUserLongPress: widget.onUserLongPress,
      ),
    );
  }
}

class LocalDisplaySC {
  LiveSuperChatMessage sc;
  final DateTime expireAt;
  final int duration;
  LocalDisplaySC(this.sc, this.expireAt, this.duration);

  String get fingerprint {
    final id = sc.id?.trim();
    if (id != null && id.isNotEmpty) {
      return "id:$id";
    }
    return "${sc.userName}|${sc.message}|${sc.price}|${sc.startTime.millisecondsSinceEpoch}";
  }
}

class PlayerSuperChatOverlay extends StatefulWidget {
  final LiveRoomController controller;
  const PlayerSuperChatOverlay({required this.controller, Key? key})
      : super(key: key);
  @override
  State<PlayerSuperChatOverlay> createState() => _PlayerSuperChatOverlayState();
}

class _PlayerSuperChatOverlayState extends State<PlayerSuperChatOverlay> {
  final List<LocalDisplaySC> _displayed = [];
  final Map<LocalDisplaySC, Timer> _timers = {};
  late Worker _worker;

  String _fingerprintOf(LiveSuperChatMessage sc) {
    final id = sc.id?.trim();
    if (id != null && id.isNotEmpty) {
      return "id:$id";
    }
    return "${sc.userName}|${sc.message}|${sc.price}|${sc.startTime.millisecondsSinceEpoch}";
  }

  void _removeLocalSC(LocalDisplaySC localSC) {
    _displayed.remove(localSC);
    _timers.remove(localSC)?.cancel();
  }

  void _addSC(LiveSuperChatMessage sc, {int? customSeconds}) {
    final fingerprint = _fingerprintOf(sc);
    int showSeconds = (customSeconds ?? 15).clamp(1, 1 << 30).toInt();
    final currentIndex = _displayed.indexWhere(
      (e) => e.fingerprint == fingerprint,
    );
    if (currentIndex >= 0) {
      final current = _displayed[currentIndex];
      current.sc = sc;
      setState(() {});
      return;
    }
    final expireAt = DateTime.now().add(Duration(seconds: showSeconds));
    final localSC = LocalDisplaySC(sc, expireAt, showSeconds);
    _displayed.add(localSC);
    _timers[localSC] = Timer(Duration(seconds: showSeconds), () {
      setState(() {
        _removeLocalSC(localSC);
      });
    });
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // 初始化时先把仍在有效期内的头条恢复到播放器悬浮层里。
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var sc in widget.controller.superChats) {
      int remain = (sc.endTime.millisecondsSinceEpoch - now) ~/ 1000;
      if (remain > 0) {
        _addSC(sc, customSeconds: remain < 15 ? remain : 15);
      }
    }
    // 监听头条列表变化，同步更新悬浮展示队列。
    _worker =
        ever<List<LiveSuperChatMessage>>(widget.controller.superChats, (list) {
      for (var sc in list) {
        final remain = sc.endTime.difference(DateTime.now()).inSeconds;
        _addSC(sc, customSeconds: remain > 0 && remain < 15 ? remain : 15);
      }
      final latestFingerprints = list.map(_fingerprintOf).toSet();
      for (final localSC in _displayed.toList()) {
        if (!latestFingerprints.contains(localSC.fingerprint)) {
          _removeLocalSC(localSC);
        }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _worker.dispose();
    for (var t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _displayed.toList()
      ..sort((a, b) => a.sc.endTime.compareTo(b.sc.endTime));
    if (AppSettingsController.instance.superChatSortDesc.value) {
      sorted.replaceRange(0, sorted.length, sorted.reversed);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var localSC in sorted)
          Padding(
            key: ValueKey(localSC.fingerprint),
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: 240,
              child: PlayerSuperChatCard(
                key: ValueKey(localSC.fingerprint),
                message: localSC.sc,
                onExpire: () {
                  setState(() {
                    _removeLocalSC(localSC);
                  });
                },
                duration: localSC.duration,
                onUserTap: () => widget.controller.showUserActions(
                  localSC.sc.userName,
                  messageContent: localSC.sc.message,
                ),
                onUserLongPress: () =>
                    widget.controller.copyUserName(localSC.sc.userName),
              ),
            ),
          ),
      ],
    );
  }
}

/// 回看进度条轨道：左侧亮色=已看过的回看区，右侧半透明=前方缓冲，
/// 最右端白点=直播前沿（缓存最新位置）。
class _LookbackTrackShape extends SliderTrackShape {
  const _LookbackTrackShape();

  @override
  Rect getPreferredRect(
      {required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      Offset offset = Offset.zero,
      bool isEnabled = false,
      bool isDiscrete = false}) {
    final height = sliderTheme.trackHeight ?? 4.0;
    return Rect.fromLTWH(
      offset.dx,
      offset.dy + (parentBox.size.height - height) / 2,
      parentBox.size.width,
      height,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    Offset? secondaryOffset,
    required Offset thumbCenter,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final canvas = context.canvas;
    final rect = getPreferredRect(
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      offset: offset,
    );
    final radius = Radius.circular(rect.height / 2);
    final t = enableAnimation.value;
    final backColor = Color.lerp(
      sliderTheme.disabledActiveTrackColor,
      sliderTheme.activeTrackColor,
      t,
    )!;
    final frontColor = Color.lerp(
      sliderTheme.disabledInactiveTrackColor,
      sliderTheme.inactiveTrackColor,
      t,
    )!;
    final thumbX = thumbCenter.dx.clamp(rect.left, rect.right);
    if (thumbX > rect.left) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(rect.left, rect.top, thumbX, rect.bottom),
          radius,
        ),
        Paint()..color = backColor,
      );
    }
    if (thumbX < rect.right) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(thumbX, rect.top, rect.right, rect.bottom),
          radius,
        ),
        Paint()..color = frontColor,
      );
    }
    // 直播前沿标记：右端内侧一个白点
    canvas.drawCircle(
      Offset(rect.right - rect.height / 2, rect.center.dy),
      rect.height * 0.9,
      Paint()..color = Color.lerp(Colors.white24, Colors.white, t)!,
    );
  }
}

/// 悬浮条玻璃效果：模糊画面背景，叠半透明渐变
// ponytail: BackdropFilter 每帧模糊有 GPU 开销，若卡顿可去掉 _glassBar 包裹
Widget _glassBar({required Widget child}) {
  return ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: child,
    ),
  );
}
