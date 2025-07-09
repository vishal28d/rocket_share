import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mailto/mailto.dart';
import 'package:unicons/unicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/constants.dart';
import '../../components/dialogs.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
        valueListenable: AdaptiveTheme.of(context).modeChangeNotifier,
        builder: (_, AdaptiveThemeMode mode, __) {
          return Scaffold(
            backgroundColor: mode.isDark
                ? const Color.fromARGB(255, 27, 32, 35)
                : Colors.white,
            appBar: AppBar(
              backgroundColor: mode.isDark ? Colors.blueGrey.shade900 : null,
              title: const Text('About'),
              leading: BackButton(
                color: Colors.white,
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              flexibleSpace: mode.isLight
                  ? Container(
                      decoration: appBarGradient,
                    )
                  : null,
            ),
            body: ListView(
              children: [
                ListTile(
                  title: const Text('Credits'),
                  leading: SvgPicture.asset('assets/icons/credits.svg',
                      color: Colors.amberAccent),
                  onTap: () {
                    credits(context);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.email_rounded,
                    color: Colors.redAccent,
                  ),
                  onTap: () {
                    var url = Mailto(
                      to: ['vishalmaurya9049@gmail.com'],
                    ).toString();
                    launchUrl(Uri.parse(url));
                  },
                  title: const Text('Email'),
                  subtitle: const Text('vishalmaurya9049@gmail.com'),
                ),
              
                ListTile(
                  leading:
                      const Icon(UniconsLine.github, color: Colors.blueAccent),
                  onTap: () {
                    launchUrl(Uri.parse('https://github.com/vishal28d/rocket_share'));
                  },
                  title: const Text('Github'),
                  subtitle: const Text('https://github.com/vishal28d/rocket_share'),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Container(
                    child: const Center(
                        child:
                            Text('Please consider supporting this project 💙')),
                  ),
                ),
               
              ],
            ),
          );
        });
  }
}
