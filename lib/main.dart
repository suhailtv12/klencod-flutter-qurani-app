import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

const Color emerald = Color(0xFF126B50);
const Color gold = Color(0xFFD7B46A);

const String apiBase = 'https://api.alquran.cloud/v1';
const String audioBase =
    'https://cdn.islamic.network/quran/audio-surah/128/ar.alafasy';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.noor_quran.audio',
    androidNotificationChannelName: 'تلاوات القرآن الكريم',
    androidNotificationOngoing: true,
  );

  final session = await AudioSession.instance;
  await session.configure(
    const AudioSessionConfiguration.speech(),
  );

  runApp(const NoorQuranApp());
}

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
      number: json['number'] as int,
      name: json['name'] as String? ?? 'سورة',
      verses: json['numberOfAyahs'] as int? ?? 0,
      type: json['revelationType'] == 'Medinan'
          ? 'مدنية'
          : 'مكية',
    );
  }
}

class Ayah {
  final int numberInSurah;
  final String text;

  const Ayah({
    required this.numberInSurah,
    required this.text,
  });

  factory Ayah.fromJson(Map<String, dynamic> json) {
    return Ayah(
      numberInSurah: json['numberInSurah'] as int? ?? 0,
      text: json['text'] as String? ?? '',
    );
  }
}

class QuranApi {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: apiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  static Future<List<Surah>> getSurahs() async {
    final response = await _dio.get('/surah');
    final data = response.data['data'] as List;

    return data
        .map((item) => Surah.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  static Future<List<Ayah>> getAyahs(int surahNumber) async {
    final response =
        await _dio.get('/surah/$surahNumber/quran-uthmani');

    final data =
        response.data['data'] as Map<String, dynamic>;
    final list = data['ayahs'] as List;

    return list
        .map((item) => Ayah.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }
}

class NoorQuranApp extends StatefulWidget {
  const NoorQuranApp({super.key});

  @override
  State<NoorQuranApp> createState() => _NoorQuranAppState();
}

class _NoorQuranAppState extends State<NoorQuranApp> {
  int selectedTab = 0;
  bool darkMode = false;
  int tasbihCount = 0;
  int khatmaPages = 0;

  final Set<int> favorites = {};
  final AudioPlayer player = AudioPlayer();
  final TextEditingController searchController =
      TextEditingController();

  List<Surah> surahs = [];
  bool loading = true;
  String? errorMessage;
  Surah? currentSurah;
  bool overlayBusy = false;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _loadSurahs();
  }

  @override
  void dispose() {
    searchController.dispose();
    player.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      darkMode = prefs.getBool('darkMode') ?? false;
      tasbihCount = prefs.getInt('tasbihCount') ?? 0;
      khatmaPages =
          (prefs.getInt('khatmaPages') ?? 0).clamp(0, 604);

      favorites.addAll(
        (prefs.getStringList('favorites') ?? [])
            .map((value) => int.tryParse(value))
            .whereType<int>(),
      );
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('darkMode', darkMode);
    await prefs.setInt('tasbihCount', tasbihCount);
    await prefs.setInt('khatmaPages', khatmaPages);
    await prefs.setStringList(
      'favorites',
      favorites.map((number) => number.toString()).toList(),
    );
  }

  Future<void> _loadSurahs() async {
    try {
      final result = await QuranApi.getSurahs();

      if (!mounted) return;

      setState(() {
        surahs = result;
        loading = false;
        errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loading = false;
        errorMessage =
            'تعذّر تحميل القرآن. تحقق من اتصال الإنترنت وحاول مجددًا.';
      });
    }
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness:
          darkMode ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: emerald,
        brightness:
            darkMode ? Brightness.dark : Brightness.light,
      ),
      scaffoldBackgroundColor: darkMode
          ? const Color(0xFF101A18)
          : const Color(0xFFF5F7F2),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نور القرآن',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: selectedTab,
            children: [
              _homePage(),
              _quranPage(),
              _favoritesPage(),
              _morePage(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedTab,
          onDestinationSelected: (index) {
            setState(() => selectedTab = index);
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

  Widget _pageHeading(String title, String subtitle) {
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
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _homePage() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _pageHeading(
          'نور القرآن',
          'رفيقك اليومي لكتاب الله',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0D5943),
                  Color(0xFF238568),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: gold,
                  size: 32,
                ),
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
                  style: TextStyle(
                    color: gold,
                    fontSize: 19,
                  ),
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
                  onPressed: () {
                    setState(() => selectedTab = 1);
                  },
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
              Expanded(
                child: _statCard(
                  Icons.menu_book,
                  '$khatmaPages / 604',
                  'صفحة الختمة',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard(
                  Icons.favorite,
                  '${favorites.length}',
                  'سور مفضلة',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard(
                  Icons.fingerprint,
                  '$tasbihCount',
                  'تسبيحة',
                ),
              ),
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
            crossAxisCount:
                MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              _toolCard(
                Icons.fingerprint,
                'المسبحة',
                'عداد التسبيح',
                _showTasbih,
              ),
              _toolCard(
                Icons.track_changes,
                'ختمة القرآن',
                'متابعة الإنجاز',
                _showKhatma,
              ),
              _toolCard(
                Icons.layers_outlined,
                'الذكر العائم',
                'فوق التطبيقات',
                _toggleOverlay,
              ),
              _toolCard(
                Icons.nights_stay_outlined,
                'الوضع الليلي',
                'تغيير المظهر',
                () async {
                  setState(() => darkMode = !darkMode);
                  await _saveData();
                },
              ),
            ],
          ),
        ),
        if (currentSurah != null) _miniPlayer(),
      ],
    );
  }

  Widget _statCard(
    IconData icon,
    String value,
    String label,
  ) {
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
            Text(
              label,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolCard(
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quranPage() {
    final query = searchController.text.trim();

    final filtered = surahs.where((surah) {
      return surah.name.contains(query) ||
          surah.number.toString() == query;
    }).toList();

    return Column(
      children: [
        _pageHeading(
          'المصحف الشريف',
          'اختر سورة للقراءة أو الاستماع',
        ),
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
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cloud_off,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              errorMessage!,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () {
                                setState(() {
                                  loading = true;
                                  errorMessage = null;
                                });
                                _loadSurahs();
                              },
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
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
                              backgroundColor:
                                  emerald.withValues(alpha: 0.12),
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
                                  onPressed: () => _playSurah(surah),
                                  icon: const Icon(
                                    Icons.play_circle_outline,
                                  ),
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
                                    await _saveData();
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
                                    onPlay: () => _playSurah(surah),
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

  Widget _favoritesPage() {
    final saved = surahs
        .where((surah) => favorites.contains(surah.number))
        .toList();

    return Column(
      children: [
        _pageHeading(
          'السور المفضلة',
          'سورك المحفوظة للوصول السريع',
        ),
        Expanded(
          child: saved.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_border,
                        size: 58,
                        color: emerald,
                      ),
                      SizedBox(height: 12),
                      Text('لا توجد سور مفضلة بعد'),
                    ],
                  ),
                )
              : ListView(
                  children: saved.map((surah) {
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
                          onPressed: () => _playSurah(surah),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReaderScreen(
                                surah: surah,
                                onPlay: () => _playSurah(surah),
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

  Widget _morePage() {
    return ListView(
      children: [
        _pageHeading(
          'المزيد',
          'إعدادات وأدوات نور القرآن',
        ),
        Card(
          child: SwitchListTile(
            secondary: const Icon(
              Icons.dark_mode_outlined,
              color: emerald,
            ),
            title: const Text('الوضع الليلي'),
            value: darkMode,
            onChanged: (value) async {
              setState(() => darkMode = value);
              await _saveData();
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.layers, color: emerald),
            title: const Text('تشغيل الذكر العائم'),
            subtitle: const Text(
              'يتطلب إذن الظهور فوق التطبيقات',
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: _toggleOverlay,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.fingerprint,
              color: emerald,
            ),
            title: const Text('المسبحة الإلكترونية'),
            onTap: _showTasbih,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.track_changes,
              color: emerald,
            ),
            title: const Text('خطة ختم القرآن'),
            onTap: _showKhatma,
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline, color: emerald),
            title: Text('مصدر القرآن'),
            subtitle: Text('AlQuran Cloud API'),
          ),
        ),
      ],
    );
  }

  Future<void> _playSurah(Surah surah) async {
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
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذّر تشغيل التلاوة. تحقق من الاتصال أو جرّب لاحقًا.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleOverlay() async {
    if (overlayBusy) return;

    setState(() => overlayBusy = true);

    try {
      final allowed =
          await FlutterOverlayWindow.isPermissionGranted();

      if (allowed != true) {
        final granted =
            await FlutterOverlayWindow.requestPermission();

        if (granted != true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'يجب السماح بالظهور فوق التطبيقات من إعدادات أندرويد.',
                ),
              ),
            );
          }
          return;
        }
      }

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
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر تشغيل النافذة العائمة على هذا الجهاز.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذّر تشغيل النافذة. راجع إعدادات أندرويد والمكتبة.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => overlayBusy = false);
    }
  }

  void _showTasbih() {
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
                    style: TextStyle(
                      fontSize: 24,
                      color: emerald,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$tasbihCount',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      setState(() => tasbihCount++);
                      updateDialog(() {});
                      await _saveData();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('تسبيحة'),
                  ),
                  TextButton(
                    onPressed: () async {
                      setState(() => tasbihCount = 0);
                      updateDialog(() {});
                      await _saveData();
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

  void _showKhatma() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialog) {
            final progress = khatmaPages / 604;

            return AlertDialog(
              title: const Text('خطة ختم القرآن'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$khatmaPages من 604 صفحة',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 12),
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}% مكتمل',
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: khatmaPages > 0
                            ? () async {
                                setState(() => khatmaPages--);
                                updateDialog(() {});
                                await _saveData();
                              }
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        onPressed: khatmaPages < 604
                            ? () async {
                                setState(() => khatmaPages++);
                                updateDialog(() {});
                                await _saveData();
                              }
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
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

  Widget _miniPlayer() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: ListTile(
        leading: const Icon(
          Icons.graphic_eq,
          color: emerald,
        ),
        title: Text(currentSurah?.name ?? 'التلاوة'),
        subtitle: const Text('مشغل القرآن الكريم'),
        trailing: StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;

            return IconButton(
              onPressed: () {
                if (playing) {
                  player.pause();
                } else {
                  player.play();
                }
              },
              icon: Icon(
                playing
                    ? Icons.pause_circle
                    : Icons.play_circle,
                size: 34,
              ),
            );
          },
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
                final playing = snapshot.data?.playing ?? false;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.menu_book,
                      color: emerald,
                      size: 42,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentSurah?.name ?? 'التلاوة',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'القرآن الكريم · بث عبر الإنترنت',
                    ),
                    const SizedBox(height: 18),
                    StreamBuilder<Duration?>(
                      stream: player.durationStream,
                      builder: (context, durationSnapshot) {
                        final total =
                            durationSnapshot.data ?? Duration.zero;

                        return StreamBuilder<Duration>(
                          stream: player.positionStream,
                          builder: (context, positionSnapshot) {
                            final position =
                                positionSnapshot.data ?? Duration.zero;

                            final maxValue = total.inMilliseconds > 0
                                ? total.inMilliseconds.toDouble()
                                : 1.0;

                            final currentValue = position
                                .inMilliseconds
                                .clamp(0, maxValue.toInt())
                                .toDouble();

                            return Column(
                              children: [
                                Slider(
                                  value: currentValue,
                                  max: maxValue,
                                  onChanged: total.inMilliseconds > 0
                                      ? (value) {
                                          player.seek(
                                            Duration(
                                              milliseconds: value.round(),
                                            ),
                                          );
                                        }
                                      : null,
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDuration(position)),
                                    Text(_formatDuration(total)),
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
                          onPressed: () {
                            if (playing) {
                              player.pause();
                            } else {
                              player.play();
                            }
                          },
                          icon: Icon(
                            playing ? Icons.pause : Icons.play_arrow,
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

  String _formatDuration(Duration duration) {
    final minutes =
        duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }
}

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
    future = QuranApi.getAyahs(widget.surah.number);
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
                fontSize = (fontSize - 2).clamp(18, 42).toDouble();
              });
            },
            icon: const Icon(Icons.text_decrease),
          ),
          IconButton(
            tooltip: 'تكبير الخط',
            onPressed: () {
              setState(() {
                fontSize = (fontSize + 2).clamp(18, 42).toDouble();
              });
            },
            icon: const Icon(Icons.text_increase),
          ),
          IconButton(
            tooltip: 'استماع',
            onPressed: widget.onPlay,
            icon: const Icon(Icons.play_circle_outline),
          ),
        ],
      ),
      body: FutureBuilder<List<Ayah>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'تعذّر تحميل الآيات. تحقق من الإنترنت.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        future =
                            QuranApi.getAyahs(widget.surah.number);
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
                    colors: [
                      Color(0xFF0D5943),
                      Color(0xFF238568),
                    ],
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
                    const SizedBox(height: 6),
                    Text(
                      '${widget.surah.type} · ${widget.surah.verses} آية',
                      style: const TextStyle(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
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
                  'النص محمّل من AlQuran Cloud API بالرسم العثماني. '
                  'راجع المصدر المعتمد قبل نشر التطبيق.',
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
                const Icon(
                  Icons.auto_awesome,
                  color: gold,
                  size: 18,
                ),
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
                      style: const TextStyle(
                        color: gold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'اضغط للعد · ضغط مطوّل لتغيير الذكر',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 9,
                      ),
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