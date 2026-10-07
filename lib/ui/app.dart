import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/coach_controller.dart';
import 'components.dart';
import 'pages.dart';
import 'theme.dart';

class SpiderAimApp extends StatelessWidget {
  const SpiderAimApp({super.key, required this.controller});
  final CoachController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SPIDER AIM',
    debugShowCheckedModeBanner: false,
    theme: spiderTheme(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: CoachShell(controller: controller),
  );
}

const destinations = <({String label, IconData icon})>[
  (label: 'لوحة القيادة', icon: Icons.space_dashboard_outlined),
  (label: 'ملف الجهاز', icon: Icons.devices_outlined),
  (label: 'معايرة التصويب', icon: Icons.my_location_outlined),
  (label: 'ملفات الأسلحة', icon: Icons.tune_rounded),
  (label: 'معايرة الحركة', icon: Icons.directions_run_rounded),
  (label: 'القنابل والرميات', icon: Icons.sports_handball_outlined),
  (label: 'تحليل الوفاة والإصابات', icon: Icons.analytics_outlined),
  (label: 'البطارية والحرارة', icon: Icons.battery_charging_full_outlined),
  (label: 'التعديلات المقترحة', icon: Icons.auto_awesome_outlined),
  (label: 'الاختبار والمقارنة', icon: Icons.science_outlined),
  (label: 'سجل الإصدارات', icon: Icons.history_rounded),
  (label: 'استرجاع الإعدادات', icon: Icons.restore_rounded),
  (label: 'مساعد الهبوط', icon: Icons.paragliding_outlined),
  (label: 'الأمان وقفل Ranked', icon: Icons.shield_outlined),
];

class CoachShell extends StatefulWidget {
  const CoachShell({super.key, required this.controller});
  final CoachController controller;
  @override
  State<CoachShell> createState() => _CoachShellState();
}

class _CoachShellState extends State<CoachShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  int _page = 0;

  void _navigate(int value) {
    if (_scaffold.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
    setState(() => _page = value);
  }

  Widget _brand() => const Padding(
    padding: EdgeInsets.fromLTRB(20, 30, 20, 24),
    child: Row(
      children: [
        Icon(Icons.my_location_rounded, color: spiderTeal, size: 32),
        SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SPIDER AIM', textDirection: TextDirection.ltr, style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w900, fontSize: 18)),
          SizedBox(height: 4),
          Text('ثبات يُقاس. قرار بيدك.', style: TextStyle(color: spiderMuted, fontSize: 12)),
        ])),
      ],
    ),
  );

  Widget _navigation() => Column(
    children: [
      _brand(),
      const Divider(height: 1),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        itemCount: destinations.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: ListTile(
            selected: _page == index,
            selectedTileColor: spiderTeal.withValues(alpha: 0.09),
            selectedColor: spiderTeal,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: Icon(destinations[index].icon, size: 21),
            title: Text(destinations[index].label, style: const TextStyle(fontSize: 13)),
            onTap: () => _navigate(index),
          ),
        ),
      )),
      const Padding(padding: EdgeInsets.all(20), child: StatusPill(text: 'NON-GYRO · TOUCH ONLY', good: true)),
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final controller = widget.controller;
        const bottomPages = [0, 2, 8, 13];
        final bottomIndex = bottomPages.indexOf(_page);
        return Scaffold(
          key: _scaffold,
          appBar: wide ? null : AppBar(
            title: const Text('SPIDER AIM', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            actions: [
              IconButton(tooltip: 'قفل Ranked وحالة الجلسة', onPressed: () => _navigate(13), icon: Icon(controller.guard.allowed ? Icons.verified_user_outlined : Icons.lock_outline, color: controller.guard.allowed ? spiderTeal : Colors.amber)),
              const SizedBox(width: 8),
            ],
          ),
          drawer: wide ? null : Drawer(backgroundColor: spiderSurface, child: SafeArea(child: _navigation())),
          bottomNavigationBar: wide ? null : NavigationBar(
            selectedIndex: bottomIndex < 0 ? 0 : bottomIndex,
            onDestinationSelected: (value) => _navigate(bottomPages[value]),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'الرئيسية'),
              NavigationDestination(icon: Icon(Icons.my_location_outlined), selectedIcon: Icon(Icons.my_location), label: 'المعايرة'),
              NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'المقترحات'),
              NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'الأمان'),
            ],
          ),
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide) Container(width: 260, decoration: const BoxDecoration(color: spiderSurface, border: Border(left: BorderSide(color: Color(0xFF253540)))), child: _navigation()),
                Expanded(child: Column(
                  children: [
                    if (controller.busy) const LinearProgressIndicator(minHeight: 2),
                    if (controller.error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: NoticePanel(text: controller.error!, warning: true)),
                    Expanded(child: !controller.ready
                        ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 20), Text('جارٍ فتح ملف الجهاز بأمان…')]))
                        : controller.device?.supported != true
                            ? const Padding(padding: EdgeInsets.all(24), child: EmptyPanel(title: 'جهاز غير مدعوم', message: 'SPIDER AIM مخصص للهواتف والأجهزة اللوحية الفعلية على Android وiOS. التشغيل على الكمبيوتر والمحاكي غير متاح.', icon: Icons.phonelink_erase_rounded))
                            : SingleChildScrollView(
                                key: ValueKey(_page),
                                padding: EdgeInsets.all(wide ? 32 : 20),
                                child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1180), child: CoachPage(index: _page, controller: controller, onNavigate: _navigate))),
                              )),
                  ],
                )),
              ],
            ),
          ),
        );
      },
    ),
  );
}
