import 'dart:io';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hive/hive.dart';
import 'package:rocket_share/components/snackbar.dart';
import 'package:rocket_share/services/file_services.dart';
import 'package:rocket_share/views/drawer/about_page.dart';
import 'package:rocket_share/views/drawer/release_notes.dart';
import 'package:rocket_share/views/drawer/settings.dart';
import 'package:rocket_share/views/home/widescreen_home.dart';
import 'package:unicons/unicons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'components/constants.dart';
import 'controllers/intents.dart';
import 'views/drawer/history.dart';
import 'views/home/mobile_home.dart';

class App extends StatefulWidget {
  const App({Key? key}) : super(key: key);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  TextEditingController usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  Box box = Hive.box('appData');

  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
    return ValueListenableBuilder(
      valueListenable: AdaptiveTheme.of(context).modeChangeNotifier,
      builder: (_, AdaptiveThemeMode mode, child) {
        return Scaffold(
          key: scaffoldKey,
          backgroundColor: mode.isDark
              ? const Color.fromARGB(255, 27, 32, 35)
              : Colors.white,
          appBar: AppBar(
            backgroundColor: mode.isDark ? Colors.blueGrey.shade900 : null,
            title: const Text(
              'Rocket Share',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            flexibleSpace: mode.isLight
                ? Container(
                    decoration: appBarGradient,
                  )
                : null,
          ),
          drawer: Shortcuts(
            shortcuts: {
              LogicalKeySet(LogicalKeyboardKey.backspace): GoBackIntent()
            },
            child: Actions(
              actions: {
                GoBackIntent: CallbackAction<GoBackIntent>(onInvoke: (intent) {
                  if (scaffoldKey.currentState!.isDrawerOpen) {
                    scaffoldKey.currentState!.openEndDrawer();
                  }
                  return null;
                })
              },
              child: Drawer(
                child: Stack(
                  children: [
                    ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height / 15,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(0.0),
                          child: Column(
                            children: [
                              Image.asset(
                                box.get('avatarPath'),
                                width: 90,
                                height: 90,
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  box.get('username'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Divider(
                            thickness: 2,
                          ),
                        ),
                        ListTile(
                          leading: Icon(
                            UniconsSolid.history,
                            color: mode.isDark ? null : Colors.black,
                          ),
                          title: const Text('History'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) {
                                  return const HistoryPage();
                                },
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.settings,
                            color: mode.isDark ? null : Colors.black,
                          ),
                          title: const Text("Settings"),
                          onTap: () {
                            Navigator.of(context)
                                .push(MaterialPageRoute(builder: (context) {
                              return const SettingsPage();
                            }));
                          },
                        ),
                        ListTile(
                          title: const Text('Enable HTTPS'),
                          trailing: Switch(
                            value: box.get('enable_https')!,
                            onChanged: (val) async {
                              setState(() {
                                if (box.get('enable_https') == false) {
                                  box.put('enable_https', true);
                                } else {
                                  box.put('enable_https', false);
                                }
                              });

                              await showDialog(
                                context: context,
                                builder: (builder) {
                                  return AlertDialog(
                                    title: const Text("Alert"),
                                    content: Text(
                                      box.get('enable_https') == true
                                          ? "Rocket Share uses self-signed certificates to enable HTTPS when enabled by the sender. While it provides additional layer of security with HTTPS and token based validation, make sure to use Rocket Share within trusted networks."
                                          : "You have disabled HTTPS, now Rocket Share uses legacy mode with unencrypted HTTP while sending. Make sure to use Rocket Share within trusted networks. You can switch back to HTTPS anytime",
                                      textAlign: TextAlign.justify,
                                    ),
                                    actions: [
                                      MaterialButton(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                        child: const Text("I understand"),
                                      )
                                    ],
                                  );
                                },
                              );
                              showSnackBar(
                                  context,
                                  box.get('enable_https') == true
                                      ? "HTTPS enabled"
                                      : "HTTPS disabled");
                            },
                          ),
                          leading: Icon(Icons.security_rounded,
                              color: mode.isDark ? null : Colors.black),
                        ),
                       
                        ListTile(
                          leading: Icon(
                            Icons.privacy_tip_rounded,
                            color: mode.isDark ? null : Colors.black,
                          ),
                          onTap: () async {
                            launchUrl(
                                Uri.parse(
                                    "https://github.com/vishal28d/rocket_share"),
                                mode: LaunchMode.externalApplication);
                          },
                          title: const Text('Privacy policy'),
                        ),
                        if (Platform.isAndroid || Platform.isIOS) ...{
                          ListTile(
                            title: const Text('Clear cache'),
                            leading: Icon(Icons.delete_forever_rounded,
                                color: mode.isDark ? null : Colors.black),
                            onTap: () async {
                              await FileUtils.clearCache();
                              if (mounted) {
                                Navigator.of(context).pop();
                                showSnackBar(context, "Cache cleared");
                              }
                            },
                          ),
                        },
                
                        ListTile(
                          title: const Text('About'),
                          leading: Icon(UniconsLine.info_circle,
                              color: mode.isDark ? null : Colors.black),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) {
                                  return const AboutPage();
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    Positioned(
                      bottom: 18,
                      right: 5,
                      child: Padding(
                        padding: const EdgeInsets.all(0.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Image.asset('assets/images/icon.png',
                                width: 30, height: 30),
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'Rocket Share v1.0.0',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
          body: Center(
            child:
                size.width > 720 ? const WidescreenHome() : const MobileHome(),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor:
                mode.isDark ? Colors.blueGrey.shade900 : Colors.white,
            onPressed: () {
              showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text("Help"),
                      content: const Text(
                        """1. Before sharing files make sure that you are connected to wifi or your mobile-hotspot is turned on.\n\n2. While receiving make sure you are connected to the same wifi or hotspot as that of sender.""",
                        textAlign: TextAlign.justify,
                      ),
                      actions: [
                        IconButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(
                            Icons.close,
                          ),
                        ),
                      ],
                    );
                  });
            },
            icon: const Text("Help"),
            label: const Icon(Icons.help),
          ),
        );
      },
    );
  }
}
