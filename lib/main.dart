import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

const emerald = Color(0xFF126B50);
const gold = Color(0xFFD7B46A);

const apiBase = 'https://api.alquran.cloud/v1';
const audioBase =
    'https://cdn.islamic.network/quran/audio-surah/128/ar.alafasy';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // لا نسمح لفشل تهيئة الصوت بمنع ظهور التطبيق.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.noor_quran.audio',
      androidNotificationChannelName: 'تلاوات القرآن الكريم',
      androidNotificationOngoing: true,
    ).timeout(const Duration(seconds: 8));
  } catch (error) {
    debugPrint('خطأ تهيئة الصوت في الخلفية: $error');
  }

  try {
    final session = await AudioSession.instance.timeout(
      const Duration(seconds: 5),
    );

    await session
        .configure(const AudioSessionConfiguration.speech())
        .timeout(const Duration(seconds: 5));
  } catch (error) {
    debugPrint('خطأ إعداد جلسة الصوت: $error');
  }

  runApp(const NoorQuranApp());
}

// ============================================================
// نماذج البيانات
// ============================================================

class Surah {
  final int number;
  final String name;
  final int verses;
  final String type;

  const Surah({
    required this.number,
    required this.name,
    required this.verses,
    required this.type,
  });

  factory Surah.fromJson(Map<String, dynamic> json) {
    return Surah(
      number: (json['number'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? 'سورة',
      verses: (json['numberOfAyahs'] as num?)?.toInt() ?? 0,
      type: json['revelationType'] == 'Medinan' ? 'مدنية' : 'مكية',
    );
  }
}

class Ayah {
  final int numberInSurah;
  final String text;

  const Ayah(this.numberInSurah, this.text);

  factory Ayah.fromJson(Map<String, dynamic> json) {
    return Ayah(
      (json['numberInSurah'] as num?)?.toInt() ?? 0,
      json['text']?.toString() ?? '',
    );
  }
}

// ============================================================
// واجهة الاتصال بخدمة القرآن
// ============================================================

class QuranApi {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: apiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
    ),
  );

  static Future<List<Surah>> surahs() async {
    final response = await _dio.get('/surah');
    final data = response.data['data'] as List<dynamic>;

    return data
        .whereType<Map<String, dynamic>>()
        .map(Surah.fromJson)
        .toList();
  }

  static Future<List<Ayah>> ayahs(int number) async {
    final response = await _dio.get('/surah/$number/quran-uthmani');
    final data = response.data['data'] as Map<String, dynamic>;
    final list = data['ayahs'] as List<dynamic>;

    return list
        .whereType<Map<String, dynamic>>()
        .map(Ayah.fromJson)
        .toList();
  }
}

// ============================================================
// التطبيق الرئيسي
// ============================================================

class NoorQuranApp extends StatefulWidget {
  const NoorQuranApp({super.key});

  @override
  State<NoorQuranApp> createState() => _NoorQuranAppState();
}

class _NoorQuranAppState extends State<NoorQuranApp> {
  int tab = 0;
  bool dark = false;
  bool loading = true;
  bool overlayBusy = false;

  int tasbih = 0;
  int pages = 0;

  String? loadError;
  Surah? currentSurah;

  final Set<int> favorites = {};
  final List<Surah> surahs = [];
  final AudioPlayer player = AudioPlayer();
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadSurahs();
  }

  // تحميل الإعدادات دون تعطيل واجهة التطبيق عند حدوث خطأ.
  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      setState(() {
        dark = prefs.getBool('dark') ?? false;
        tasbih = prefs.getInt('tasbih') ?? 0;
        pages = prefs.getInt('pages') ?? 0;

        favorites
          ..clear()
          ..addAll(
            (prefs.getStringList('favorites') ?? [])
                .map((value) => int.tryParse(value))
                .whereType<int>(),
          );
      });
    } catch (error) {
      debugPrint('تعذر تحميل الإعدادات: $error');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('dark', dark);
      await prefs.setInt('tasbih', tasbih);
      await prefs.setInt('pages', pages);
      await prefs.setStringList(
        'favorites',
        favorites.map((value) => value.toString()).toList(),
      );
    } catch (error) {
      debugPrint('تعذر حفظ الإعدادات: $error');
    }
  }

  Future<void> _loadSurahs() async {
    if (mounted) {
      setState(() {
        loading = true;
        loadError = null;
      });
    }

    try {
      final result = await QuranApi.surahs().timeout(
        const Duration(seconds: 25),
      );

      if (!mounted) return;

      setState(() {
        surahs
          ..clear()
          ..addAll(result);
        loading = false;
        loadError = null;
      });
    } catch (error) {
      debugPrint('تعذر تحميل السور: $error');

      if (!mounted) return;

      setState(() {
        loading = false;
        loadError = 'تعذّر تحميل فهرس القرآن. تحقق من الإنترنت وحاول مجددًا.';
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    player.dispose();
    super.dispose();
  }

  // ==========================================================
  // تشغيل التلاوة
  // ==========================================================

  Future<void> playSurah(Surah surah) async {
    try {
      setState(() => currentSurah = surah);

      await player.setAudioSource(
        AudioSource.uri(
          Uri.parse('$audioBase/${surah.number}.mp3'),
          tag: MediaItem(
            id: '${surah.number}',
            title: surah.name,
            album: 'القرآن الكريم',
            artist: 'مشاري العفاسي',
          ),
        ),
      );

      await player.play();
    } catch (error) {
      debugPrint('تعذر تشغيل التلاوة: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تشغيل التلاوة. تحقق من الإنترنت وحاول مجددًا.'),
        ),
      );
    }
  }

  // ==========================================================
  // النافذة العائمة للأذكار
  // ==========================================================

  Future<void> toggleOverlay() async {
    if (overlayBusy) return;

    setState(() => overlayBusy = true);

    try {
      bool? allowed =
          await FlutterOverlayWindow.isPermissionGranted();

      if (allowed != true) {
        allowed = await FlutterOverlayWindow.requestPermission();
      }

      if (allowed == true) {
        await FlutterOverlayWindow.showOverlay(
          height: 180,
          width: 280,
          alignment: OverlayAlignment.centerRight,
          visibility: NotificationVisibility.visibilityPublic,
          flag: OverlayFlag.defaultFlag,
          enableDrag: true,
          overlayTitle: 'نور القرآن',
          overlayContent: 'ذكر الله',
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى السماح بالظهور فوق التطبيقات الأخرى.'),
          ),
        );
      }
    } on PlatformException catch (error) {
      debugPrint('خطأ النافذة العائمة: $error');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر تشغيل النافذة العائمة على هذا الجهاز.'),
          ),
        );
      }
    } catch (error) {
      debugPrint('خطأ غير متوقع في النافذة العائمة: $error');
    } finally {
      if (mounted) {
        setState(() => overlayBusy = false);
      }
    }
  }

  // ==========================================================
  // التصميم والثيم
  // ==========================================================

  ThemeData get theme => ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: emerald,
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        scaffoldBackgroundColor:
            dark ? const Color(0xFF101A18) : const Color(0xFFF5F7F2),
        appBarTheme: const AppBarTheme(centerTitle: false),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نور القرآن',
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: tab,
            children: [
              _home(),
              _quran(),
              _favoritesPage(),
              _more(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) {
            setState(() => tab = value);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'المصحف',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline),
              selectedIcon: Icon(Icons.favorite),
              label: 'المفضلة',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_rounded),
              label: 'المزيد',
            ),
          ],
        ),
        floatingActionButton: currentSurah == null
            ? null
            : FloatingActionButton.small(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                onPressed: () => _showPlayer(context),
                child: const Icon(Icons.graphic_eq),
              ),
      ),
    );
  }

  Widget _heading(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // الرئيسية
  // ==========================================================

  Widget _home() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _heading('نور القرآن', 'رفيقك اليومي لكتاب الله'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [Color(0xFF0D5943), Color(0xFF238568)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, color: gold, size: 32),
                const SizedBox(height: 14),
                const Text(
                  'وَلَقَدْ يَسَّرْنَا الْقُرْآنَ لِلذِّكْرِ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'فَهَلْ مِن مُّدَّكِرٍ',
                  style: TextStyle(color: gold, fontSize: 19),
                ),
                const SizedBox(height: 6),
                const Text(
                  'سورة القمر · آية 17',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: Colors.black87,
                  ),
                  onPressed: () => setState(() => tab = 1),
                  child: const Text('افتح المصحف'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: _stat(Icons.menu_book, '$pages / 604', 'صفحة الختمة')),
              const SizedBox(width: 10),
              Expanded(child: _stat(Icons.favorite, '${favorites.length}', 'سور مفضلة')),
              const SizedBox(width: 10),
              Expanded(child: _stat(Icons.fingerprint, '$tasbih', 'تسبيحة')),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'أدواتك اليومية',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              _tool(
                Icons.fingerprint,
                'المسبحة',
                'عداد محفوظ',
                _tasbihDialog,
              ),
              _tool(
                Icons.track_changes,
                'ختمة القرآن',
                'تقدم القراءة',
                _khatmaDialog,
              ),
              _tool(
                Icons.layers_outlined,
                'ذكر عائم',
                'يظهر فوق التطبيقات',
                toggleOverlay,
              ),
              _tool(
                Icons.nights_stay_outlined,
                'الوضع الليلي',
                'تبديل المظهر',
                () async {
                  setState(() => dark = !dark);
                  await _save();
                },
              ),
            ],
          ),
        ),
        if (currentSurah != null) _miniPlayer(),
      ],
    );
  }

  Widget _stat(IconData icon, String value, String label) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: emerald),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _tool(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: emerald, size: 29),
              const SizedBox(height: 9),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(subtitle, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // فهرس القرآن
  // ==========================================================

  Widget _quran() {
    final query = searchController.text.trim();

    final filtered = surahs.where((surah) {
      return surah.name.contains(query) ||
          surah.number.toString() == query;
    }).toList();

    return Column(
      children: [
        _heading('المصحف الشريف', 'اختر سورة للقراءة أو الاستماع'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'ابحث عن سورة أو رقمها',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : loadError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 48),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              loadError!,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          FilledButton(
                            onPressed: _loadSurahs,
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final surah = filtered[index];
                        final isFavorite =
                            favorites.contains(surah.number);

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: emerald.withValues(alpha: 0.12),
                              child: Text(
                                '${surah.number}',
                                style: const TextStyle(
                                  color: emerald,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              surah.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${surah.type} · ${surah.verses} آية',
                            ),
                            trailing: Wrap(
                              spacing: 0,
                              children: [
                                IconButton(
                                  tooltip: 'استماع',
                                  onPressed: () => playSurah(surah),
                                  icon: const Icon(Icons.play_circle_outline),
                                ),
                                IconButton(
                                  tooltip: 'المفضلة',
                                  onPressed: () async {
                                    setState(() {
                                      if (isFavorite) {
                                        favorites.remove(surah.number);
                                      } else {
                                        favorites.add(surah.number);
                                      }
                                    });
                                    await _save();
                                  },
                                  icon: Icon(
                                    isFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: isFavorite ? Colors.red : null,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReaderScreen(
                                    surah: surah,
                                    onPlay: () => playSurah(surah),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ==========================================================
  // المفضلة
  // ==========================================================

  Widget _favoritesPage() {
    final list = surahs
        .where((surah) => favorites.contains(surah.number))
        .toList();

    return Column(
      children: [
        _heading('السور المفضلة', 'سورك المحفوظة للوصول السريع'),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('لا توجد سور مفضلة بعد'))
              : ListView(
                  children: list.map((surah) {
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: ListTile(
                        title: Text(surah.name),
                        subtitle: Text('${surah.verses} آية'),
                        trailing: IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () => playSurah(surah),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReaderScreen(
                                surah: surah,
                                onPlay: () => playSurah(surah),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  // ==========================================================
  // المزيد والإعدادات
  // ==========================================================

  Widget _more() {
    return ListView(
      children: [
        _heading('المزيد', 'إعدادات وأدوات نور القرآن'),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined, color: emerald),
            title: const Text('الوضع الليلي'),
            value: dark,
            onChanged: (value) async {
              setState(() => dark = value);
              await _save();
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.layers, color: emerald),
            title: const Text('تشغيل الذكر العائم'),
            subtitle: const Text('يحتاج إذن الظهور فوق التطبيقات'),
            trailing: const Icon(Icons.chevron_left),
            onTap: toggleOverlay,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.fingerprint, color: emerald),
            title: const Text('المسبحة الإلكترونية'),
            onTap: _tasbihDialog,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.track_changes, color: emerald),
            title: const Text('خطة ختم القرآن'),
            onTap: _khatmaDialog,
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline, color: emerald),
            title: Text('مصدر القرآن'),
            subtitle: Text('AlQuran Cloud API — يتطلب اتصال إنترنت'),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // المسبحة الإلكترونية
  // ==========================================================

  void _tasbihDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialog) {
            return AlertDialog(
              title: const Text('المسبحة الإلكترونية'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'سُبْحَانَ اللَّهِ',
                    style: TextStyle(fontSize: 24, color: emerald),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$tasbih',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      setState(() => tasbih++);
                      updateDialog(() {});
                      await _save();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('تسبيحة'),
                  ),
                  TextButton(
                    onPressed: () async {
                      setState(() => tasbih = 0);
                      updateDialog(() {});
                      await _save();
                    },
                    child: const Text('تصفير العداد'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إغلاق'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================================
  // خطة الختمة
  // ==========================================================

  void _khatmaDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialog) {
            return AlertDialog(
              title: const Text('خطة ختم القرآن'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$pages من 604 صفحة',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  LinearProgressIndicator(value: pages / 604),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: pages > 0
                            ? () async {
                                setState(() => pages--);
                                updateDialog(() {});
                                await _save();
                              }
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        onPressed: pages < 604
                            ? () async {
                                setState(() => pages++);
                                updateDialog(() {});
                                await _save();
                              }
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  Text(
                    '${(pages / 604 * 100).toStringAsFixed(1)}% مكتمل',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إغلاق'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================================
  // مشغل مصغر
  // ==========================================================

  Widget _miniPlayer() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: ListTile(
        leading: const Icon(Icons.graphic_eq, color: emerald),
        title: Text(currentSurah!.name),
        subtitle: const Text('مشغل التلاوة'),
        trailing: IconButton(
          onPressed: () async {
            try {
              if (player.playing) {
                await player.pause();
              } else {
                await player.play();
              }
            } catch (error) {
              debugPrint('خطأ المشغل: $error');
            }
          },
          icon: StreamBuilder<PlayerState>(
            stream: player.playerStateStream,
            builder: (_, snapshot) {
              return Icon(
                snapshot.data?.playing == true
                    ? Icons.pause_circle
                    : Icons.play_circle,
                size: 34,
              );
            },
          ),
        ),
        onTap: () => _showPlayer(context),
      ),
    );
  }

  void _showPlayer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: StreamBuilder<PlayerState>(
              stream: player.playerStateStream,
              builder: (context, snapshot) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.menu_book, color: emerald, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      currentSurah?.name ?? 'التلاوة',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('مشاري العفاسي · بث عبر الإنترنت'),
                    StreamBuilder<Duration?>(
                      stream: player.durationStream,
                      builder: (_, durationSnapshot) {
                        return StreamBuilder<Duration>(
                          stream: player.positionStream,
                          builder: (_, positionSnapshot) {
                            final total =
                                durationSnapshot.data ?? Duration.zero;
                            final position =
                                positionSnapshot.data ?? Duration.zero;

                            final maxValue = total.inMilliseconds > 0
                                ? total.inMilliseconds.toDouble()
                                : 1.0;

                            final value = position.inMilliseconds
                                .clamp(0, total.inMilliseconds > 0
                                    ? total.inMilliseconds
                                    : 0)
                                .toDouble();

                            return Column(
                              children: [
                                Slider(
                                  value: value.clamp(0.0, maxValue),
                                  max: maxValue,
                                  onChanged: total.inMilliseconds > 0
                                      ? (newValue) {
                                          player.seek(
                                            Duration(
                                              milliseconds: newValue.round(),
                                            ),
                                          );
                                        }
                                      : null,
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_fmt(position)),
                                    Text(_fmt(total)),
                                  ],
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () => player.seek(Duration.zero),
                          icon: const Icon(Icons.replay),
                        ),
                        IconButton.filled(
                          onPressed: () async {
                            try {
                              if (player.playing) {
                                await player.pause();
                              } else {
                                await player.play();
                              }
                            } catch (error) {
                              debugPrint('خطأ تشغيل الصوت: $error');
                            }
                          },
                          icon: Icon(
                            snapshot.data?.playing == true
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ),
                        IconButton(
                          onPressed: () => player.stop(),
                          icon: const Icon(Icons.stop),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _fmt(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

// ============================================================
// شاشة قراءة السورة
// ============================================================

class ReaderScreen extends StatefulWidget {
  final Surah surah;
  final VoidCallback onPlay;

  const ReaderScreen({
    super.key,
    required this.surah,
    required this.onPlay,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late Future<List<Ayah>> future;
  double fontSize = 27;

  @override
  void initState() {
    super.initState();
    future = QuranApi.ayahs(widget.surah.number);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.surah.name),
        actions: [
          IconButton(
            tooltip: 'تصغير الخط',
            onPressed: () {
              setState(() {
                fontSize = (fontSize - 2).clamp(18.0, 42.0).toDouble();
              });
            },
            icon: const Icon(Icons.text_decrease),
          ),
          IconButton(
            tooltip: 'تكبير الخط',
            onPressed: () {
              setState(() {
                fontSize = (fontSize + 2).clamp(18.0, 42.0).toDouble();
              });
            },
            icon: const Icon(Icons.text_increase),
          ),
          IconButton(
            tooltip: 'استماع للسورة',
            onPressed: widget.onPlay,
            icon: const Icon(Icons.play_circle_outline),
          ),
        ],
      ),
      body: FutureBuilder<List<Ayah>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('تعذر تحميل الآيات. تحقق من اتصال الإنترنت.'),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        future = QuranApi.ayahs(widget.surah.number);
                      });
                    },
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }

          final ayahs = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D5943), Color(0xFF238568)],
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      widget.surah.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${widget.surah.type} · ${widget.surah.verses} آية',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              if (widget.surah.number != 1 && widget.surah.number != 9)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 22),
                  child: Text(
                    'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 25, color: emerald),
                  ),
                ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    ayahs
                        .map((ayah) =>
                            '${ayah.text} ﴿${ayah.numberInSurah}﴾')
                        .join('  '),
                    textAlign: TextAlign.justify,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: 2.15,
                      fontFamily: 'serif',
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'النص محمّل من AlQuran Cloud. يُستحسن مراجعة المصدر قبل اعتماد أي طبعة خاصة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// نقطة تشغيل النافذة العائمة
// ============================================================

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DhikrOverlay(),
    ),
  );
}

class DhikrOverlay extends StatefulWidget {
  const DhikrOverlay({super.key});

  @override
  State<DhikrOverlay> createState() => _DhikrOverlayState();
}

class _DhikrOverlayState extends State<DhikrOverlay> {
  int count = 0;
  int selected = 0;

  final List<String> adhkar = const [
    'سُبْحَانَ اللَّهِ',
    'الْحَمْدُ لِلَّهِ',
    'اللَّهُ أَكْبَرُ',
    'أَسْتَغْفِرُ اللَّهَ',
    'لَا إِلَهَ إِلَّا اللَّهُ',
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xF2122B24),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gold, width: 1.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: gold, size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'نور القرآن',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => FlutterOverlayWindow.closeOverlay(),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => count++),
              onLongPress: () {
                setState(() {
                  count = 0;
                  selected = (selected + 1) % adhkar.length;
                });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      adhkar[selected],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'عدد التسبيحات: $count',
                      style: const TextStyle(color: gold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'اضغط للعد · ضغط مطوّل لتغيير الذكر',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}