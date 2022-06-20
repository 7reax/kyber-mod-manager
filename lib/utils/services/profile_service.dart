import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:kyber_mod_manager/main.dart';
import 'package:kyber_mod_manager/utils/helpers/origin_helper.dart';
import 'package:kyber_mod_manager/utils/services/frosty_profile_service.dart';
import 'package:kyber_mod_manager/utils/services/frosty_service.dart';
import 'package:kyber_mod_manager/utils/services/mod_service.dart';
import 'package:kyber_mod_manager/utils/types/freezed/mod.dart';
import 'package:kyber_mod_manager/utils/types/frosty_config.dart';
import 'package:kyber_mod_manager/utils/types/saved_profile.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

class ProfileService {
  static final File _profileFile = File('${OriginHelper.getBattlefrontPath()}\\ModData\\SavedProfiles\\profiles.json');

  static Future<void> searchProfile(List<String> mods, [Function? onProgress]) async {
    if (!box.get('saveProfiles', defaultValue: true)) {
      return;
    }
    String battlefrontPath = OriginHelper.getBattlefrontPath();
    FrostyConfig config = FrostyService.getFrostyConfig();
    Directory dir = Directory('$battlefrontPath\\ModData\\KyberModManager');
    List<dynamic> convertedMods = mods.map((mod) => ModService.convertToFrostyMod(mod)).toList();
    List<dynamic> current = await FrostyProfileService.getModsFromProfile('KyberModManager');

    if (listEquals(current, convertedMods)) {
      Logger.root.info('Profile is already up to date');
      return;
    }

    List<SavedProfile> profiles = getSavedProfiles();
    if (profiles.where((element) => equalModlist(element.mods, convertedMods)).isEmpty) {
      if (current.isEmpty || profiles.where((element) => equalModlist(element.mods, current)).isNotEmpty) {
        return;
      }
      await _saveProfile(dir, current, onProgress);
      return;
    }

    if (current.isNotEmpty && profiles.where((element) => equalModlist(current, element.mods)).isEmpty) {
      await _saveProfile(dir, current, onProgress);
    }

    SavedProfile profile = profiles.firstWhere((element) => equalModlist(element.mods, convertedMods));
    profile.lastUsed = DateTime.now();
    _editProfile(profile);
    await copyProfileData(Directory(profile.path), dir, onProgress, true);
    config.games['starwarsbattlefrontii']?.packs?['KyberModManager'] =
        profile.mods.where((element) => element.filename.isNotEmpty).map((element) => '${element.filename}:True').join('|');
    await FrostyService.saveFrostyConfig(config);

    File file = File('${dir.path}\\patch\\mods.txt');
    if (!file.existsSync()) {
      return;
    }

    String content = await file.readAsString();
    String newContent = '';
    content.split('\n').where((element) => element.contains(':') && element.contains("' '")).map((element) {
      String filename = element.split(':')[0];
      String line = element.trim().replaceAll(RegExp(r'(\n){3,}'), "");
      var mod = ModService.getFrostyMod(filename);
      if (line.endsWith("'${mod.category}'")) {
        newContent += "$line ''\n";
      } else {
        newContent += '$line\n';
      }
    }).toList();
    if (newContent != content) {
      await file.writeAsString(newContent);
    }

    Logger.root.info('Found profile ${profile.id}');
  }

  static bool equalModlist(List<dynamic> a, List<dynamic> b) {
    return listEquals(List<String>.from(a.map((e) => e.toKyberString())), List<String>.from(b.map((e) => e.toKyberString())));
  }

  static containsMod(List<Mod> mods, Mod mod) => mods.where((element) => element.filename == mod.filename).isNotEmpty;

  static Future<void> _saveProfile(Directory dir, List<dynamic> mods, [Function? onProgress]) async {
    String id = const Uuid().v4();
    String battlefrontPath = OriginHelper.getBattlefrontPath();
    String profilePath = '$battlefrontPath\\ModData\\SavedProfiles\\$id';
    await copyProfileData(dir, Directory(profilePath), onProgress);
    int size = await getProfileSize(id);
    SavedProfile savedProfile = SavedProfile(id: id, path: profilePath, mods: mods, size: size);
    saveProfile(savedProfile);
    Logger.root.info('Saved profile ${savedProfile.id}');
  }

  static Future<void> deleteProfile(String id) async {
    List<SavedProfile> profiles = getSavedProfiles();
    SavedProfile profile = profiles.firstWhere((element) => element.id == id);
    Directory dir = Directory(profile.path);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    profiles = profiles.where((element) => element.id != id).toList();
    _saveProfiles(profiles);
  }

  static void generateFiles() {
    String path = OriginHelper.getBattlefrontPath();
    if (path.isEmpty) {
      return;
    }

    if (!_profileFile.existsSync()) {
      _profileFile.createSync(recursive: true);
      _profileFile.writeAsStringSync('[]');
    }
  }

  static Future<int> getProfileSize(String name) async {
    ReceivePort receivePort = ReceivePort();
    Isolate isolate = await Isolate.spawn(_getProfileSize, [name, receivePort.sendPort], onExit: receivePort.sendPort, paused: true);
    isolate.addOnExitListener(receivePort.sendPort);
    isolate.resume(isolate.pauseCapability!);
    return await receivePort.first;
  }

  static _getProfileSize(List<dynamic> s) {
    String battlefrontPath = OriginHelper.getBattlefrontPath();
    int size = 0;
    Directory('$battlefrontPath\\ModData\\SavedProfiles\\${s[0]}').listSync(recursive: true).forEach((element) async {
      if (element is File) {
        size += element.lengthSync();
      }
    });
    Isolate.exit(s[1], size);
  }

  static Future<void> copyProfileData(Directory from, Directory to, [Function? onProgress, bool symlink = false]) async {
    List<File> files = await _getAllFiles(from);
    WindowsTaskbar.setProgressMode(TaskbarProgressMode.normal);

    File file = files.firstWhere((element) => element.path.endsWith('layout.toc'));
    File backupFile = File(file.path.replaceAll('layout.toc', 'layout_backup.toc'));
    if (!backupFile.existsSync()) {
      await file.copy(backupFile.path);
    } else {
      files.removeWhere((element) => element.path.endsWith('layout_backup.toc'));
      await backupFile.copy(file.path);
    }

    for (File file in files) {
      if (onProgress != null) {
        onProgress(files.indexOf(file), files.length - 1);
      }
      WindowsTaskbar.setProgress(files.indexOf(file), files.length - 1);
      String dirPath = '${to.path}/${file.parent.path.substring(from.path.length)}';
      Directory dir = Directory(dirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      String path = '${to.path}${file.path.substring(from.path.length)}';
      if (!symlink) {
        await file.copy(path);
      } else {
        if (File(path).existsSync()) {
          if (await FileSystemEntity.isLink(path)) {
            await Link(path).delete();
          } else {
            await File(path).delete();
          }
        }

        try {
          await Link(path).create(file.path, recursive: true);
        } catch (e) {
          await file.copy(path);
          symlink = false;
        }
      }
    }
    WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
  }

  static bool _isSymlink(String path) {
    return File(path).resolveSymbolicLinksSync() != path;
  }

  static Future<List<File>> _getAllFiles(Directory dir) async {
    List<FileSystemEntity> files = await dir.list(recursive: true).toList();
    return List<File>.from(files.where((element) => element is File && !_isSymlink(element.path)).toList());
  }

  static void _saveProfiles(List<SavedProfile> profiles) {
    if (!_profileFile.existsSync()) {
      _profileFile.createSync();
      _profileFile.writeAsStringSync('[]');
    }
    const encoder = JsonEncoder.withIndent('  ');
    _profileFile.writeAsStringSync(encoder.convert(profiles.map((e) => e.toJson()).toList()));
  }

  static void _editProfile(SavedProfile profile) {
    const encoder = JsonEncoder.withIndent('  ');
    List<dynamic> profiles = jsonDecode(_profileFile.readAsStringSync());
    profiles.removeWhere((element) => element['id'] == profile.id);
    profiles.add(profile.toJson());
    _profileFile.writeAsStringSync(encoder.convert(profiles));
  }

  static void saveProfile(SavedProfile profile) {
    if (!_profileFile.existsSync()) {
      _profileFile.createSync();
      _profileFile.writeAsStringSync('[]');
    }
    const encoder = JsonEncoder.withIndent('  ');
    List<SavedProfile> profiles = getSavedProfiles()..add(profile);
    _profileFile.writeAsStringSync(encoder.convert(profiles.map((e) => e.toJson()).toList()));
  }

  static Future<List<SavedProfile>> getSavedProfilesAsync() async {
    if (!await _profileFile.exists()) {
      await _profileFile.create();
      _profileFile.writeAsStringSync('[]');
      return [];
    }
    List<SavedProfile> profiles =
        await _profileFile.readAsString().then((value) => List<SavedProfile>.from(jsonDecode(value).map((element) => SavedProfile.fromJson(element)).toList()));
    List<SavedProfile> profilesToRemove = profiles.where((element) => !Directory(element.path).existsSync()).toList();
    profiles.removeWhere((element) => !Directory(element.path).existsSync());
    for (SavedProfile profile in profilesToRemove) {
      deleteProfile(profile.id);
    }
    return profiles;
  }

  static List<SavedProfile> getSavedProfiles() {
    if (!_profileFile.existsSync()) {
      _profileFile.createSync(recursive: true);
      _profileFile.writeAsStringSync('[]');
      return [];
    }
    return List<SavedProfile>.from(jsonDecode(_profileFile.readAsStringSync()).map((element) => SavedProfile.fromJson(element)).toList());
  }

  static void migrateSavedProfiles() {
    if (box.containsKey('savedProfilesMigrated')) {
      return;
    }

    var profiles = getSavedProfiles();
    if (profiles.every((element) => element.mods[0].author != null)) {
      Logger.root.info('Saved profiles already migrated');
      return;
    }

    profiles = profiles.map((e) {
      e.mods = e.mods.map((e) => ModService.fromFilename(e.filename)).toList();
      return e;
    }).toList();
    box.put('savedProfilesMigrated', true);
    _saveProfiles(profiles);
  }
}
