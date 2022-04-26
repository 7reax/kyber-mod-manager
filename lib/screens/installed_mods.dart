import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_translate/flutter_translate.dart';
import 'package:kyber_mod_manager/main.dart';
import 'package:kyber_mod_manager/utils/services/mod_service.dart';
import 'package:kyber_mod_manager/utils/types/freezed/mod.dart';
import 'package:kyber_mod_manager/widgets/button_text.dart';
import 'package:kyber_mod_manager/widgets/custom_button.dart';
import 'package:url_launcher/url_launcher_string.dart';

class InstalledMods extends StatefulWidget {
  const InstalledMods({Key? key}) : super(key: key);

  @override
  _InstalledModsState createState() => _InstalledModsState();
}

class _InstalledModsState extends State<InstalledMods> {
  final String prefix = 'installed_mods';
  List<Mod> _installedMods = [];
  String search = '';

  @override
  void initState() {
    Timer.run(() => loadMods());
    super.initState();
  }

  void loadMods() {
    setState(() => _installedMods = _installedMods = ModService.mods.where((element) => element.toString().toLowerCase().contains(search.toLowerCase())).toList()
      ..sort((a, b) => a.name.compareTo(b.name)));
  }

  @override
  Widget build(BuildContext context) {
    final color = FluentTheme.of(context).typography.body!.color!;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(translate('$prefix.title')),
        commandBar: Row(
          children: [
            FilledButton(
              child: ButtonText(
                icon: const Icon(FluentIcons.folder_search),
                text: Text(translate('$prefix.open_directory')),
              ),
              onPressed: () => launchUrlString('file://${box.get('frostyPath')}\\Mods\\starwarsbattlefrontii'),
            ),
          ],
        ),
      ),
      content: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: TextBox(
                  autofocus: true,
                  onChanged: (String? value) {
                    setState(() => search = value ?? '');
                    loadMods();
                  },
                  placeholder: translate('search'),
                ),
              ),
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width),
                  child: SingleChildScrollView(
                    child: material.DataTable(
                      dataRowHeight: 40,
                      columns: [
                        material.DataColumn(
                          label: SizedBox(
                            child: Text(
                              translate('name'),
                              style: TextStyle(
                                color: color.withOpacity(.5),
                              ),
                            ),
                          ),
                        ),
                        material.DataColumn(
                          label: SizedBox(
                            child: Text(
                              translate('author'),
                              style: TextStyle(
                                color: color.withOpacity(.5),
                              ),
                            ),
                          ),
                        ),
                        material.DataColumn(
                          label: SizedBox(
                            child: Text(
                              translate('version'),
                              style: TextStyle(
                                color: color.withOpacity(.5),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        const material.DataColumn(
                          label: Text(''),
                        ),
                      ],
                      rows: _installedMods.map((e) {
                        return material.DataRow(
                          cells: [
                            material.DataCell(
                              Text(e.name),
                            ),
                            material.DataCell(
                              Text(e.author ?? 'Unknown'),
                            ),
                            material.DataCell(
                              Text(e.version, textAlign: TextAlign.center),
                            ),
                            material.DataCell(Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                CustomFilledButton(
                                  color: Colors.red,
                                  child: ButtonText(
                                    text: Text(translate('delete')),
                                    icon: const Icon(FluentIcons.delete),
                                  ),
                                  onPressed: () {
                                    ModService.deleteMod(e);
                                    loadMods();
                                  },
                                ),
                              ],
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
