import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import 'screens/create_memory.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'screens/view_memory.dart';

class MemoryLanesPage extends StatefulWidget {
  final ApiService apiService;
  final String? e2eStatus;

  const MemoryLanesPage({super.key, required this.apiService, this.e2eStatus});

  @override
  State<MemoryLanesPage> createState() => _MemoryLanesPageState();
}

class _MemoryLanesPageState extends State<MemoryLanesPage>
    with TickerProviderStateMixin {
  int _currentStep = 1;
  late final AnimationController _introController;
  bool _showIntroAnimation = true;
  bool _e2eEnabled = false;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSettingUp = false;

  String? _localE2eStatus;
  bool _isUnlocked = false;
  bool _isLoadingMemories = false;
  List<dynamic> _memories = [];
  final _storage = const FlutterSecureStorage();
  final _unlockPasswordController = TextEditingController();

  
  bool _isPinLocked = false;
  String? _pin;
  final _pinController = TextEditingController();

  bool _isCalendarView = false;
  Map<int, Map<int, Map<int, List<dynamic>>>> _groupedMemories = {};
  final Set<int> _collapsedYears = {};
  final Set<String> _collapsedMonths = {};
  final Set<String> _expandedStacks = {}; 
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMore = true;

  final List<Color> _monthColors = [
    Colors.transparent,
    const Color(0xFFE57373), 
    const Color(0xFFF06292), 
    const Color(0xFFBA68C8), 
    const Color(0xFF9575CD), 
    const Color(0xFF7986CB), 
    const Color(0xFF64B5F6), 
    const Color(0xFF4FC3F7), 
    const Color(0xFF4DD0E1), 
    const Color(0xFF4DB6AC), 
    const Color(0xFF81C784), 
    const Color(0xFFFFB74D), 
    const Color(0xFFFF8A65), 
  ];

  void _groupMemoriesList() {
    _groupedMemories = {};
    for (var memory in _memories) {
      final createdAt = memory['createdAt'];
      if (createdAt != null) {
        try {
          final date = DateTime.parse(createdAt).toLocal();
          final year = date.year;
          final month = date.month;
          final day = date.day;

          _groupedMemories.putIfAbsent(year, () => {});
          _groupedMemories[year]!.putIfAbsent(month, () => {});
          _groupedMemories[year]![month]!.putIfAbsent(day, () => []);
          _groupedMemories[year]![month]![day]!.add(memory);
        } catch (_) {}
      }
    }
  }

  final Map<String, Color> _tagColors = {
    'blue': Colors.blue,
    'red': Colors.red,
    'green': Colors.green,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'pink': Colors.pink,
    'teal': Colors.teal,
  };

  Color _getColor(String? colorName) {
    if (colorName == null) return Colors.blue;
    return _tagColors[colorName] ?? Colors.blue;
  }

  @override
  void initState() {
    super.initState();
    _localE2eStatus = widget.e2eStatus;
    _introController = AnimationController(vsync: this);
    _scrollController.addListener(_onScroll);
    _checkInitialState();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore &&
        !_isCalendarView) {
      _loadMoreMemories();
    }
  }

  Future<void> _checkInitialState() async {
    final pin = await _storage.read(key: 'memory_lanes_pin');
    if (pin != null) {
      setState(() {
        _pin = pin;
        _isPinLocked = true;
      });
    }

    if (_localE2eStatus != null) {
      if (_localE2eStatus == 'true') {
        final cached = await _storage.read(key: 'memory_lanes_password');
        if (cached != null) {
          _unlockPasswordController.text = cached;
          _unlock();
        }
      } else {
        _unlock();
      }
    }
  }

  void _unlock() {
    setState(() {
      _isUnlocked = true;
    });
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() {
      _isLoadingMemories = true;
      _hasMore = true;
    });
    try {
      final memories = await widget.apiService.getMemories();

      
      if (_localE2eStatus == 'true' &&
          _unlockPasswordController.text.isNotEmpty) {
        final key = encrypt.Key.fromUtf8(
          _unlockPasswordController.text.padRight(32).substring(0, 32),
        );
        final encrypter = encrypt.Encrypter(encrypt.AES(key));

        String decryptField(String text) {
          try {
            if (text.contains(':')) {
              final parts = text.split(':');
              if (parts.length == 2) {
                final iv = encrypt.IV.fromBase64(parts[0]);
                return encrypter.decrypt64(parts[1], iv: iv);
              }
            }
            return text;
          } catch (e) {
            return text;
          }
        }

        for (var memory in memories) {
          if (memory['public'] == true) continue;
          if (memory['description'] != null)
            memory['description'] = decryptField(memory['description']);
          if (memory['name'] != null)
            memory['name'] = decryptField(memory['name']);
          if (memory['tag'] != null)
            memory['tag'] = decryptField(memory['tag']);
          if (memory['tagColor'] != null)
            memory['tagColor'] = decryptField(memory['tagColor']);
          if (memory['mood'] != null)
            memory['mood'] = decryptField(memory['mood']);
        }
      }

      if (mounted) {
        setState(() {
          _memories = memories;
          _groupMemoriesList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load memories: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingMemories = false);
    }
  }

  Future<void> _loadMoreMemories() async {
    setState(() => _isLoadingMore = true);
    try {
      final newMemories = await widget.apiService.getMemories(length: 30);
      if (mounted) {
        if (newMemories.isEmpty) {
          setState(() => _hasMore = false);
        } else {
          setState(() {
            
            final existingIds = _memories.map((m) => m['\$id']).toSet();
            final uniqueNew = newMemories
                .where((m) => !existingIds.contains(m['\$id']))
                .toList();

            if (uniqueNew.isEmpty) {
              _hasMore = false;
            } else {
              _memories.addAll(uniqueNew);
              _groupMemoriesList();
            }
          });
        }
      }
    } catch (e) {
      
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  void dispose() {
    _introController.dispose();
    _passwordController.dispose();
    _unlockPasswordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onIntroLoaded(LottieComposition composition) {
    _introController
      ..duration = composition.duration
      ..forward().whenComplete(() {
        if (mounted) {
          setState(() => _showIntroAnimation = false);
        }
      });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isPinLocked) {
      return _buildPinLockScreen(context, colorScheme);
    }

    if (_localE2eStatus == 'true' && !_isUnlocked) {
      return _buildLockScreen(context, colorScheme);
    }

    if (_localE2eStatus != null && _isUnlocked) {
      return _buildMainView(context, colorScheme);
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Memory Lanes',
          style: GoogleFonts.gabarito(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _buildCurrentStep(context, colorScheme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinLockScreen(BuildContext context, ColorScheme colorScheme) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory Lanes Locked')),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Enter PIN',
              style: GoogleFonts.gabarito(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final filled = _pinController.text.length > index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    border: Border.all(
                      color: filled ? colorScheme.primary : colorScheme.outline,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            const Spacer(),
            Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1.2,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 24,
                ),
                itemCount: 12,
                itemBuilder: (context, index) {
                  if (index == 9) return const SizedBox(); 
                  if (index == 11) {
                    
                    return InkWell(
                      onTap: () {
                        if (_pinController.text.isNotEmpty) {
                          setState(() {
                            _pinController.text = _pinController.text.substring(
                              0,
                              _pinController.text.length - 1,
                            );
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(40),
                      child: Center(
                        child: Icon(
                          Icons.backspace_outlined,
                          color: colorScheme.onSurface,
                          size: 28,
                        ),
                      ),
                    );
                  }

                  final number = index == 10 ? 0 : index + 1;
                  return FilledButton.tonal(
                    onPressed: () {
                      if (_pinController.text.length < 4) {
                        setState(() {
                          _pinController.text += number.toString();
                        });

                        if (_pinController.text.length == 4) {
                          if (_pinController.text == _pin) {
                            Future.delayed(
                              const Duration(milliseconds: 200),
                              () {
                                setState(() {
                                  _isPinLocked = false;
                                  _pinController.clear();
                                });
                              },
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Incorrect PIN')),
                            );
                            _pinController.clear();
                          }
                        }
                      }
                    },
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(20),
                      backgroundColor: colorScheme.surfaceContainerHigh,
                    ),
                    child: Text(
                      number.toString(),
                      style: GoogleFonts.gabarito(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Future<void> _showPinSetupDialog() async {
    final isPinSet = _pin != null;
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isPinSet ? 'Manage PIN' : 'Set PIN',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPinSet) ...[
              Text(
                'PIN is currently enabled.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () async {
                  await _storage.delete(key: 'memory_lanes_pin');
                  setState(() => _pin = null);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Remove PIN'),
              ),
            ] else ...[
              Text(
                'Set a 4-digit PIN to lock Memory Lanes.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: const InputDecoration(
                  hintText: '****',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (!isPinSet)
            FilledButton(
              onPressed: () async {
                if (controller.text.length == 4) {
                  await _storage.write(
                    key: 'memory_lanes_pin',
                    value: controller.text,
                  );
                  setState(() => _pin = controller.text);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Set PIN'),
            ),
        ],
      ),
    );
  }

  Widget _buildLockScreen(BuildContext context, ColorScheme colorScheme) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory Lanes')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 64,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Enter Password',
              style: GoogleFonts.gabarito(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _unlockPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Encryption Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                if (_unlockPasswordController.text.isNotEmpty) {
                  await _storage.write(
                    key: 'memory_lanes_password',
                    value: _unlockPasswordController.text,
                  );
                  _unlock();
                }
              },
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainView(BuildContext context, ColorScheme colorScheme) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Lanes'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _pin != null ? Icons.lock : Icons.lock_open,
              color: colorScheme.onSurface,
            ),
            tooltip: 'Lock Settings',
            onPressed: _showPinSetupDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoadingMemories
          ? const Center(child: CircularProgressIndicator())
          : _memories.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 64,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No memories yet',
                    style: GoogleFonts.gabarito(
                      fontSize: 18,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            )
          : _isCalendarView
          ? _buildCalendarView(context, colorScheme)
          : _buildListView(context, colorScheme),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreateMemoryPage(
                apiService: widget.apiService,
                e2eEnabled: _localE2eStatus == 'true',
              ),
            ),
          );
          if (result == true) {
            _loadMemories();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildListView(BuildContext context, ColorScheme colorScheme) {
    final years = _groupedMemories.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: years.length + 1, 
      itemBuilder: (context, index) {
        if (index == years.length) {
          return _isLoadingMore
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : const SizedBox(height: 80); 
        }

        final year = years[index];
        
        return _buildYearContent(context, colorScheme, year);
      },
    );
  }

  Widget _buildYearContent(
    BuildContext context,
    ColorScheme colorScheme,
    int year,
  ) {
    final months = _groupedMemories[year]!.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      children: months.map((month) {
        final monthKey = '$year-$month';
        final isCollapsed = _collapsedMonths.contains(monthKey);
        final monthColor = _monthColors[month];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
            InkWell(
              onTap: () => setState(() {
                if (isCollapsed) {
                  _collapsedMonths.remove(monthKey);
                } else {
                  _collapsedMonths.add(monthKey);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Text(
                      DateFormat('MMMM').format(DateTime(year, month)),
                      style: GoogleFonts.gabarito(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: monthColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      year.toString(),
                      style: GoogleFonts.gabarito(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      isCollapsed ? Icons.expand_more : Icons.expand_less,
                      color: monthColor,
                    ),
                  ],
                ),
              ),
            ),

            if (!isCollapsed)
              _buildMonthContent(context, colorScheme, year, month),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildMonthContent(
    BuildContext context,
    ColorScheme colorScheme,
    int year,
    int month,
  ) {
    final days = _groupedMemories[year]![month]!.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      children: days.map((day) {
        final memories = _groupedMemories[year]![month]![day]!;
        
        memories.sort(
          (a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''),
        );

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              SizedBox(
                width: 40,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      day.toString(),
                      style: GoogleFonts.gabarito(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      DateFormat(
                        'E',
                      ).format(DateTime(year, month, day)).toUpperCase(),
                      style: GoogleFonts.gabarito(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),

              
              SizedBox(
                width: 30,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      width: 2,
                      color: colorScheme.outlineVariant,
                      height: double.infinity,
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _monthColors[month],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: memories.length > 1
                      ? _buildStack(
                          context,
                          colorScheme,
                          memories,
                          _monthColors[month],
                          '$year-$month-$day',
                        )
                      : _buildMemoryCard(
                          context,
                          colorScheme,
                          memories.first,
                          _monthColors[month],
                        ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStack(
    BuildContext context,
    ColorScheme colorScheme,
    List<dynamic> memories,
    Color color,
    String stackKey,
  ) {
    final isExpanded = _expandedStacks.contains(stackKey);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: isExpanded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                
                InkWell(
                  onTap: () => setState(() => _expandedStacks.remove(stackKey)),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.expand_less,
                          size: 16,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Collapse stack',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                ...memories.map(
                  (memory) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _buildMemoryCard(
                      context,
                      colorScheme,
                      memory,
                      color,
                    ),
                  ),
                ),
              ],
            )
          : GestureDetector(
              onTap: () => setState(() => _expandedStacks.add(stackKey)),
              child: Stack(
                children: [
                  
                  Transform.translate(
                    offset: const Offset(4, 4),
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(8, 8),
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color.withValues(alpha: 0.1)),
                      ),
                    ),
                  ),
                  
                  _buildMemoryCard(
                    context,
                    colorScheme,
                    memories.first,
                    color,
                    isStackTop: true,
                    count: memories.length,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMemoryCard(
    BuildContext context,
    ColorScheme colorScheme,
    dynamic memory,
    Color color, {
    bool isStackTop = false,
    int count = 0,
  }) {
    final tag = memory['tag'];
    final tagColorName = memory['tagColor'];
    final cardColor = _getColor(
      tagColorName,
    ); 

    return Card(
      elevation: 0,
      color: cardColor.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cardColor.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isStackTop ? null : () => _openMemory(memory),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      memory['name'] ?? 'Untitled',
                      style: GoogleFonts.gabarito(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isStackTop)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '+${count - 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              if (tag != null && tag.toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  tag,
                  style: GoogleFonts.gabarito(
                    fontSize: 12,
                    color: cardColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMemory(dynamic memory) async {
    final result = await Navigator.of(context).push<bool?>(
      MaterialPageRoute(
        builder: (_) =>
            MemoryDetailPage(memory: memory, apiService: widget.apiService),
      ),
    );
    if (result == true) {
      _loadMemories();
    }
  }

  Widget _buildCalendarView(BuildContext context, ColorScheme colorScheme) {
    
    final years = _groupedMemories.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: years.length,
      itemBuilder: (context, index) {
        final year = years[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              year.toString(),
              style: GoogleFonts.gabarito(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: 12,
              itemBuilder: (context, monthIndex) {
                final month = monthIndex + 1;
                final hasMemories =
                    _groupedMemories[year]?.containsKey(month) ?? false;
                final count = hasMemories
                    ? _groupedMemories[year]![month]!.values.fold(
                        0,
                        (sum, list) => sum + list.length,
                      )
                    : 0;

                return Card(
                  color: hasMemories
                      ? _monthColors[month].withValues(alpha: 0.1)
                      : colorScheme.surfaceContainerLow,
                  elevation: 0,
                  child: InkWell(
                    onTap: hasMemories
                        ? () {
                            
                            
                            setState(() {
                              _isCalendarView = false;
                              _collapsedYears.remove(year);
                              _collapsedMonths.remove('$year-$month');
                            });
                          }
                        : null,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('MMM').format(DateTime(year, month)),
                          style: GoogleFonts.gabarito(
                            fontWeight: FontWeight.bold,
                            color: hasMemories
                                ? _monthColors[month]
                                : colorScheme.outline,
                          ),
                        ),
                        if (count > 0) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _monthColors[month],
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              count.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Widget _buildCurrentStep(BuildContext context, ColorScheme colorScheme) {
    switch (_currentStep) {
      case 1:
        return _buildWelcomeStep(colorScheme);
      case 2:
        return _buildSecurityStep(colorScheme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWelcomeStep(ColorScheme colorScheme) {
    return Column(
      key: const ValueKey(1),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          constraints: BoxConstraints(
            maxWidth: _showIntroAnimation ? 300 : 200,
            maxHeight: _showIntroAnimation ? 300 : 200,
          ),
          child: _showIntroAnimation
              ? Lottie.asset(
                  'assets/anim/memorylanes.json',
                  controller: _introController,
                  onLoaded: _onIntroLoaded,
                  fit: BoxFit.contain,
                )
              : Lottie.asset('assets/anim/notepad.json', fit: BoxFit.contain),
        ),
        const SizedBox(height: 32),
        Text(
          'Memory Lanes',
          style: GoogleFonts.gabarito(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Write down the best - and the worst of your life in your memory lanes so you can occasionally take a trip down the road!',
          textAlign: TextAlign.center,
          style: GoogleFonts.gabarito(
            fontSize: 18,
            height: 1.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 48),
        FilledButton(
          onPressed: () => setState(() => _currentStep = 2),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            'Next',
            style: GoogleFonts.gabarito(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityStep(ColorScheme colorScheme) {
    return Column(
      key: const ValueKey(2),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
          child: Lottie.asset(
            'assets/anim/safe.json',
            repeat: false,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Secure your memories',
          style: GoogleFonts.gabarito(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              _buildWarningItem(
                context,
                'Your memories are encrypted on AurAchieve\'s servers.',
                icon: Icons.lock_outline,
              ),
              _buildWarningItem(
                context,
                'Read more in the Privacy Policy.',
                icon: Icons.privacy_tip_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IgnorePointer(
                  child: CheckboxListTile(
                    value: true,
                    onChanged: (_) {},
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Encryption',
                      style: GoogleFonts.gabarito(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      'Always active',
                      style: GoogleFonts.gabarito(color: colorScheme.primary),
                    ),
                    secondary: Icon(Icons.security, color: colorScheme.primary),
                  ),
                ),
                const Divider(),
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Advanced Security',
                      style: GoogleFonts.gabarito(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    leading: Icon(
                      Icons.admin_panel_settings_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'End-to-End Encryption',
                          style: GoogleFonts.gabarito(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          'Maximum privacy with your own password',
                          style: GoogleFonts.gabarito(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        value: _e2eEnabled,
                        onChanged: (val) => setState(() => _e2eEnabled = val),
                      ),
                      if (_e2eEnabled) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(color: colorScheme.onSurface),
                          decoration: InputDecoration(
                            labelText: 'Encryption Password',
                            labelStyle: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildWarningItem(
                          context,
                          'If you lose this password, your memories are gone forever.',
                          isError: true,
                        ),
                        _buildWarningItem(
                          context,
                          'No one, not even AurAchieve, can recover your data.',
                          isError: true,
                        ),
                        _buildWarningItem(
                          context,
                          'Media upload size limits will be smaller.',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _isSettingUp
              ? null
              : () async {
                  if (_e2eEnabled && _passwordController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please set a password.')),
                    );
                    return;
                  }

                  setState(() => _isSettingUp = true);
                  try {
                    await widget.apiService.setupMemoryLanes(e2e: _e2eEnabled);

                    if (_e2eEnabled) {
                      await _storage.write(
                        key: 'memory_lanes_password',
                        value: _passwordController.text,
                      );
                      _unlockPasswordController.text = _passwordController.text;
                    }

                    setState(() {
                      _localE2eStatus = _e2eEnabled ? 'true' : 'false';
                    });
                    _unlock();
                  } catch (e) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Setup failed: $e')));
                  } finally {
                    if (mounted) setState(() => _isSettingUp = false);
                  }
                },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isSettingUp
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  'Get Started',
                  style: GoogleFonts.gabarito(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildWarningItem(
    BuildContext context,
    String text, {
    bool isError = false,
    IconData icon = Icons.info_outline_rounded,
  }) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.warning_amber_rounded : icon,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.gabarito(
                fontSize: 13,
                color: color,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
