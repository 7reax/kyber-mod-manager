import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_translate/flutter_translate.dart';
import 'package:kyber_mod_manager/logic/game_status_cubic.dart';
import 'package:kyber_mod_manager/main.dart';
import 'package:kyber_mod_manager/utils/services/frosty_profile_service.dart';
import 'package:kyber_mod_manager/utils/services/frosty_service.dart';
import 'package:kyber_mod_manager/utils/services/notification_service.dart';
import 'package:kyber_mod_manager/utils/services/profile_service.dart';
import 'package:kyber_mod_manager/utils/types/freezed/frosty_collection.dart';
import 'package:kyber_mod_manager/utils/types/freezed/mod.dart';
import 'package:kyber_mod_manager/utils/types/freezed/mod_profile.dart';
import 'package:kyber_mod_manager/utils/types/mod_info.dart';
import 'package:kyber_mod_manager/utils/types/pack_type.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:sentry_flutter/sentry_flutter.dart';

class ModService {
  static final List<String> _kyberCategories = ['gameplay', 'server host'];
  static List<Mod> mods = [];
  static List<FrostyCollection> collections = [];
  static StreamSubscription? _subscription;

  static Future<List<dynamic>> createModPack(BuildContext context, {
    required PackType packType,
    required String profileName,
    bool cosmetics = false,
    required Function(int copied, int total) onProgress,
    required Function(String content) setContent,
  }) async {
    const String prefix = 'server_browser.join_dialog.joining_states';
    List<Mod> cosmeticMods = List<Mod>.from(box.get('cosmetics'));
    bool enableCosmetics = cosmetics && box.get('enableCosmetics');
    Logger.root.info('Loading mods for $profileName (cosmetics: $enableCosmetics | type: $packType)');

    if (packType == PackType.NO_MODS) {
      await ProfileService.enableProfile(ProfileService.getProfilePath("KyberModManager"));
      if (enableCosmetics) {
        await FrostyProfileService.createProfile(cosmeticMods.map((e) => e.toKyberString()).toList());
        return [];
      }
      await FrostyProfileService.createProfile([]);
      return [];
    } else if (packType == PackType.MOD_PROFILE) {
      ModProfile profile = List<ModProfile>.from(box.get('profiles')).where((p) => p.name == profileName).first;
      List<dynamic> mods = List.from(profile.mods);
      List<String> formattedMods = List<String>.from(mods.map((e) => e.toKyberString()).toList());
      if (enableCosmetics) {
        mods = [...mods, ...cosmeticMods];
        formattedMods = List<String>.from(mods.map((e) => e.toKyberString()).toList());
      }

      if (dynamicEnvEnabled) {
        BlocProvider.of<GameStatusCubic>(context).setProfile(ProfileService.getProfilePath(profileName));
        return formattedMods;
      }

      await FrostyProfileService.createProfile(formattedMods);
      await ProfileService.searchProfile(formattedMods, onProgress);
      return mods;
    } else if (packType == PackType.FROSTY_PACK) {
      var currentMods = await FrostyProfileService.getModsFromProfile('KyberModManager');
      List<dynamic> mods = FrostyProfileService.getModsFromConfigProfile(profileName);
      List<String> formattedMods = List<String>.from(mods.map((e) => e.toKyberString()).toList());

      if (!enableCosmetics && dynamicEnvEnabled) {
        BlocProvider.of<GameStatusCubic>(context).setProfile(ProfileService.getProfilePath(profileName));
        return mods;
      } else if (dynamicEnvEnabled) {
        mods = [...mods, ...cosmeticMods];
        formattedMods = List<String>.from(mods.map((e) => e.toKyberString()).toList());
        await FrostyProfileService.createProfile(formattedMods);
        await ProfileService.searchProfile(formattedMods, onProgress);
        return mods;
      } else if (enableCosmetics) {
        mods = [...mods, ...cosmeticMods];
        formattedMods = List<String>.from(mods.map((e) => e.toKyberString()).toList());
      }

      if (!listEquals(currentMods, mods)) {
        var packMods = FrostyProfileService.getModsFromConfigProfile(profileName);
        setContent(translate('$prefix.creating'));
        await FrostyProfileService.createProfile(formattedMods);
        if (listEquals(packMods, mods)) {
          onProgress(0, 0);
          return await FrostyProfileService.loadFrostyPack(profileName.replaceAll(' (Frosty Pack)', ''), onProgress);
        }
        await ProfileService.searchProfile(formattedMods, onProgress);
        return mods;
      }

      await FrostyProfileService.createProfile(formattedMods);
      String? profile = await ProfileService.searchProfile(formattedMods, onProgress);
      BlocProvider.of<GameStatusCubic>(context).setProfile(profile);
      return mods;
    } else if (packType == PackType.COSMETICS) {
      List<Mod> mods = List<Mod>.from(box.get('cosmetics'));
      await ProfileService.searchProfile(mods.map((e) => e.toKyberString()).toList(), onProgress);
      setContent(translate('$prefix.creating'));
      await FrostyProfileService.createProfile(mods.map((e) => e.toKyberString()).toList());
      String? profile = await ProfileService.searchProfile(mods.map((e) => e.toKyberString()).toList(), onProgress);
      BlocProvider.of<GameStatusCubic>(context).setProfile(profile);
      return mods;
    }
    NotificationService.showNotification(message: translate('host_server.forms.mod_profile.no_profile_found'));
    return [];
  }

  static List<dynamic> getModsFromModPack(String name) {
    PackType packType = getPackType(name);
    if (packType == PackType.FROSTY_PACK || packType == PackType.MOD_PROFILE) {
      name = name.replaceAll(' ${packType.name}', '');
    }
    switch (packType) {
      case PackType.NO_MODS:
        return [];
      case PackType.MOD_PROFILE:
        return List<ModProfile>.from(box.get('profiles')).where((p) => p.name == name).first.mods;
      case PackType.FROSTY_PACK:
        return FrostyProfileService.getModsFromConfigProfile(name);
      case PackType.COSMETICS:
        return List<Mod>.from(box.get('cosmetics'));
      default:
        return [];
    }
  }

  static dynamic fromFilename(String filename) {
    for (FrostyCollection collection in collections) {
      if (collection.filename == filename) {
        return collection;
      }
    }

    for (Mod mod in mods) {
      if (mod.filename == filename) {
        return mod;
      }
    }
    return Mod.fromString('');
  }

  static void deleteMod(dynamic mod) {
    Directory dir = Directory(p.join(box.get('frostyPath'), 'Mods', 'starwarsbattlefrontii'));
    File file = File(p.join(dir.path, mod.filename));
    if (file.existsSync()) {
      file.deleteSync();
    }
    if (mod is Mod) {
      mods.remove(mod);
    } else if (mod is FrostyCollection) {
      collections.remove(mod);
    }
  }

  static Mod convertToMod(String mod) {
    ModInfo info = convertToModInfo(mod);
    return mods.firstWhere((element) => element.name == info.name && element.version.trim() == info.version.trim(), orElse: () => Mod.fromString(mod));
  }

  static dynamic convertToFrostyMod(String mod) {
    ModInfo info = convertToModInfo(mod);
    dynamic frostyMod = mods.firstWhere((element) => element.name == info.name && element.version == info.version, orElse: () => Mod.fromString(''));
    if (frostyMod.name == 'Invalid' && collections.any((element) => element.name == info.name && element.version == info.version)) {
      frostyMod = collections.firstWhere((element) => element.name == info.name && element.version == info.version);
    }

    return frostyMod;
  }

  static dynamic getFrostyMod(String filename) {
    dynamic frostyMod = mods.firstWhere((element) => element.filename == filename, orElse: () => Mod.fromString(''));
    if (frostyMod.name == 'Invalid' && collections.any((element) => element.filename == filename)) {
      frostyMod = collections.firstWhere((element) => element.filename == filename);
    }

    return frostyMod;
  }

  static ModInfo convertToModInfo(String name) {
    String modName = name.substring(0, name.lastIndexOf(' ('));
    String version = name.substring(name.lastIndexOf('(') + 1, name.length - 1);
    return ModInfo(name: modName, version: version);
  }

  static bool isInstalled(String name) {
    String modName = name.substring(0, name.lastIndexOf(' ('));
    String version = name.substring(name.lastIndexOf('(') + 1, name.length - 1);
    return mods.any((mod) => mod.name == modName && mod.version == version) ||
        collections.any((element) => element.title == modName && element.version == version);
  }

  static Map<String, List<dynamic>> getModsByCategory([bool kyberCategories = false]) {
    Map<String, List<dynamic>> categories = {"Frosty Colelctions": []};
    for (dynamic mod in [...mods, ...collections]) {
      if (kyberCategories && !_kyberCategories.contains(mod.category.toLowerCase())) continue;
      if (categories.containsKey(mod.category)) {
        categories[mod.category]?.add(mod);
      } else {
        categories[mod.category] = [mod];
      }
    }

    List<MapEntry<String, List<dynamic>>> items = categories.entries.toList()..sort(((a, b) => a.key.compareTo(b.key)));

    return Map<String, List<dynamic>>.fromEntries(items);
  }

  static void watchDirectory() {
    FrostyService.getFrostyConfigPath();
    if (!box.containsKey('frostyPath')) {
      return;
    }

    Directory dir = Directory(p.join(box.get('frostyPath'), 'Mods', 'starwarsbattlefrontii'));
    if (!dir.existsSync()) {
      return;
    }

    if (_subscription != null) {
      _subscription?.cancel();
    }

    DateTime cooldown = DateTime.now();
    Logger.root.info('Watching directory for changes');
    _subscription = dir.watch(events: FileSystemEvent.all).listen((event) {
      cooldown = DateTime.now();
      Future.delayed(const Duration(seconds: 2), () {
        if (DateTime.now().difference(cooldown).inSeconds != 2) {
          return;
        }
        loadMods();
      });
    });
  }

  static Future<void> loadMods([BuildContext? context]) async {
    FrostyService.getFrostyConfigPath();
    if (!box.containsKey('frostyPath')) {
      return;
    }

    Directory dir = Directory(p.join(box.get('frostyPath'), 'Mods', 'starwarsbattlefrontii'));
    if (!dir.existsSync()) {
      box.delete('frostyPath');
      box.delete('setup');
      return;
    }

    final List<FileSystemEntity> entities = await dir.list().toList();
    mods = await compute(_loadMods, entities.map((e) => e.path).toList());
    if (context != null) {
      NotificationService.showNotification(message: translate('mods_loaded', args: {'count': mods.length.toString()}));
    }

    collections = await _loadCollections(entities.map((e) => e.path).toList());
  }

  static Future<Mod> getDataFromFile(File file) async {
    List<int> data = [];
    await file.openRead(0, 1500).toList().then((value) => value.forEach((element) => element.forEach((element1) => data.add(element1))));
    return Mod.fromString(
      file.path,
      utf8.decode(
        data.getRange(50, data.length).toList(),
        allowMalformed: true,
      ),
    );
  }
}

Future<List<FrostyCollection>> _loadCollections(List<dynamic> files) async {
  List<FrostyCollection> loadedCollections = [];
  await Future.forEach(List<String>.from(files).where((element) => element.endsWith('.fbcollection')), (String element) async {
    File file = File(element);
    if (!file.existsSync()) {
      return;
    }

    // TODO: fix this mess
    List<int> data = [];
    await file.openRead(0, 6000).toList().then((value) => value.forEach((element) => element.forEach((element1) => data.add(element1))));
    String decoded = utf8.decode(
      data.getRange(28, data.length).toList(),
      allowMalformed: true,
    );
    decoded = Uri.decodeComponent(Uri.encodeComponent(decoded).split('%00').first);
    loadedCollections.add(FrostyCollection.fromFile(element, jsonDecode(decoded.substring(0, decoded.lastIndexOf('}') + 1))));
  });
  return loadedCollections;
}

Future<List<Mod>> _loadMods(List<dynamic> files) async {
  List<Mod> loadedMods = [];
  await Future.forEach(List<String>.from(files).where((element) => element.endsWith('.fbmod')), (String element) async {
    try {
      File file = File(element);
      if (!file.existsSync()) {
        return;
      }
      List<int> data = [];
      await file.openRead(0, 1500).toList().then((value) => value.forEach((element) => element.forEach((element1) => data.add(element1))));
      loadedMods.add(Mod.fromString(
        element,
        utf8.decode(
          data.getRange(50, data.length).toList(),
          allowMalformed: true,
        ),
      ));
    } catch (e) {
      Sentry.captureException(e);
      Logger.root.info('Error loading mod: $e');
    }
  });
  return loadedMods;
}
