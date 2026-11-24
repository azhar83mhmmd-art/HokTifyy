import 'package:streambeats/core/config/app_config.dart';
import 'dart:developer';

import 'package:streambeats/core/constants/setting_keys.dart';
import 'package:streambeats/services/streambeats_updater_tools.dart';
import 'package:streambeats/services/db/dao/settings_dao.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'global_events_state.dart';

class GlobalEventsCubit extends Cubit<GlobalEventsState> {
  final SettingsDAO _settingsDao;

  GlobalEventsCubit({required SettingsDAO settingsDao})
      : _settingsDao = settingsDao,
        super(GlobalEventsInitial()) {
    checkForUpdates();
  }

  void checkForUpdates() async {
    final Map<String, dynamic> updates = await getAppUpdates();
    log("Checking for updates...", name: 'GlobalEventsCubit');

    if (updates['changelogs'] != null) {
      emit(WhatIsNewState(changeLogs: updates['changelogs']));
    }

    // Pop up update selalu ditampilkan selama ada versi baru
    // (tidak lagi bergantung pada toggle "notifikasi update").
    if (updates["results"] == true) {
      emit(UpdateAvailable(
        newVersion: updates["newVer"],
        newBuild: updates["newBuild"],
        downloadUrl: updates["download_url"] ?? AppConfig.websiteUrl,
      ));
    }
  }

  void showAlertDialog(String title, String content) {
    emit(AlertDialogState(title: title, content: content));
  }
}
