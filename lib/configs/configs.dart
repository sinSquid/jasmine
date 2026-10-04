import 'package:flutter/material.dart';
import 'package:jasmine/basic/platform.dart';
import 'package:jasmine/configs/Authentication.dart';
import 'package:jasmine/configs/android_display_mode.dart';
import 'package:jasmine/configs/android_version.dart';
import 'package:jasmine/configs/always_enter_browser.dart';
import 'package:jasmine/configs/app_font_size.dart';
import 'package:jasmine/configs/app_orientation.dart';
import 'package:jasmine/configs/display_jmcode.dart';
import 'package:jasmine/configs/download_thread_count.dart';
import 'package:jasmine/configs/drag_region_lock.dart';
import 'package:jasmine/configs/comic_seal.dart';
import 'package:jasmine/configs/esc_to_pop.dart';
import 'package:jasmine/configs/gesture_speed.dart';
import 'package:jasmine/configs/no_animation.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/passed.dart';
import 'package:jasmine/configs/proxy.dart';
import 'package:jasmine/configs/reader_zoom_scale.dart';
import 'package:jasmine/configs/recommend_links.dart';
import 'package:jasmine/configs/search_title_words.dart';
import 'package:jasmine/configs/theme.dart';
import 'package:jasmine/configs/two_page_direction.dart';
import 'package:jasmine/configs/using_right_click_pop.dart';
import 'package:jasmine/configs/volume_key_control.dart';
import 'package:jasmine/configs/web_dav_password.dart';
import 'package:jasmine/configs/web_dav_sync_switch.dart';
import 'package:jasmine/configs/web_dav_url.dart';
import 'package:jasmine/configs/web_dav_username.dart';

import 'auto_clean.dart';
import 'categories_sort.dart';
import 'download_and_export_to.dart';
import 'export_path.dart';
import 'export_rename.dart';
import 'disable_recommend_content.dart';
import 'ignore_upgrade_pop.dart';
import 'ignore_view_log.dart';
import 'dart:async';
import 'network_api_host.dart';
import 'network_cdn_host.dart';
import 'reader_controller_type.dart';
import 'reader_direction.dart';
import 'reader_slider_position.dart';
import 'reader_type.dart';
import 'versions.dart';
import 'login.dart';
import 'pager_controller_mode.dart';
import 'pager_view_mode.dart';

Future initConfigs(BuildContext context) async {
  await initAlwaysEnterBrowser();
  await initPassed();
  await initAndroidVersion();
  await initAndroidDisplayMode();
  await initVersion();
  await initApiHost();
  await initCdnHost();
  final independent = <Future<dynamic> Function()>[
    initPagerControllerMode,
    initPagerViewMode,
    initReaderType,
    initTwoPageDirection,
    initReaderDirection,
    initReaderControllerType,
    initReaderSliderPosition,
    initGestureSpeed,
    initDragRegionLock,
    initReaderZoomScale,
    initPagerColumnCount,
    initPagerCoverRate,
    initAutoClean,
    initTheme,
    initDisableRecommendContent,
    initExportPath,
    initDownloadThreadCount,
    initProxy,
    initUsingRightClickPop,
    initEscToPop,
    initComicSealConfig,
    initWebDavSyncSwitch,
    initWebDavUrl,
    initWebDavUserName,
    initWebDavPassword,
    initVolumeKeyControl,
    initNoAnimation,
    initDownloadAndExportTo,
    initExportRename,
  ];
  for (var i = 0; i < independent.length; i += 3) {
    await Future.wait(independent.skip(i).take(3).map((load) => load()));
  }
  await initLogin(context);
  await initDisplayJmcode();
  await initSearchTitleWords();
  await initCategoriesSort();
  await initAuthentication();
  await initFontSizeAdjust();
  await initAppOrientation();
  await initIgnoreVewLog();
  await initIgnoreUpgradePop();
  unawaited(initRecommendLinks());
  if (normalPlatform) autoCheckNewVersion();
}
