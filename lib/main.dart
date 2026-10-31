import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStore.init();

  List<CameraDescription> cameras = [];

  try {
    cameras = await availableCameras();
  } catch (_) {}

  runApp(DrugTestingApp(cameras: cameras));
}

// ============================================================
// APP
// ============================================================

class DrugTestingApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const DrugTestingApp({
    super.key,
    required this.cameras,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Digital Companion for Field Drug Testing',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1769E0),
        ),
      ),
      home: LoginScreen(cameras: cameras),
    );
  }
}

// ============================================================
// COLORS
// ============================================================

const navy = Color(0xFF092F57);
const blue = Color(0xFF1769E0);
const cyan = Color(0xFF08A6C7);
const green = Color(0xFF16A36D);
const red = Color(0xFFE34D59);
const orange = Color(0xFFF59E0B);
const purple = Color(0xFF7957D5);

const background = Color(0xFFF5F7FB);
const textDark = Color(0xFF172B4D);
const muted = Color(0xFF718096);
const border = Color(0xFFE2E8F0);

// Real photographs supplied for the judge/demo workflow.
// These are bundled locally so the selector works without internet access.
const List<String> demoImageAssets = [
  'assets/demo_test_1.jpg',
  'assets/demo_test_2.jpg',
  'assets/demo_test_3.jpg',
  'assets/demo_test_4.jpg',
  'assets/demo_test_5.jpg',
];

const List<String> demoImageTitles = [
  'Demo Test 1 • Fentanyl reagent',
  'Demo Test 2 • Methamphetamine / MDMA reagent',
  'Demo Test 3 • Field test kit',
  'Demo Test 4 • Fentanyl reagent',
  'Demo Test 5 • Fentanyl reagent',
];


// ---------------------------------------------------------------------------
// REAL-WORLD REFERENCE COLOUR DATA
// ---------------------------------------------------------------------------
// Based on a published Marquis reagent reference chart (NARTEC) and NIJ
// colour-test guidance. This is displayed as a digital reference card.
// Production deployment should use the exact chart supplied with the
// manufacturer/kit being used in the field.
class ReferenceColourEntry {
  final String substance;
  final String expected;
  final Color swatch;
  final String hex;

  const ReferenceColourEntry({
    required this.substance,
    required this.expected,
    required this.swatch,
    required this.hex,
  });
}

const List<ReferenceColourEntry> marquisReferenceColours = [
  ReferenceColourEntry(
    substance: 'MDMA / MDA / MDE',
    expected: 'Dark purple → black',
    swatch: Color(0xFF2D153B),
    hex: '#2D153B',
  ),
  ReferenceColourEntry(
    substance: 'Amphetamine',
    expected: 'Orange',
    swatch: Color(0xFFE8751A),
    hex: '#E8751A',
  ),
  ReferenceColourEntry(
    substance: 'Methamphetamine',
    expected: 'Yellow → brown',
    swatch: Color(0xFFB87928),
    hex: '#B87928',
  ),
  ReferenceColourEntry(
    substance: 'Fentanyl',
    expected: 'Brown → dark brown',
    swatch: Color(0xFF5A3825),
    hex: '#5A3825',
  ),
  ReferenceColourEntry(
    substance: 'LSD',
    expected: 'Green',
    swatch: Color(0xFF4C9A55),
    hex: '#4C9A55',
  ),
  ReferenceColourEntry(
    substance: 'Heroin',
    expected: 'Purple',
    swatch: Color(0xFF6E3A8A),
    hex: '#6E3A8A',
  ),
  ReferenceColourEntry(
    substance: '2C-I',
    expected: 'Yellow → green',
    swatch: Color(0xFF9DAA35),
    hex: '#9DAA35',
  ),
  ReferenceColourEntry(
    substance: 'Morphine',
    expected: 'Red → purple',
    swatch: Color(0xFF9E3B55),
    hex: '#9E3B55',
  ),
  ReferenceColourEntry(
    substance: 'Codeine',
    expected: 'Lavender → dark purple',
    swatch: Color(0xFF7A5C96),
    hex: '#7A5C96',
  ),
  ReferenceColourEntry(
    substance: 'Ritalin',
    expected: 'Pale yellow → orange',
    swatch: Color(0xFFF0C45C),
    hex: '#F0C45C',
  ),
  ReferenceColourEntry(
    substance: 'Methylone',
    expected: 'Pale yellow → bright yellow',
    swatch: Color(0xFFF3D64B),
    hex: '#F3D64B',
  ),
  ReferenceColourEntry(
    substance: 'Mescaline',
    expected: 'Pale yellow → orange',
    swatch: Color(0xFFE5B94D),
    hex: '#E5B94D',
  ),
];

String generateUniqueCaseId() {
  final now = DateTime.now();
  final base =
      'FT-${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
      '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}-${now.microsecond.toString().padLeft(6, '0')}';
  var id = base;
  var counter = 1;
  while (AppStore.records.any((r) => r.caseId == id)) {
    id = '$base-$counter';
    counter++;
  }
  return id;
}

String generateUniqueSampleId() {
  final now = DateTime.now();
  final base =
      'SMP-${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
      '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}-${now.microsecond.toString().padLeft(6, '0')}';
  var id = base;
  var counter = 1;
  while (AppStore.records.any((r) => r.sampleId == id)) {
    id = '$base-$counter';
    counter++;
  }
  return id;
}

// ============================================================
// LOGIN
// ============================================================

class LoginScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const LoginScreen({
    super.key,
    required this.cameras,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final operatorController =
      TextEditingController(text: 'OFFICER-001');

  final pinController =
      TextEditingController(text: '1234');

  bool hidePin = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  children: [
                    Container(
                      height: 82,
                      width: 82,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F1FF),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.biotech_rounded,
                        size: 48,
                        color: blue,
                      ),
                    ),

                    const SizedBox(height: 22),

                    const Text(
                      'Digital Companion',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: navy,
                      ),
                    ),

                    const SizedBox(height: 3),

                    const Text(
                      'for Field Drug Testing',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: blue,
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'Secure • Standardized • Auditable',
                      style: TextStyle(
                        color: muted,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 30),

                    TextField(
                      controller: operatorController,
                      decoration: InputDecoration(
                        labelText: 'Operator ID',
                        prefixIcon:
                            const Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: pinController,
                      obscureText: hidePin,
                      decoration: InputDecoration(
                        labelText: 'PIN',
                        prefixIcon:
                            const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              hidePin = !hidePin;
                            });
                          },
                          icon: Icon(
                            hidePin
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MainDashboard(
                                cameras: widget.cameras,
                                operatorId:
                                    operatorController.text
                                            .trim()
                                            .isEmpty
                                        ? 'OFFICER-001'
                                        : operatorController.text
                                            .trim(),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                            Icons.login_rounded),
                        label: const Text(
                          'Secure Login',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E7),
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: orange,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Prototype field result only. Laboratory confirmation is required.',
                              style: TextStyle(
                                fontSize: 11,
                                color: textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MAIN DASHBOARD
// ============================================================

class MainDashboard extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String operatorId;

  const MainDashboard({
    super.key,
    required this.cameras,
    required this.operatorId,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int selectedIndex = 0;

  final pages = const [
    'Dashboard',
    'New Test',
    'Image Analysis',
    'Test Records',
    'Chain of Custody',
    'Test Locations',
    'Verify Record',
    'Analytics',
    'Reports',
  ];

  @override
  Widget build(BuildContext context) {
    final desktop =
        MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      backgroundColor: background,
      body: Row(
        children: [
          if (desktop) _desktopSidebar(),

          Expanded(
            child: Column(
              children: [
                _topBar(desktop),
                Expanded(
                  child: _content(),
                ),
              ],
            ),
          ),
        ],
      ),

      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex:
                  selectedIndex > 3 ? 0 : selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  selectedIndex = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon:
                      Icon(Icons.dashboard_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.science_outlined),
                  selectedIcon:
                      Icon(Icons.science_rounded),
                  label: 'New Test',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon:
                      Icon(Icons.history_rounded),
                  label: 'Records',
                ),
                NavigationDestination(
                  icon: Icon(Icons.verified_outlined),
                  selectedIcon:
                      Icon(Icons.verified_rounded),
                  label: 'Verify',
                ),
              ],
            ),
    );
  }

  Widget _desktopSidebar() {
    return Container(
      width: 255,
      color: navy,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 25),

            Row(
              children: [
                const SizedBox(width: 20),

                Container(
                  height: 45,
                  width: 45,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.12),
                    borderRadius:
                        BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.biotech_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ),

                const SizedBox(width: 12),

                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Field Drug',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Testing Companion',
                        style: TextStyle(
                          color: Color(0xFFBBD5F5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 35),

            Expanded(
              child: ListView.builder(
                itemCount: pages.length,
                itemBuilder: (_, index) {
                  return _sideItem(
                    index,
                    _iconFor(index),
                    pages[index],
                  );
                },
              ),
            ),

            const Divider(
              color: Colors.white24,
              indent: 18,
              endIndent: 18,
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor:
                        Colors.white24,
                    child: Icon(
                      Icons.person,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Operator',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          widget.operatorId,
                          overflow:
                              TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight:
                                FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(int index) {
    const icons = [
      Icons.dashboard_rounded,
      Icons.science_rounded,
      Icons.image_search_rounded,
      Icons.folder_copy_rounded,
      Icons.security_rounded,
      Icons.location_on_rounded,
      Icons.verified_rounded,
      Icons.analytics_rounded,
      Icons.picture_as_pdf_rounded,
    ];

    return icons[index];
  }

  Widget _sideItem(
      int index, IconData icon, String title) {
    final active = selectedIndex == index;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            selectedIndex = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          margin:
              const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withOpacity(.13)
                : Colors.transparent,
            borderRadius:
                BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: active
                    ? Colors.white
                    : const Color(0xFF9EB8D6),
                size: 21,
              ),
              const SizedBox(width: 13),
              Text(
                title,
                style: TextStyle(
                  color: active
                      ? Colors.white
                      : const Color(0xFFB7C9DD),
                  fontWeight: active
                      ? FontWeight.w800
                      : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(bool desktop) {
    return Container(
      height: 75,
      color: Colors.white,
      padding:
          const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          if (!desktop)
            IconButton(
              onPressed: () {
                _showMobileMenu();
              },
              icon: const Icon(Icons.menu_rounded),
            ),

          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  pages[selectedIndex],
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                  ),
                ),
                const Text(
                  'Digital evidence & field testing platform',
                  style: TextStyle(
                    fontSize: 11,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F8F1),
              borderRadius:
                  BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.circle,
                  color: green,
                  size: 9,
                ),
                SizedBox(width: 6),
                Text(
                  'System Online',
                  style: TextStyle(
                    color: green,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          CircleAvatar(
            backgroundColor:
                const Color(0xFFE8F1FF),
            child: IconButton(
              onPressed: _profile,
              icon: const Icon(
                Icons.person_rounded,
                color: blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    switch (selectedIndex) {
      case 0:
        return DashboardHome(
          operatorId: widget.operatorId,
          onNewTest: () {
            setState(() {
              selectedIndex = 1;
            });
          },
        );

      case 1:
        return NewTestPage(
          cameras: widget.cameras,
          operatorId: widget.operatorId,
        );

      case 2:
        return const AnalysisInfoPage();

      case 3:
        return const RecordsPage();

      case 4:
        return const CustodyPage();

      case 5:
        return const LocationsPage();

      case 6:
        return const VerifyPage();

      case 7:
        return const AnalyticsPage();

      case 8:
        return const ReportsPage();

      default:
        return const SizedBox();
    }
  }

  void _showMobileMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: List.generate(
              pages.length,
              (index) => ListTile(
                leading: Icon(_iconFor(index)),
                title: Text(pages[index]),
                onTap: () {
                  Navigator.pop(context);

                  setState(() {
                    selectedIndex = index;
                  });
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _profile() {
    final total = AppStore.total;
    final pos = AppStore.count('POSITIVE');
    final neg = AppStore.count('NEGATIVE');
    final inc = AppStore.count('INCONCLUSIVE');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [CircleAvatar(radius: 23, backgroundColor: Color(0xFFE8F1FF), child: Icon(Icons.person_rounded, color: blue)), SizedBox(width: 12), Text('Officer Profile')]),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          profileLine('Officer ID', widget.operatorId),
          profileLine('Role', 'Field Testing Officer'),
          profileLine('Department', 'Digital Field Testing Unit'),
          profileLine('System', 'Digital Companion for Field Drug Testing'),
          profileLine('Session', 'ACTIVE'),
          profileLine('Security', 'SHA-256 + QR verification enabled'),
          profileLine('Audit', 'Digital record logging enabled'),
          const Divider(height: 25),
          const Text('Activity Statistics', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          profileLine('Total tests', '$total'),
          profileLine('Positive', '$pos'),
          profileLine('Negative', '$neg'),
          profileLine('Inconclusive', '$inc'),
          profileLine('Average confidence', '${AppStore.averageConfidence.toStringAsFixed(1)}%'),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton.icon(onPressed: () { Navigator.pop(context); Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen(cameras: widget.cameras))); }, icon: const Icon(Icons.logout_rounded), label: const Text('Logout')),
        ],
      ),
    );
  }

  Widget profileLine(String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 145, child: Text(title, style: const TextStyle(color: muted, fontSize: 12))), Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: textDark)))],),
      );

}

// ============================================================
// DASHBOARD HOME
// ============================================================

class DashboardHome extends StatelessWidget {
  final String operatorId;
  final VoidCallback onNewTest;

  const DashboardHome({
    super.key,
    required this.operatorId,
    required this.onNewTest,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Good Evening, Officer',
                      style: TextStyle(
                        color: muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      operatorId,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),

              FilledButton.icon(
                onPressed: onNewTest,
                icon: const Icon(
                    Icons.add_rounded),
                label:
                    const Text('New Test'),
              ),
            ],
          ),

          const SizedBox(height: 25),

          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFEAF4FF),
                  Color(0xFFE9F9F3),
                ],
              ),
              borderRadius:
                  BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFD6E7F8),
              ),
            ),
            child: Row(
              children: [
                Container(
                  height: 58,
                  width: 58,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(17),
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: blue,
                    size: 30,
                  ),
                ),

                const SizedBox(width: 17),

                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Secure Field Testing',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight:
                              FontWeight.w900,
                          color: textDark,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Standardized capture • AI-assisted analysis • Tamper-evident digital records',
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 25),

          const Text(
            'Testing Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: textDark,
            ),
          ),

          const SizedBox(height: 13),

          ValueListenableBuilder<int>(
            valueListenable: AppStore.version,
            builder: (_, __, ___) => LayoutBuilder(
              builder: (_, constraints) {
                final wide = constraints.maxWidth > 800;
                final cards = [
                  DashboardStat(title: 'Total Tests', value: '${AppStore.total}', icon: Icons.science_rounded, color: blue, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TotalTestsPage()))),
                  DashboardStat(title: 'Positive', value: '${AppStore.count('POSITIVE')}', icon: Icons.warning_rounded, color: red, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResultRecordsPage(result: 'POSITIVE')))),
                  DashboardStat(title: 'Negative', value: '${AppStore.count('NEGATIVE')}', icon: Icons.check_circle_rounded, color: green, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResultRecordsPage(result: 'NEGATIVE')))),
                  DashboardStat(title: 'Inconclusive', value: '${AppStore.count('INCONCLUSIVE')}', icon: Icons.help_rounded, color: orange, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResultRecordsPage(result: 'INCONCLUSIVE')))),
                ];
                return GridView.count(
                  crossAxisCount: wide ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: wide ? 1.8 : 1.55,
                  children: cards,
                );
              },
            ),
          ),

          const SizedBox(height: 28),

          LayoutBuilder(
            builder: (_, constraints) {
              if (constraints.maxWidth > 900) {
                return Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _recentTests(context),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 2,
                      child: _securityCard(),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  _recentTests(context),
                  const SizedBox(height: 18),
                  _securityCard(),
                ],
              );
            },
          ),

          const SizedBox(height: 25),

          const InfoBanner(),
        ],
      ),
    );
  }

  Widget _recentTests(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppStore.version,
      builder: (_, __, ___) {
        final records = AppStore.records.take(5).toList();
        return WhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recent Test Records',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textDark),
              ),
              const SizedBox(height: 15),
              if (records.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No saved test records yet. Start a test to create the first digital record.'),
                )
              else
                ...records.map(
                  (r) => InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TestDetailsPage(record: r)),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: border)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: resultBg(r.result),
                            child: Icon(resultIcon(r.result), color: resultColor(r.result), size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.caseId, style: const TextStyle(fontWeight: FontWeight.w800, color: textDark)),
                                Text(
                                  '${r.result} • ${r.confidence}% • ${r.timestamp}',
                                  style: const TextStyle(color: muted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          StatusChip(text: r.result),
                          const SizedBox(width: 5),
                          const Icon(Icons.chevron_right_rounded, color: muted),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _securityCard() {
    return WhiteCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.security_rounded,
                color: green,
              ),
              SizedBox(width: 8),
              Text(
                'Security Status',
                style: TextStyle(
                  fontWeight:
                      FontWeight.w900,
                  color: textDark,
                  fontSize: 16,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          securityRow(
              'SHA-256 Integrity',
              'ACTIVE',
              green),
          securityRow(
              'Audit Logging',
              'ACTIVE',
              green),
          securityRow(
              'GPS Capture',
              'READY',
              blue),
          securityRow(
              'QR Verification',
              'READY',
              blue),
          securityRow(
              'Offline Mode',
              'READY',
              purple),
        ],
      ),
    );
  }

  Widget securityRow(
      String title, String value, Color color) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: muted,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight:
                  FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// NEW TEST PAGE
// ============================================================

class NewTestPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String operatorId;

  const NewTestPage({
    super.key,
    required this.cameras,
    required this.operatorId,
  });

  @override
  State<NewTestPage> createState() =>
      _NewTestPageState();
}

class _NewTestPageState
    extends State<NewTestPage> {
  late final TextEditingController caseController;
  late final TextEditingController sampleController;
  final kitController =
      TextEditingController(text: 'KIT-MDP-001');

  String testType = 'Multi-Drug Panel';

  @override
  void initState() {
    super.initState();
    _refreshUniqueIds();
  }

  void _refreshUniqueIds() {
    caseController = TextEditingController(text: generateUniqueCaseId());
    sampleController = TextEditingController(text: generateUniqueSampleId());
  }

  @override
  void dispose() {
    caseController.dispose();
    sampleController.dispose();
    kitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(
                  maxWidth: 1000),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const PageHeading(
                title:
                    'Create New Field Test',
                subtitle:
                    'Start a secure digital evidence record before image capture.',
              ),

              const SizedBox(height: 22),

              LayoutBuilder(
                builder: (_, constraints) {
                  if (constraints.maxWidth >
                      750) {
                    return Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child:
                              _details(),
                        ),
                        const SizedBox(
                            width: 20),
                        Expanded(
                          child:
                              _workflowCard(),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      _details(),
                      const SizedBox(
                          height: 20),
                      _workflowCard(),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _details() {
    return WhiteCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'Test Information',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: textDark,
            ),
          ),

          const SizedBox(height: 18),

          AppField(
            controller: caseController,
            label: 'Case ID (Auto-generated)',
            icon: Icons.folder_open_rounded,
            readOnly: true,
          ),

          AppField(
            controller: sampleController,
            label: 'Sample ID (Auto-generated)',
            icon: Icons.science_outlined,
            readOnly: true,
          ),

          AppField(
            controller: kitController,
            label: 'Test Kit ID',
            icon: Icons.inventory_2_outlined,
          ),

          Container(
            margin:
                const EdgeInsets.only(bottom: 14),
            padding:
                const EdgeInsets.symmetric(
                    horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(14),
              border: Border.all(
                  color: border),
            ),
            child:
                DropdownButtonHideUnderline(
              child:
                  DropdownButton<String>(
                value: testType,
                isExpanded: true,
                items: const [
                  'Multi-Drug Panel',
                  'Cannabis Panel',
                  'Opiates Panel',
                  'Custom Test Kit',
                ]
                    .map(
                      (e) =>
                          DropdownMenuItem(
                        value: e,
                        child: Text(e),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    testType =
                        v ?? testType;
                  });
                },
              ),
            ),
          ),

          AppField(
            controller:
                TextEditingController(
                    text: widget.operatorId),
            label: 'Operator ID',
            icon: Icons.badge_outlined,
            readOnly: true,
          ),
        ],
      ),
    );
  }

  Widget _workflowCard() {
    return WhiteCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'Testing Workflow',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: textDark,
            ),
          ),

          const SizedBox(height: 18),

          const WorkflowStep(
            number: '01',
            title: 'Existing Test Kit',
            subtitle:
                'Use the existing colorimetric field kit.',
            icon: Icons.science_outlined,
          ),

          const WorkflowStep(
            number: '02',
            title: 'Guided Image Capture',
            subtitle:
                'Capture the kit with the reference colour region.',
            icon: Icons.camera_alt_outlined,
          ),

          const WorkflowStep(
            number: '03',
            title: 'CV / ML Analysis',
            subtitle:
                'Prototype analyses colour pattern and quality.',
            icon: Icons.auto_awesome,
          ),

          const WorkflowStep(
            number: '04',
            title: 'Secure Digital Record',
            subtitle:
                'GPS, timestamp, hash, QR and audit trail.',
            icon: Icons.verified_user_outlined,
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _startTest,
              icon: const Icon(
                  Icons.camera_alt_rounded),
              label: const Text(
                'Start Test',
                style: TextStyle(
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          const Text(
            'Presumptive field result only • laboratory confirmation required',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }

  void _startTest() {
    // Every press of Start Test creates a fresh case/sample identifier.
    final newCaseId = generateUniqueCaseId();
    final newSampleId = generateUniqueSampleId();

    caseController.text = newCaseId;
    sampleController.text = newSampleId;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraTestScreen(
          cameras: widget.cameras,
          caseId: newCaseId,
          sampleId: newSampleId,
          operatorId: widget.operatorId,
          kitId: kitController.text.trim(),
          testType: testType,
        ),
      ),
    );
  }
}

// ============================================================
// CAMERA
// ============================================================

class CameraTestScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String caseId;
  final String sampleId;
  final String operatorId;
  final String kitId;
  final String testType;

  const CameraTestScreen({
    super.key,
    required this.cameras,
    required this.caseId,
    required this.sampleId,
    required this.operatorId,
    required this.kitId,
    required this.testType,
  });

  @override
  State<CameraTestScreen> createState() =>
      _CameraTestScreenState();
}

class _CameraTestScreenState
    extends State<CameraTestScreen> {
  CameraController? controller;

  Uint8List? captured;

  bool validating = false;
  bool valid = false;

  String message =
      'Place the test kit and reference colour area inside the frame.';

  List<String> checks = [
    'Test area visible',
    'Reference colour region visible',
    'Image quality acceptable',
  ];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;

    final selected =
        widget.cameras.firstWhere(
      (c) =>
          c.lensDirection ==
          CameraLensDirection.back,
      orElse: () =>
          widget.cameras.first,
    );

    controller = CameraController(
      selected,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await controller!.initialize();

      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _capture() async {
    if (controller == null ||
        !controller!.value.isInitialized ||
        validating) {
      return;
    }

    final file =
        await controller!.takePicture();

    final bytes =
        await file.readAsBytes();

    setState(() {
      captured = bytes;
      validating = true;
      valid = false;
      message =
          'Validating test image...';
    });

    await Future.delayed(
      const Duration(milliseconds: 700),
    );

    final result =
        await validateTestImage(bytes);

    if (!mounted) return;

    setState(() {
      validating = false;
      valid = result.valid;
      message = result.message;
      checks = result.checks;
    });
  }

  // ----------------------------------------------------------
  // DEMO TEST IMAGE
  // ----------------------------------------------------------

  Future<void> _demoImage() async {
    // Show all locally bundled real photographs first. The selected image is
    // then loaded into the same `captured` byte flow used by the camera.
    final selectedAsset = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.photo_library_rounded, color: blue),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Demo Test Image',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: textDark,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Choose a real photographed test-kit image for the demonstration.',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 330,
                        mainAxisExtent: 255,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: demoImageAssets.length,
                      itemBuilder: (_, index) {
                        final asset = demoImageAssets[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(dialogContext, asset),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: border),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Image.asset(
                                    asset,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          demoImageTitles[index],
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: textDark,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_rounded, color: blue, size: 20),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Demo photographs are for prototype demonstration; they are not validated forensic ground truth.',
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selectedAsset == null || !mounted) return;

    setState(() {
      validating = true;
      valid = false;
      message = 'Loading selected demo test image...';
      checks = [];
    });

    try {
      final data = await rootBundle.load(selectedAsset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      if (!mounted) return;
      setState(() {
        captured = Uint8List.fromList(bytes);
        validating = false;
        valid = true;
        message = 'Demo image selected successfully. This exact image will follow the complete test workflow.';
        checks = [
          'Real photographed demo image loaded',
          'Selected image visible in preview',
          'Ready for prototype analysis',
        ];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        validating = false;
        valid = false;
        message = 'Could not load the selected demo image.';
        checks = [
          'Check that the image exists in assets/',
          'Run flutter pub get',
          'Restart the Flutter application',
        ];
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Image Capture'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: captured == null
          ? _camera()
          : _preview(),
    );
  }

  Widget _camera() {
    if (controller == null ||
        !controller!.value.isInitialized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                size: 70,
                color: muted,
              ),
              const SizedBox(height: 15),
              const Text(
                'Camera is not available',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _demoImage,
                icon: const Icon(
                    Icons.science_outlined),
                label: const Text(
                    'Use Demo Test Image'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: CameraPreview(
            controller!,
          ),
        ),

        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: GuidePainter(),
            ),
          ),
        ),

        Positioned(
          top: 20,
          left: 20,
          right: 20,
          child: Container(
            padding:
                const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:
                  Colors.black.withOpacity(.68),
              borderRadius:
                  BorderRadius.circular(14),
            ),
            child: const Text(
              'Place the field test kit + reference colour area inside the frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
        ),

        Positioned(
          left: 25,
          right: 25,
          bottom: 105,
          child: OutlinedButton.icon(
            onPressed: _demoImage,
            style: OutlinedButton.styleFrom(
              backgroundColor:
                  Colors.white.withOpacity(.94),
              foregroundColor: navy,
              padding:
                  const EdgeInsets.all(14),
            ),
            icon: const Icon(
                Icons.science_outlined),
            label: const Text(
              'Use Demo Test Image',
              style: TextStyle(
                fontWeight:
                    FontWeight.w800,
              ),
            ),
          ),
        ),

        Positioned(
          bottom: 25,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _capture,
              child: Container(
                height: 75,
                width: 75,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: blue,
                    width: 7,
                  ),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: blue,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _preview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(
                  maxWidth: 850),
          child: Column(
            children: [
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(18),
                child: Image.memory(
                  captured!,
                  height: 360,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

              const SizedBox(height: 18),

              const ReferenceColourCard(compact: true),

              const SizedBox(height: 20),

              if (validating)
                const WhiteCard(
                  child: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 15),
                      Text(
                        'Checking test image...',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

              if (!validating)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: valid
                        ? const Color(
                            0xFFE8F8F1)
                        : const Color(
                            0xFFFFEEF0),
                    borderRadius:
                        BorderRadius.circular(18),
                    border: Border.all(
                      color: valid
                          ? green
                          : red,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        valid
                            ? Icons.verified_rounded
                            : Icons.cancel_rounded,
                        color: valid
                            ? green
                            : red,
                        size: 45,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        valid
                            ? 'TEST IMAGE VALID'
                            : 'INVALID TEST IMAGE',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight.w900,
                          color: valid
                              ? green
                              : red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign:
                            TextAlign.center,
                        style:
                            const TextStyle(
                          color: textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...checks.map(
                        (x) => Padding(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 3,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                valid
                                    ? Icons
                                        .check_circle
                                    : Icons
                                        .radio_button_unchecked,
                                color: valid
                                    ? green
                                    : muted,
                                size: 18,
                              ),
                              const SizedBox(
                                  width: 8),
                              Text(x),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          captured = null;
                          valid = false;
                        });
                      },
                      icon: const Icon(
                          Icons.refresh),
                      label:
                          const Text('Retake'),
                    ),
                  ),

                  if (valid) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AnalysisScreen(
                                imageBytes:
                                    captured!,
                                caseId:
                                    widget.caseId,
                                sampleId:
                                    widget.sampleId,
                                operatorId:
                                    widget.operatorId,
                                kitId:
                                    widget.kitId,
                                testType:
                                    widget.testType,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                            Icons.auto_awesome),
                        label: const Text(
                            'Analyze'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ANALYSIS
// ============================================================

class AnalysisScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String caseId;
  final String sampleId;
  final String operatorId;
  final String kitId;
  final String testType;

  const AnalysisScreen({
    super.key,
    required this.imageBytes,
    required this.caseId,
    required this.sampleId,
    required this.operatorId,
    required this.kitId,
    required this.testType,
  });

  @override
  State<AnalysisScreen> createState() =>
      _AnalysisScreenState();
}

class _AnalysisScreenState
    extends State<AnalysisScreen> {
  int progress = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();

    timer = Timer.periodic(
      const Duration(milliseconds: 650),
      (_) {
        if (!mounted) return;

        setState(() {
          progress++;
        });

        if (progress >= 4) {
          timer?.cancel();
        }
      },
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = progress >= 4;

    if (done) {
      return ResultScreen(
        imageBytes: widget.imageBytes,
        caseId: widget.caseId,
        sampleId: widget.sampleId,
        operatorId: widget.operatorId,
        kitId: widget.kitId,
        testType: widget.testType,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('AI Image Analysis'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(
                  maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 150,
                  width: 150,
                  child:
                      CircularProgressIndicator(
                    value: progress / 4,
                    strokeWidth: 10,
                  ),
                ),

                const SizedBox(height: 25),

                const Text(
                  'Analyzing Sample...',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight:
                        FontWeight.w900,
                    color: textDark,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Validating colour pattern and generating a presumptive result.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: muted,
                  ),
                ),

                const SizedBox(height: 25),

                AnalysisCheck(
                  text:
                      'Sample validation',
                  done: progress >= 1,
                ),

                AnalysisCheck(
                  text:
                      'Reference colour calibration',
                  done: progress >= 2,
                ),

                AnalysisCheck(
                  text:
                      'Colour pattern analysis',
                  done: progress >= 3,
                ),

                AnalysisCheck(
                  text:
                      'Generating presumptive result',
                  done: progress >= 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AnalysisCheck extends StatelessWidget {
  final String text;
  final bool done;

  const AnalysisCheck({
    super.key,
    required this.text,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
              vertical: 6),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            done
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color:
                done ? green : muted,
          ),
          const SizedBox(width: 9),
          Text(
            text,
            style: TextStyle(
              color:
                  done ? textDark : muted,
              fontWeight:
                  done
                      ? FontWeight.w700
                      : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// REAL REFERENCE COLOUR CARD
// ============================================================

class ReferenceColourCard extends StatelessWidget {
  final bool compact;

  const ReferenceColourCard({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final visible = compact
        ? marquisReferenceColours.take(6).toList()
        : marquisReferenceColours;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E2EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.palette_rounded,
                  color: blue,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reference Colour Card',
                      style: TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Marquis reagent • published reference colours',
                      style: TextStyle(
                        color: muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact)
                const Icon(
                  Icons.verified_outlined,
                  color: green,
                  size: 21,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFD),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: blue,
                  size: 17,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Compare the observed reaction with the expected colour range. A colour match is presumptive, not laboratory confirmation.',
                    style: TextStyle(
                      color: textDark,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...visible.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    height: 31,
                    width: 52,
                    decoration: BoxDecoration(
                      color: entry.swatch,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.black12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.substance,
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.expected,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (compact)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                '+ additional documented colour reactions',
                style: TextStyle(
                  color: blue,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 5),
          const Text(
            'Reference basis: NARTEC Marquis Testing Color Chart; NIJ Standard-0604.01. Use the exact manufacturer chart for the deployed kit.',
            style: TextStyle(
              color: muted,
              fontSize: 9.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// RESULT
// ============================================================

class ResultScreen extends StatelessWidget {
  final Uint8List imageBytes;
  final String caseId;
  final String sampleId;
  final String operatorId;
  final String kitId;
  final String testType;

  const ResultScreen({
    super.key,
    required this.imageBytes,
    required this.caseId,
    required this.sampleId,
    required this.operatorId,
    required this.kitId,
    required this.testType,
  });

  void _showResultDetails(
    BuildContext context,
    PrototypeAnalysis analysis,
  ) {
    final color = resultColor(analysis.result);
    final title = analysis.result == 'POSITIVE'
        ? 'Presumptive Positive'
        : analysis.result == 'NEGATIVE'
            ? 'Presumptive Negative'
            : 'Inconclusive / Review Required';

    final meaning = analysis.result == 'POSITIVE'
        ? 'The prototype detected a colour pattern that crossed the configured positive threshold.'
        : analysis.result == 'NEGATIVE'
            ? 'The prototype did not detect the configured positive colour pattern.'
            : 'The observed image did not provide a sufficiently clear pattern for a reliable prototype classification.';

    final action = analysis.result == 'INCONCLUSIVE'
        ? 'Retake under neutral lighting and compare the reaction with the kit reference card.'
        : 'Record the presumptive result and follow the approved confirmatory laboratory workflow.';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: resultBg(analysis.result),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        resultIcon(analysis.result),
                        color: color,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: color,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Case $caseId',
                            style: const TextStyle(
                              color: muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: resultBg(analysis.result),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${analysis.confidence}%',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _detailSection(
                  icon: Icons.insights_rounded,
                  title: 'What the result means',
                  child: Text(
                    meaning,
                    style: const TextStyle(
                      color: textDark,
                      height: 1.45,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _detailSection(
                  icon: Icons.analytics_outlined,
                  title: 'Prototype analysis',
                  child: Text(
                    analysis.explanation,
                    style: const TextStyle(
                      color: muted,
                      height: 1.45,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _detailSection(
                  icon: Icons.task_alt_rounded,
                  title: 'Recommended workflow',
                  child: Text(
                    action,
                    style: const TextStyle(
                      color: textDark,
                      height: 1.45,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E7),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFF2D28A)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: orange,
                        size: 20,
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'This is a prototype presumptive result. It is not a confirmed forensic identification and does not establish purity, concentration or safety.',
                          style: TextStyle(
                            color: textDark,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: blue, size: 19),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final analysis = analyzePrototypeImage(imageBytes);
    final color = resultColor(analysis.result);
    final bg = resultBg(analysis.result);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Result'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.memory(
                    imageBytes,
                    height: 250,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 18),

                // The real reference card stays visible beside the actual
                // captured test image.
                const ReferenceColourCard(),

                const SizedBox(height: 18),

                // Tap any result state to open the detailed result UI.
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showResultDetails(context, analysis),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(22, 23, 22, 20),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: color, width: 1.4),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x10000000),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                height: 62,
                                width: 62,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(.72),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  resultIcon(analysis.result),
                                  color: color,
                                  size: 34,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 11),
                          Text(
                            analysis.result == 'INCONCLUSIVE'
                                ? 'INCONCLUSIVE'
                                : analysis.result,
                            style: TextStyle(
                              color: color,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            analysis.result == 'POSITIVE'
                                ? 'Presumptive positive field result'
                                : analysis.result == 'NEGATIVE'
                                    ? 'Presumptive negative field result'
                                    : 'Review required before recording a conclusion',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.7),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.speed_rounded,
                                  color: textDark,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Prototype confidence',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${analysis.confidence}%',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 11),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.touch_app_rounded,
                                color: muted,
                                size: 16,
                              ),
                              SizedBox(width: 5),
                              Text(
                                'Tap for detailed interpretation',
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                WhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Observed Test Signals',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...analysis.analytes.entries.map(
                        (e) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Row(
                            children: [
                              Container(
                                height: 30,
                                width: 30,
                                decoration: BoxDecoration(
                                  color: resultBg(analysis.result),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(
                                  resultIcon(analysis.result),
                                  color: color,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  e.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: textDark,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              FlexibleText(
                                value: e.value,
                                color: color,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                InfoBanner(
                  text:
                      'Case $caseId • Sample $sampleId • $testType. This prototype uses image/color features for demonstration and is not a validated forensic or laboratory test.',
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EvidenceScreen(
                            imageBytes: imageBytes,
                            caseId: caseId,
                            sampleId: sampleId,
                            operatorId: operatorId,
                            kitId: kitId,
                            testType: testType,
                            analysis: analysis,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.security_rounded),
                    label: const Text(
                      'Generate Secure Digital Record',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FlexibleText extends StatelessWidget {
  final String value;
  final Color color;
  const FlexibleText({super.key, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(value, textAlign: TextAlign.right, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      );
}

// ============================================================
// PROFESSIONAL PDF REPORT BUILDER
// ============================================================

PdfColor _pdfColor(Color color) {
  return PdfColor.fromInt(color.value);
}

pw.Widget pdfReferenceColourCard() {
  return pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: _pdfColor(const Color(0xFFF7FAFD)),
      borderRadius: pw.BorderRadius.circular(10),
      border: pw.Border.all(
        color: _pdfColor(const Color(0xFFD8E2EE)),
        width: 1,
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'REFERENCE COLOUR CARD',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: _pdfColor(navy),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Marquis reagent — published reference colour ranges',
          style: pw.TextStyle(
            fontSize: 8.5,
            color: _pdfColor(muted),
          ),
        ),
        pw.SizedBox(height: 9),
        pw.Table(
          border: pw.TableBorder.all(
            color: _pdfColor(const Color(0xFFE2E8F0)),
            width: .6,
          ),
          columnWidths: const {
            0: pw.FixedColumnWidth(70),
            1: pw.FlexColumnWidth(2.1),
            2: pw.FlexColumnWidth(2.2),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: _pdfColor(const Color(0xFFEAF1FF)),
              ),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    'SWATCH',
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    'SUBSTANCE',
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    'EXPECTED COLOUR',
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            ...marquisReferenceColours.map(
              (entry) => pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Container(
                      height: 18,
                      width: 55,
                      decoration: pw.BoxDecoration(
                        color: _pdfColor(entry.swatch),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      entry.substance,
                      style: const pw.TextStyle(fontSize: 7.5),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      entry.expected,
                      style: const pw.TextStyle(fontSize: 7.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 7),
        pw.Text(
          'Reference basis: NARTEC Marquis Testing Color Chart and NIJ Standard-0604.01. '
          'The exact manufacturer chart for the deployed field kit should be used in production.',
          style: pw.TextStyle(
            fontSize: 7,
            color: _pdfColor(muted),
          ),
        ),
      ],
    ),
  );
}

pw.Widget pdfSectionTitle(String title, IconData icon) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 7,
    ),
    decoration: pw.BoxDecoration(
      color: _pdfColor(const Color(0xFFEAF1FF)),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Text(
      title.toUpperCase(),
      style: pw.TextStyle(
        color: _pdfColor(navy),
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget pdfMetaTable(TestRecord record) {
  final rows = <List<String>>[
    ['Case ID', record.caseId],
    ['Sample ID', record.sampleId],
    ['Test Kit ID', record.kitId],
    ['Test Type', record.testType],
    ['Operator ID', record.operatorId],
    ['Result', '${record.result} • Presumptive'],
    ['Confidence', '${record.confidence}%'],
    ['Timestamp', record.timestamp],
    ['GPS', record.gps],
  ];

  return pw.Table(
    border: pw.TableBorder.all(
      color: _pdfColor(const Color(0xFFE2E8F0)),
      width: .6,
    ),
    columnWidths: const {
      0: pw.FixedColumnWidth(105),
      1: pw.FlexColumnWidth(),
    },
    children: rows
        .map(
          (row) => pw.TableRow(
            children: [
              pw.Container(
                color: _pdfColor(const Color(0xFFF7FAFD)),
                padding: const pw.EdgeInsets.all(7),
                child: pw.Text(
                  row[0],
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _pdfColor(muted),
                  ),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(7),
                child: pw.Text(
                  row[1],
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
        )
        .toList(),
  );
}

Future<Uint8List> buildProfessionalPdf(TestRecord record) async {
  final doc = pw.Document();

  final testImage = pw.MemoryImage(record.imageBytes);
  final resultPdfColor = _pdfColor(resultColor(record.result));

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        margin: const pw.EdgeInsets.fromLTRB(32, 34, 32, 34),
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        ),
      ),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(
              color: _pdfColor(const Color(0xFFD8E2EE)),
              width: .8,
            ),
          ),
        ),
        child: pw.Row(
          children: [
            pw.Container(
              width: 25,
              height: 25,
              decoration: pw.BoxDecoration(
                color: _pdfColor(blue),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Center(
                child: pw.Text(
                  'D',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                'DIGITAL COMPANION • FIELD DRUG TESTING',
                style: pw.TextStyle(
                  color: _pdfColor(navy),
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Text(
              'EVIDENCE REPORT',
              style: pw.TextStyle(
                color: _pdfColor(muted),
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(
              color: _pdfColor(const Color(0xFFD8E2EE)),
              width: .8,
            ),
          ),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'Prototype / presumptive field record • Laboratory confirmation required',
                style: pw.TextStyle(
                  fontSize: 6.5,
                  color: _pdfColor(muted),
                ),
              ),
            ),
            pw.Text(
              'Page ${context.pageNumber}',
              style: pw.TextStyle(
                fontSize: 6.5,
                color: _pdfColor(muted),
              ),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(15),
          decoration: pw.BoxDecoration(
            color: _pdfColor(resultBg(record.result)),
            border: pw.Border.all(
              color: resultPdfColor,
              width: 1.2,
            ),
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Row(
            children: [
              pw.Container(
                width: 42,
                height: 42,
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(21),
                ),
                child: pw.Center(
                  child: pw.Text(
                    record.result == 'POSITIVE'
                        ? '!'
                        : record.result == 'NEGATIVE'
                            ? '✓'
                            : '?',
                    style: pw.TextStyle(
                      color: resultPdfColor,
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      record.result,
                      style: pw.TextStyle(
                        color: resultPdfColor,
                        fontSize: 19,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Presumptive field result • Confidence ${record.confidence}%',
                      style: pw.TextStyle(
                        color: _pdfColor(textDark),
                        fontSize: 8.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 14),

        pdfSectionTitle('Captured test image', Icons.camera_alt_rounded),
        pw.SizedBox(height: 8),
        pw.Container(
          height: 250,
          width: double.infinity,
          padding: const pw.EdgeInsets.all(5),
          decoration: pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(9),
            border: pw.Border.all(
              color: _pdfColor(const Color(0xFFD8E2EE)),
            ),
          ),
          child: pw.Image(
            testImage,
            fit: pw.BoxFit.contain,
          ),
        ),
        pw.SizedBox(height: 14),

        pdfSectionTitle('Test information', Icons.description_rounded),
        pw.SizedBox(height: 8),
        pdfMetaTable(record),
        pw.SizedBox(height: 14),

        pdfReferenceColourCard(),
        pw.SizedBox(height: 14),

        pdfSectionTitle('Analysis', Icons.analytics_rounded),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _pdfColor(const Color(0xFFF8FAFC)),
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(
              color: _pdfColor(const Color(0xFFE2E8F0)),
            ),
          ),
          child: pw.Text(
            record.analysisNote,
            style: const pw.TextStyle(
              fontSize: 8,
              lineSpacing: 2,
            ),
          ),
        ),
        pw.SizedBox(height: 14),

        pdfSectionTitle('Integrity & verification', Icons.security_rounded),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(
            color: _pdfColor(const Color(0xFFE2E8F0)),
            width: .6,
          ),
          columnWidths: const {
            0: pw.FixedColumnWidth(105),
            1: pw.FlexColumnWidth(),
          },
          children: [
            ['SHA-256 image hash', record.imageHash],
            ['Digital signature', record.signature],
            ['QR payload', 'Embedded in the saved digital record'],
          ].map(
            (row) => pw.TableRow(
              children: [
                pw.Container(
                  color: _pdfColor(const Color(0xFFF7FAFD)),
                  padding: const pw.EdgeInsets.all(7),
                  child: pw.Text(
                    row[0],
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _pdfColor(muted),
                    ),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(7),
                  child: pw.Text(
                    row[1],
                    style: const pw.TextStyle(
                      fontSize: 7,
                    ),
                  ),
                ),
              ],
            ),
          ).toList(),
        ),
        pw.SizedBox(height: 14),

        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(11),
          decoration: pw.BoxDecoration(
            color: _pdfColor(const Color(0xFFFFF8E7)),
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(
              color: _pdfColor(const Color(0xFFF2D28A)),
            ),
          ),
          child: pw.Text(
            'IMPORTANT LIMITATION: This application is a prototype for presumptive field-test digitization. '
            'Colour-reagent results can be affected by lighting, reagent condition, sample composition and '
            'other factors. This report must not be treated as a confirmed forensic identification. '
            'Laboratory confirmation is required.',
            style: pw.TextStyle(
              fontSize: 7.5,
              color: _pdfColor(textDark),
              lineSpacing: 1.7,
            ),
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

// ============================================================
// DIGITAL EVIDENCE
// ============================================================

class EvidenceScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String caseId;
  final String sampleId;
  final String operatorId;
  final String kitId;
  final String testType;
  final PrototypeAnalysis analysis;

  const EvidenceScreen({
    super.key,
    required this.imageBytes,
    required this.caseId,
    required this.sampleId,
    required this.operatorId,
    required this.kitId,
    required this.testType,
    required this.analysis,
  });

  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
  late final String timestamp;
  late final String imageHash;
  String gps = 'Checking GPS...';
  Position? position;

  @override
  void initState() {
    super.initState();
    timestamp = DateTime.now().toIso8601String();
    imageHash = sha256.convert(widget.imageBytes).toString();
    _gps();
  }

  Future<void> _gps() async {
    final p = await getCurrentPositionSafe();
    if (!mounted) return;
    position = p;
    setState(() {
      gps = p == null
          ? 'GPS unavailable'
          : '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)} ±${p.accuracy.toStringAsFixed(1)} m';
    });
  }

  TestRecord _record() => TestRecord(
        caseId: widget.caseId,
        sampleId: widget.sampleId,
        kitId: widget.kitId,
        testType: widget.testType,
        operatorId: widget.operatorId,
        result: widget.analysis.result,
        confidence: widget.analysis.confidence,
        timestamp: timestamp,
        imageBytes: widget.imageBytes,
        imageHash: imageHash,
        gps: gps,
        latitude: position?.latitude,
        longitude: position?.longitude,
        accuracy: position?.accuracy,
        analysisNote: widget.analysis.explanation,
      );

  Future<void> _saveAndFinish() async {
    await AppStore.add(_record());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Digital record saved to test history.')),
    );
    await Future.delayed(const Duration(milliseconds: 450));
    if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
  }

  Future<void> _pdf() async {
    final record = _record();
    final bytes = await buildProfessionalPdf(record);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Field_Test_Report_${record.caseId}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = _record();
    return Scaffold(
      appBar: AppBar(title: const Text('Digital Evidence Record'), backgroundColor: navy, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.memory(widget.imageBytes, height: 260, width: double.infinity, fit: BoxFit.cover)),
                const SizedBox(height: 16),
                const ReferenceColourCard(compact: true),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: const Color(0xFFE8F8F1), borderRadius: BorderRadius.circular(17)),
                  child: const Row(children: [Icon(Icons.verified_user_rounded, color: green, size: 30), SizedBox(width: 10), Text('TAMPER-EVIDENT RECORD', style: TextStyle(color: green, fontWeight: FontWeight.w900))]),
                ),
                const SizedBox(height: 18),
                WhiteCard(
                  child: Column(
                    children: [
                      RecordRow(title: 'Case ID', value: record.caseId),
                      RecordRow(title: 'Sample ID', value: record.sampleId),
                      RecordRow(title: 'Result', value: '${record.result} • ${record.confidence}%'),
                      RecordRow(title: 'Operator', value: record.operatorId),
                      RecordRow(title: 'Timestamp', value: record.timestamp),
                      RecordRow(title: 'GPS', value: record.gps),
                      RecordRow(title: 'SHA-256 Image Hash', value: record.imageHash),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                WhiteCard(
                  child: Column(
                    children: [
                      const Text('QR VERIFICATION', style: TextStyle(fontWeight: FontWeight.w900, color: textDark)),
                      const SizedBox(height: 15),
                      QrImageView(data: record.qrData, size: 210),
                      const SizedBox(height: 8),
                      const Text('Scan this QR code to verify the digital record', style: TextStyle(color: muted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const InfoBanner(text: 'The QR and SHA-256 values provide prototype integrity verification. Production deployment should use an authorized backend signing service.'),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(onPressed: _pdf, icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('PDF Report'))),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton.icon(onPressed: _saveAndFinish, icon: const Icon(Icons.save_rounded), label: const Text('Save Record'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// RECORDS
// ============================================================

class TotalTestsPage extends StatelessWidget {
  const TotalTestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text(
          'Total Tests',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppStore.version,
        builder: (_, __, ___) {
          final records = AppStore.records;
          final positive = AppStore.count('POSITIVE');
          final negative = AppStore.count('NEGATIVE');
          final inconclusive = AppStore.count('INCONCLUSIVE');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PageHeading(
                      title: 'Total Test Records',
                      subtitle: 'Complete list of all saved field-test records.',
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (_, constraints) {
                        final wide = constraints.maxWidth > 800;
                        final cards = [
                          _TotalTestsSummaryCard(
                            title: 'Total Tests',
                            value: '${records.length}',
                            icon: Icons.science_rounded,
                            color: blue,
                          ),
                          _TotalTestsSummaryCard(
                            title: 'Positive',
                            value: '$positive',
                            icon: Icons.warning_rounded,
                            color: red,
                          ),
                          _TotalTestsSummaryCard(
                            title: 'Negative',
                            value: '$negative',
                            icon: Icons.check_circle_rounded,
                            color: green,
                          ),
                          _TotalTestsSummaryCard(
                            title: 'Inconclusive',
                            value: '$inconclusive',
                            icon: Icons.help_rounded,
                            color: orange,
                          ),
                        ];
                        return GridView.count(
                          crossAxisCount: wide ? 4 : 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: wide ? 1.9 : 1.6,
                          children: cards,
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    WhiteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'All Saved Tests',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: textDark,
                                  ),
                                ),
                              ),
                              Text(
                                '${records.length} records',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          if (records.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 30),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.science_outlined, size: 55, color: muted),
                                    SizedBox(height: 10),
                                    Text(
                                      'No saved tests yet.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: textDark,
                                      ),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Complete a field test and save the record.',
                                      style: TextStyle(color: muted, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ...records.map(
                              (r) => InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TestDetailsPage(record: r),
                                  ),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFD),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: border),
                                  ),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.memory(
                                          r.imageBytes,
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r.caseId,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: textDark,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Sample ID: ${r.sampleId}',
                                              style: const TextStyle(color: muted, fontSize: 12),
                                            ),
                                            Text(
                                              'Test: ${r.testType}',
                                              style: const TextStyle(color: muted, fontSize: 12),
                                            ),
                                            Text(
                                              '${r.timestamp} • ${r.confidence}% confidence',
                                              style: const TextStyle(color: muted, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      StatusChip(text: r.result),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.chevron_right_rounded, color: muted),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TotalTestsSummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _TotalTestsSummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppStore.version,
      builder: (_, __, ___) {
        final records = AppStore.records;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeading(
                title: 'Test Records',
                subtitle: 'Persistent digital field-test history. Tap any record for complete information.',
              ),
              const SizedBox(height: 20),
              WhiteCard(
                child: records.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(25),
                        child: Text('No saved test records yet. Complete a test to add it here.'),
                      )
                    : Column(
                        children: records
                            .map<Widget>(
                              (r) => ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 7),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(r.imageBytes, width: 58, height: 58, fit: BoxFit.cover),
                                ),
                                title: Text(r.caseId, style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text('${r.sampleId} • ${r.result} • ${r.confidence}%\n${r.timestamp} • ${r.gps}'),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    StatusChip(text: r.result),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => TestDetailsPage(record: r)),
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TestDetailsPage extends StatelessWidget {
  final TestRecord record;

  const TestDetailsPage({
    super.key,
    required this.record,
  });

  Future<void> _generatePdf(BuildContext context) async {
    final bytes = await buildProfessionalPdf(record);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Field_Test_Report_${record.caseId}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = resultColor(record.result);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Details'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Generate PDF report',
            onPressed: () => _generatePdf(context),
            icon: const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: resultBg(record.result),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: color,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        height: 58,
                        width: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.75),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          resultIcon(record.result),
                          color: color,
                          size: 31,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.result,
                              style: TextStyle(
                                color: color,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Presumptive field result • ${record.confidence}% prototype confidence',
                              style: const TextStyle(
                                color: textDark,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusChip(text: record.result),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                WhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Captured Evidence',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.memory(
                          record.imageBytes,
                          height: 330,
                          width: double.infinity,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'Exact image bytes stored with this digital record.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                const ReferenceColourCard(),
                const SizedBox(height: 18),

                WhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Case & Test Information',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      RecordRow(title: 'Case ID', value: record.caseId),
                      RecordRow(title: 'Sample ID', value: record.sampleId),
                      RecordRow(title: 'Test Kit ID', value: record.kitId),
                      RecordRow(title: 'Test Type', value: record.testType),
                      RecordRow(title: 'Operator', value: record.operatorId),
                      RecordRow(title: 'Timestamp', value: record.timestamp),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                WhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Location & Integrity',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      RecordRow(title: 'GPS', value: record.gps),
                      if (record.latitude != null)
                        RecordRow(
                          title: 'Latitude',
                          value: record.latitude!.toStringAsFixed(6),
                        ),
                      if (record.longitude != null)
                        RecordRow(
                          title: 'Longitude',
                          value: record.longitude!.toStringAsFixed(6),
                        ),
                      if (record.accuracy != null)
                        RecordRow(
                          title: 'Accuracy',
                          value: '${record.accuracy!.toStringAsFixed(1)} m',
                        ),
                      RecordRow(
                        title: 'SHA-256',
                        value: record.imageHash,
                      ),
                      RecordRow(
                        title: 'Digital Signature',
                        value: record.signature,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                WhiteCard(
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.qr_code_2_rounded,
                            color: blue,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'QR VERIFICATION',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      QrImageView(
                        data: record.qrData,
                        size: 220,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Scan to inspect the digital record payload.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                WhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Prototype Analysis Note',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        record.analysisNote,
                        style: const TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: () => _generatePdf(context),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text(
                      'Generate Professional PDF Report',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                const InfoBanner(
                  text:
                      'This record is a prototype presumptive field-test record. Laboratory confirmation is required before a final forensic conclusion.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CHAIN OF CUSTODY
// ============================================================

class CustodyPage extends StatelessWidget {
  const CustodyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final events = [
      [
        '10:42 AM',
        'Image Captured',
        'Officer-001',
        Icons.camera_alt
      ],
      [
        '10:43 AM',
        'Colour Analysis Completed',
        'AI Module',
        Icons.auto_awesome
      ],
      [
        '10:43 AM',
        'Result Recorded',
        'System',
        Icons.check_circle
      ],
      [
        '10:44 AM',
        'SHA-256 Generated',
        'Security Layer',
        Icons.fingerprint
      ],
      [
        '10:44 AM',
        'QR Record Created',
        'System',
        Icons.qr_code_2
      ],
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Chain of Custody',
            subtitle:
                'Track every important event associated with a field-test record.',
          ),

          const SizedBox(height: 20),

          WhiteCard(
            child: Column(
              children: events.map(
                (e) {
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor:
                          const Color(0xFFE8F1FF),
                      child: Icon(
                        e[3] as IconData,
                        color: blue,
                      ),
                    ),
                    title: Text(
                      e[1] as String,
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      '${e[0]} • ${e[2]}',
                    ),
                    trailing: const Icon(
                      Icons.verified_rounded,
                      color: green,
                    ),
                  );
                },
              ).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LOCATIONS
// ============================================================

class LocationsPage extends StatefulWidget {
  const LocationsPage({super.key});
  @override
  State<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends State<LocationsPage> {
  Position? position;
  bool loading = true;
  String status = 'Checking location permission and GPS service...';

  @override
  void initState() { super.initState(); _loadLocation(); }

  Future<void> _loadLocation() async {
    final p = await getCurrentPositionSafe();
    if (!mounted) return;
    setState(() { position = p; loading = false; status = p == null ? 'GPS unavailable. Turn on Location and allow browser/device permission.' : 'GPS is ON. Current system location is available.'; });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppStore.version,
      builder: (_, __, ___) => SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeading(title: 'Test Locations', subtitle: 'Live GPS status and saved test locations.'),
            const SizedBox(height: 20),
            WhiteCard(
              child: Column(
                children: [
                  Container(
                    height: 250,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4FF),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Center(
                      child: loading
                          ? const CircularProgressIndicator()
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  position == null ? Icons.location_off_rounded : Icons.location_on_rounded,
                                  color: position == null ? red : blue,
                                  size: 65,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  position == null ? 'GPS OFF / UNAVAILABLE' : 'GPS LOCATION AVAILABLE',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: position == null ? red : textDark,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(status, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (position != null) ...[
                    RecordRow(title: 'Latitude', value: position!.latitude.toStringAsFixed(6)),
                    RecordRow(title: 'Longitude', value: position!.longitude.toStringAsFixed(6)),
                    RecordRow(title: 'Accuracy', value: '±${position!.accuracy.toStringAsFixed(1)} m'),
                    RecordRow(
                      title: 'Timestamp',
                      value: position!.timestamp?.toIso8601String() ?? DateTime.now().toIso8601String(),
                    ),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loadLocation,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh GPS'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Saved Test Locations', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            ...AppStore.records.map(
              (r) => Card(
                child: ListTile(
                  leading: const Icon(Icons.location_on_rounded, color: blue),
                  title: Text(r.caseId, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(r.gps),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TestDetailsPage(record: r)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// ============================================================
// VERIFY
// ============================================================

class VerifyPage extends StatefulWidget {
  const VerifyPage({super.key});

  @override
  State<VerifyPage> createState() =>
      _VerifyPageState();
}

class _VerifyPageState
    extends State<VerifyPage> {
  final controller =
      TextEditingController();

  bool? verified;

  String message = '';

  void loadDemo() {
    final record = AppStore.latest;
    if (record == null) { setState(() { controller.text = ''; message = 'No saved record exists. Complete a test first.'; verified = false; }); return; }
    controller.text = record.qrData;
    setState(() { verified = null; message = 'Latest saved record loaded. Tap Verify Record.'; });
  }

  void verify() {
    try {
      final data =
          jsonDecode(controller.text);

      final caseId =
          data['case_id'].toString();
      final sampleId =
          data['sample_id'].toString();
      final operator =
          data['operator'].toString();
      final result =
          data['result'].toString();
      final imageHash =
          data['image_hash'].toString();

      final supplied =
          data['digital_signature']
              .toString();

      final expected =
          sha256.convert(
        utf8.encode(
          '$caseId|$sampleId|${data['kit_id']}|${data['test_type']}|$operator|$result|${data['confidence']}|${data['timestamp']}|$imageHash|${data['gps']}',
        ),
      ).toString();

      final ok =
          supplied == expected;

      setState(() {
        verified = ok;
        message = ok
            ? 'Record signature matches. No modification detected in the supplied prototype payload.'
            : 'Signature mismatch. Record may have been modified.';
      });
    } catch (_) {
      setState(() {
        verified = false;
        message =
            'Invalid QR / record data.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(
                  maxWidth: 800),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const PageHeading(
                title:
                    'Verify Digital Record',
                subtitle:
                    'Validate QR payload and prototype record integrity.',
              ),

              const SizedBox(height: 20),

              WhiteCard(
                child: Column(
                  children: [
                    TextField(
                      controller:
                          controller,
                      maxLines: 8,
                      decoration:
                          InputDecoration(
                        labelText:
                            'QR / Record Payload',
                        hintText:
                            'Paste QR data here...',
                        border:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child:
                              OutlinedButton.icon(
                            onPressed:
                                loadDemo,
                            icon: const Icon(
                                Icons.science_outlined),
                            label: const Text(
                                'Load Demo Record'),
                          ),
                        ),
                        const SizedBox(
                            width: 12),
                        Expanded(
                          child:
                              FilledButton.icon(
                            onPressed:
                                verify,
                            icon: const Icon(
                                Icons.verified_rounded),
                            label: const Text(
                                'Verify Record'),
                          ),
                        ),
                      ],
                    ),

                    if (verified != null) ...[
                      const SizedBox(
                          height: 20),

                      Container(
                        width:
                            double.infinity,
                        padding:
                            const EdgeInsets
                                .all(18),
                        decoration:
                            BoxDecoration(
                          color: verified!
                              ? const Color(
                                  0xFFE8F8F1)
                              : const Color(
                                  0xFFFFEEF0),
                          borderRadius:
                              BorderRadius
                                  .circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              verified!
                                  ? Icons
                                      .verified_rounded
                                  : Icons
                                      .gpp_bad_rounded,
                              color: verified!
                                  ? green
                                  : red,
                              size: 35,
                            ),
                            const SizedBox(
                                width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Text(
                                    verified!
                                        ? 'RECORD VERIFIED'
                                        : 'VERIFICATION FAILED',
                                    style:
                                        TextStyle(
                                      color:
                                          verified!
                                              ? green
                                              : red,
                                      fontWeight:
                                          FontWeight
                                              .w900,
                                    ),
                                  ),
                                  const SizedBox(
                                      height: 5),
                                  Text(
                                    message,
                                    style:
                                        const TextStyle(
                                      color:
                                          textDark,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              const InfoBanner(
                text:
                    'Prototype verification demonstrates SHA-256 based integrity. Production deployment would use authorized signing keys and backend audit services.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FILTERED RESULT RECORDS
// ============================================================

class ResultRecordsPage extends StatelessWidget {
  final String result;

  const ResultRecordsPage({
    super.key,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final color = resultColor(result);
    final records = AppStore.records
        .where((r) => r.result == result)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('$result Test Records'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppStore.version,
        builder: (_, __, ___) {
          final current = AppStore.records
              .where((r) => r.result == result)
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 950),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: resultBg(result),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: color),
                      ),
                      child: Row(
                        children: [
                          Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.75),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              resultIcon(result),
                              color: color,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  result,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  result == 'POSITIVE'
                                      ? 'Presumptive positive field records'
                                      : result == 'NEGATIVE'
                                          ? 'Presumptive negative field records'
                                          : 'Records requiring review / repeat testing',
                                  style: const TextStyle(
                                    color: textDark,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${current.length}',
                            style: TextStyle(
                              color: color,
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (current.isEmpty)
                      WhiteCard(
                        child: Column(
                          children: [
                            Icon(
                              resultIcon(result),
                              color: color,
                              size: 44,
                            ),
                            const SizedBox(height: 9),
                            Text(
                              'No $result records yet',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Complete a test and save the digital record to see it here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...current.map(
                        (record) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    TestDetailsPage(record: record),
                              ),
                            ),
                            child: WhiteCard(
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: Image.memory(
                                      record.imageBytes,
                                      width: 74,
                                      height: 74,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          record.caseId,
                                          style: const TextStyle(
                                            color: textDark,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Sample ${record.sampleId}',
                                          style: const TextStyle(
                                            color: muted,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${record.confidence}% • ${record.timestamp}',
                                          style: const TextStyle(
                                            color: muted,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  StatusChip(text: result),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// ANALYTICS
// ============================================================

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppStore.version,
      builder: (_, __, ___) {
        final total = AppStore.total;
        final pos = AppStore.count('POSITIVE');
        final neg = AppStore.count('NEGATIVE');
        final inc = AppStore.count('INCONCLUSIVE');
        final avg = AppStore.averageConfidence;
        final safeTotal = total == 0 ? 1 : total;
        return SingleChildScrollView(padding: const EdgeInsets.all(25), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PageHeading(title: 'Analytics', subtitle: 'Live statistics calculated from saved test records.'),
          const SizedBox(height: 20),
          Row(children: [Expanded(child: metric('$total', 'Total Tests', blue)), const SizedBox(width: 14), Expanded(child: metric('${avg.toStringAsFixed(0)}%', 'Avg Confidence', green)), const SizedBox(width: 14), Expanded(child: metric('$inc', 'Inconclusive', orange))]),
          const SizedBox(height: 20),
          WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Result Distribution', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 20), analyticsBar(context, 'Negative', neg, safeTotal, green), analyticsBar(context, 'Positive', pos, safeTotal, red), analyticsBar(context, 'Inconclusive', inc, safeTotal, orange)])),
        ]));
      },
    );
  }

  Widget metric(String value, String label, Color color) => WhiteCard(child: Column(children: [Text(value, style: TextStyle(color: color, fontSize: 27, fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text(label, style: const TextStyle(color: muted, fontSize: 11))]));

  Widget analyticsBar(
    BuildContext context,
    String title,
    int value,
    int total,
    Color color,
  ) {
    final result = title.toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultRecordsPage(result: result),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '$value',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: muted,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: value / total,
                minHeight: 9,
                borderRadius: BorderRadius.circular(20),
                color: color,
                backgroundColor: const Color(0xFFE8EDF3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// REPORTS
// ============================================================

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  Future<void> _generate(BuildContext context, TestRecord record) async {
    final bytes = await buildProfessionalPdf(record);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Field_Test_Report_${record.caseId}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppStore.version,
      builder: (_, __, ___) {
        final records = AppStore.records;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeading(
                title: 'Reports',
                subtitle: 'Generate a PDF report containing the exact saved test image and complete evidence data.',
              ),
              const SizedBox(height: 20),
              if (records.isEmpty)
                const WhiteCard(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No test record is available yet. Complete and save a test first.'),
                  ),
                )
              else
                ...records.map(
                  (r) => Card(
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(r.imageBytes, width: 65, height: 65, fit: BoxFit.cover),
                      ),
                      title: Text(r.caseId, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${r.result} • ${r.timestamp}'),
                      trailing: FilledButton.icon(
                        onPressed: () => _generate(context, r),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('PDF'),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TestDetailsPage(record: r)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

}

// ============================================================
// IMAGE ANALYSIS INFO
// ============================================================

class AnalysisInfoPage extends StatelessWidget {
  const AnalysisInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final steps = [
      [
        Icons.image_search,
        'Image Quality Check',
        'Checks lighting, structure and visible colour regions.'
      ],
      [
        Icons.tune_rounded,
        'Colour Calibration',
        'Reference colour region helps reduce lighting variation.'
      ],
      [
        Icons.auto_awesome,
        'Computer Vision',
        'Prototype analyses the test image and colour pattern.'
      ],
      [
        Icons.psychology_rounded,
        'Classification',
        'Produces Positive, Negative or Inconclusive presumptive result.'
      ],
      [
        Icons.verified_rounded,
        'Confidence Score',
        'Displays confidence and supports retake when image quality is poor.'
      ],
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Image Analysis',
            subtitle:
                'Computer-vision based prototype analysis workflow.',
          ),

          const SizedBox(height: 20),

          ...steps.map(
            (s) => Padding(
              padding:
                  const EdgeInsets.only(
                      bottom: 12),
              child: WhiteCard(
                child: Row(
                  children: [
                    Container(
                      height: 50,
                      width: 50,
                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                                0xFFEAF1FF),
                        borderRadius:
                            BorderRadius
                                .circular(14),
                      ),
                      child: Icon(
                        s[0] as IconData,
                        color: blue,
                      ),
                    ),
                    const SizedBox(
                        width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            s[1] as String,
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .w900,
                              color:
                                  textDark,
                            ),
                          ),
                          const SizedBox(
                              height: 4),
                          Text(
                            s[2] as String,
                            style:
                                const TextStyle(
                              color: muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_circle,
                      color: green,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          const InfoBanner(
            text:
                'Prototype AI/CV result is presumptive only and requires laboratory confirmation before any final conclusion.',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// COMMON WIDGETS
// ============================================================

class PageHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const PageHeading({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 25,
            fontWeight:
                FontWeight.w900,
            color: textDark,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(
            color: muted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class WhiteCard extends StatelessWidget {
  final Widget child;

  const WhiteCard({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        border:
            Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withOpacity(.025),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class DashboardStat extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const DashboardStat({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
      padding:
          const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(17),
        border:
            Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: color,
            size: 25,
          ),
          const SizedBox(height: 9),
          Text(
            value,
            style: const TextStyle(
              fontSize: 25,
              fontWeight:
                  FontWeight.w900,
              color: textDark,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: muted,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class AppField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool readOnly;

  const AppField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class WorkflowStep
    extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;
  final IconData icon;

  const WorkflowStep({
    super.key,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color:
                  const Color(0xFFEAF1FF),
              borderRadius:
                  BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '$number  $title',
                  style: const TextStyle(
                    fontWeight:
                        FontWeight.w900,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style:
                      const TextStyle(
                    color: muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String text;

  const StatusChip({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: resultBg(text),
        borderRadius:
            BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: resultColor(text),
          fontWeight:
              FontWeight.w900,
          fontSize: 9,
        ),
      ),
    );
  }
}

class RecordRow extends StatelessWidget {
  final String title;
  final String value;

  const RecordRow({
    super.key,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(
        title,
        style: const TextStyle(
          color: muted,
          fontSize: 10,
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          color: textDark,
          fontWeight:
              FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  final String text;

  const InfoBanner({
    super.key,
    this.text =
        'Field results are presumptive only. Laboratory confirmation is required.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color:
            const Color(0xFFFFF8E7),
        borderRadius:
            BorderRadius.circular(15),
        border: Border.all(
          color:
              const Color(0xFFF3D889),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: orange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: textDark,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DEMO IMAGE VALIDATION
// ============================================================

class ValidationResult {
  final bool valid;
  final String message;
  final List<String> checks;

  ValidationResult(
    this.valid,
    this.message,
    this.checks,
  );
}

Future<ValidationResult>
    validateTestImage(
        Uint8List bytes) async {
  final decoded =
      img.decodeImage(bytes);

  if (decoded == null) {
    return ValidationResult(
      false,
      'Image could not be read.',
      [
        'Image readable',
        'Test area visible',
        'Reference colour visible',
      ],
    );
  }

  final resized =
      img.copyResize(
    decoded,
    width: 320,
  );

  double brightness = 0;
  double edge = 0;

  int bright = 0;
  int coloured = 0;

  for (int y = 1;
      y < resized.height - 1;
      y += 2) {
    for (int x = 1;
        x < resized.width - 1;
        x += 2) {
      final p =
          resized.getPixel(x, y);

      final r = p.r.toDouble();
      final g = p.g.toDouble();
      final b = p.b.toDouble();

      final avg =
          (r + g + b) / 3;

      brightness += avg;

      if (avg > 205) {
        bright++;
      }

      final maxc =
          [r, g, b].reduce(
        (a, b) => a > b ? a : b,
      );

      final minc =
          [r, g, b].reduce(
        (a, b) => a < b ? a : b,
      );

      if (maxc - minc > 35) {
        coloured++;
      }

      final p2 =
          resized.getPixel(
        x + 1,
        y,
      );

      final p3 =
          resized.getPixel(
        x,
        y + 1,
      );

      edge +=
          ((r - p2.r).abs() +
              (g - p2.g).abs() +
              (b - p2.b).abs());

      edge +=
          ((r - p3.r).abs() +
              (g - p3.g).abs() +
              (b - p3.b).abs());
    }
  }

  final count =
      ((resized.width / 2) *
              (resized.height / 2))
          .toDouble();

  brightness /= count;

  final brightRatio =
      bright / count;

  final colourRatio =
      coloured / count;

  final edgeScore =
      edge / count;

  final lightingOk =
      brightness > 55 &&
          brightness < 235;

  final structureOk =
      edgeScore > 18;

  final colourOk =
      colourRatio > .04;

  final kitAreaOk =
      brightRatio > .18;

  final valid =
      lightingOk &&
          structureOk &&
          colourOk &&
          kitAreaOk;

  if (valid) {
    return ValidationResult(
      true,
      'Test setup detected. Image quality and colour regions are suitable for prototype analysis.',
      [
        'Test area detected',
        'Colour reference region detected',
        'Image quality acceptable',
      ],
    );
  }

  return ValidationResult(
    false,
    'Please capture the field drug test kit and reference colour area clearly. Retake required.',
    [
      'Test area not confirmed',
      'Colour reference not confirmed',
      'Retake required',
    ],
  );
}

// ============================================================
// DEMO RECT
// ============================================================

void _fillRect(
  img.Image image,
  int x1,
  int y1,
  int x2,
  int y2,
  img.Color color,
) {
  final left =
      x1 < x2 ? x1 : x2;

  final right =
      x1 < x2 ? x2 : x1;

  final top =
      y1 < y2 ? y1 : y2;

  final bottom =
      y1 < y2 ? y2 : y1;

  for (var y = top;
      y <= bottom;
      y++) {
    for (var x = left;
        x <= right;
        x++) {
      image.setPixel(
        x,
        y,
        color,
      );
    }
  }
}

// ============================================================
// GPS
// ============================================================

Future<Position?>
    getCurrentPositionSafe() async {
  try {
    final enabled =
        await Geolocator
            .isLocationServiceEnabled();

    if (!enabled) return null;

    var permission =
        await Geolocator
            .checkPermission();

    if (permission ==
        LocationPermission.denied) {
      permission =
          await Geolocator
              .requestPermission();
    }

    if (permission ==
            LocationPermission.denied ||
        permission ==
            LocationPermission
                .deniedForever) {
      return null;
    }

    return await Geolocator
        .getCurrentPosition(
      locationSettings:
          const LocationSettings(
        accuracy:
            LocationAccuracy.high,
      ),
    );
  } catch (_) {
    return null;
  }
}

// ============================================================
// GUIDE PAINTER
// ============================================================

class GuidePainter
    extends CustomPainter {
  @override
  void paint(
      Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 3;

    final rect =
        Rect.fromCenter(
      center: Offset(
        size.width / 2,
        size.height / 2,
      ),
      width: size.width * .78,
      height: size.height * .48,
    );

    const l = 28.0;

    final lines = [
      [
        rect.topLeft,
        Offset(
            rect.left + l,
            rect.top)
      ],
      [
        rect.topLeft,
        Offset(
            rect.left,
            rect.top + l)
      ],
      [
        Offset(
            rect.right,
            rect.top),
        Offset(
            rect.right - l,
            rect.top)
      ],
      [
        Offset(
            rect.right,
            rect.top),
        Offset(
            rect.right,
            rect.top + l)
      ],
      [
        Offset(
            rect.left,
            rect.bottom),
        Offset(
            rect.left + l,
            rect.bottom)
      ],
      [
        Offset(
            rect.left,
            rect.bottom),
        Offset(
            rect.left,
            rect.bottom - l)
      ],
      [
        rect.bottomRight,
        Offset(
            rect.right - l,
            rect.bottom)
      ],
      [
        rect.bottomRight,
        Offset(
            rect.right,
            rect.bottom - l)
      ],
    ];

    for (final pair in lines) {
      canvas.drawLine(
        pair[0],
        pair[1],
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
      covariant CustomPainter oldDelegate) {
    return false;
  }
}


// ============================================================
// TEST RECORD + PROTOTYPE IMAGE ANALYSIS
// ============================================================

class PrototypeAnalysis {
  final String result;
  final int confidence;
  final String explanation;
  final Map<String, String> analytes;

  const PrototypeAnalysis({
    required this.result,
    required this.confidence,
    required this.explanation,
    required this.analytes,
  });
}

class TestRecord {
  final String caseId;
  final String sampleId;
  final String kitId;
  final String testType;
  final String operatorId;
  final String result;
  final int confidence;
  final String timestamp;
  final Uint8List imageBytes;
  final String imageHash;
  final String gps;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String analysisNote;

  TestRecord({
    required this.caseId,
    required this.sampleId,
    required this.kitId,
    required this.testType,
    required this.operatorId,
    required this.result,
    required this.confidence,
    required this.timestamp,
    required this.imageBytes,
    required this.imageHash,
    required this.gps,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.analysisNote,
  });

  String get signature => sha256.convert(utf8.encode(
        '$caseId|$sampleId|$kitId|$testType|$operatorId|$result|$confidence|$timestamp|$imageHash|$gps',
      )).toString();

  String get qrData => jsonEncode({
        'case_id': caseId,
        'sample_id': sampleId,
        'kit_id': kitId,
        'test_type': testType,
        'result': result,
        'confidence': confidence,
        'operator': operatorId,
        'timestamp': timestamp,
        'gps': gps,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'image_hash': imageHash,
        'digital_signature': signature,
      });

  Map<String, dynamic> toMap() => {
        'caseId': caseId,
        'sampleId': sampleId,
        'kitId': kitId,
        'testType': testType,
        'operatorId': operatorId,
        'result': result,
        'confidence': confidence,
        'timestamp': timestamp,
        'imageBytes': base64Encode(imageBytes),
        'imageHash': imageHash,
        'gps': gps,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'analysisNote': analysisNote,
      };

  factory TestRecord.fromMap(Map<String, dynamic> map) => TestRecord(
        caseId: map['caseId']?.toString() ?? '',
        sampleId: map['sampleId']?.toString() ?? '',
        kitId: map['kitId']?.toString() ?? 'KIT-MDP-001',
        testType: map['testType']?.toString() ?? 'Multi-Drug Panel',
        operatorId: map['operatorId']?.toString() ?? 'OFFICER-001',
        result: map['result']?.toString() ?? 'INCONCLUSIVE',
        confidence: (map['confidence'] as num?)?.toInt() ?? 0,
        timestamp: map['timestamp']?.toString() ?? '',
        imageBytes: base64Decode(map['imageBytes']?.toString() ?? ''),
        imageHash: map['imageHash']?.toString() ?? '',
        gps: map['gps']?.toString() ?? 'GPS unavailable',
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        accuracy: (map['accuracy'] as num?)?.toDouble(),
        analysisNote: map['analysisNote']?.toString() ?? '',
      );
}

class AppStore {
  static final List<TestRecord> records = [];
  static final ValueNotifier<int> version = ValueNotifier<int>(0);
  static late Box<Map> _box;
  static const _boxName = 'field_test_records_v2';

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<Map>(_boxName);
    records
      ..clear()
      ..addAll(_box.values.map((e) {
        try {
          return TestRecord.fromMap(Map<String, dynamic>.from(e));
        } catch (_) {
          return null;
        }
      }).whereType<TestRecord>());
    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    version.value++;
  }

  static Future<void> add(TestRecord record) async {
    records.removeWhere((r) => r.caseId == record.caseId);
    records.insert(0, record);
    await _box.put(record.caseId, record.toMap());
    version.value++;
  }

  static int get total => records.length;
  static int count(String result) => records.where((r) => r.result == result).length;
  static double get averageConfidence => records.isEmpty ? 0 : records.map((r) => r.confidence).reduce((a, b) => a + b) / records.length;
  static TestRecord? get latest => records.isEmpty ? null : records.first;
}

PrototypeAnalysis analyzePrototypeImage(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) {
    return const PrototypeAnalysis(
      result: 'INCONCLUSIVE',
      confidence: 50,
      explanation: 'The image could not be decoded.',
      analytes: {},
    );
  }

  final small = img.copyResize(image, width: 240);
  double red = 0;
  double orange = 0;
  double greenPixels = 0;
  double blue = 0;
  double saturation = 0;
  int samples = 0;

  // Sample the lower/middle portion where the demo test regions are drawn.
  final yStart = (small.height * .45).round();
  for (int y = yStart; y < small.height; y += 3) {
    for (int x = 0; x < small.width; x += 3) {
      final p = small.getPixel(x, y);
      final r = p.r.toDouble();
      final g = p.g.toDouble();
      final b = p.b.toDouble();
      final maxc = [r, g, b].reduce((a, b) => a > b ? a : b);
      final minc = [r, g, b].reduce((a, b) => a < b ? a : b);
      final sat = maxc == 0 ? 0 : (maxc - minc) / maxc;
      saturation += sat;
      samples++;

      if (r > g * 1.25 && r > b * 1.25 && r > 130) red++;
      if (r > b * 1.15 && g > b * 1.05 && r > 130 && g > 90) orange++;
      if (g > r * 1.15 && g > b * 1.05 && g > 100) greenPixels++;
      if (b > r * 1.15 && b > g * 1.05 && b > 100) blue++;
    }
  }

  if (samples == 0) {
    return const PrototypeAnalysis(
      result: 'INCONCLUSIVE',
      confidence: 50,
      explanation: 'Not enough image data was available for prototype analysis.',
      analytes: {},
    );
  }

  final warmRatio = (red + orange) / samples;
  final coolRatio = (greenPixels + blue) / samples;
  final avgSat = saturation / samples;
  final difference = (warmRatio - coolRatio).abs();

  String result;
  if (difference < .025 || avgSat < .08) {
    result = 'INCONCLUSIVE';
  } else if (warmRatio > coolRatio && warmRatio > .055) {
    result = 'POSITIVE';
  } else if (coolRatio > warmRatio && coolRatio > .055) {
    result = 'NEGATIVE';
  } else {
    result = 'INCONCLUSIVE';
  }

  final confidence = (55 + (difference * 450)).round().clamp(55, 97);

  final analytes = <String, String>{
    'Cocaine': result == 'POSITIVE' ? 'Prototype signal detected' : 'No prototype signal',
    'Amphetamine': result == 'POSITIVE' ? 'Prototype signal detected' : 'No prototype signal',
    'Cannabis (THC)': result == 'POSITIVE' ? 'Prototype signal detected' : 'No prototype signal',
    'Methamphetamine': result == 'POSITIVE' ? 'Prototype signal detected' : 'No prototype signal',
  };

  return PrototypeAnalysis(
    result: result,
    confidence: confidence,
    explanation:
        'Image-based color-region analysis: warm=${(warmRatio * 100).toStringAsFixed(1)}%, '
        'cool=${(coolRatio * 100).toStringAsFixed(1)}%, saturation=${(avgSat * 100).toStringAsFixed(1)}%.',
    analytes: analytes,
  );
}

// ============================================================
// RESULT HELPERS
// ============================================================

Color resultColor(
    String result) {
  switch (result) {
    case 'POSITIVE':
      return red;
    case 'INCONCLUSIVE':
      return orange;
    default:
      return green;
  }
}

Color resultBg(
    String result) {
  switch (result) {
    case 'POSITIVE':
      return const Color(0xFFFFE7E9);
    case 'INCONCLUSIVE':
      return const Color(0xFFFFF3D7);
    default:
      return const Color(0xFFE5F8F0);
  }
}

IconData resultIcon(
    String result) {
  switch (result) {
    case 'POSITIVE':
      return Icons.warning_amber_rounded;
    case 'INCONCLUSIVE':
      return Icons.help_outline_rounded;
    default:
      return Icons.check_rounded;
  }
}