import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import 'screens/create_memory.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'screens/view_memory.dart';
import 'utils/draft_utils.dart';
import 'lock.dart';

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
  bool _isInitializing = true;
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

  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _isDeepSearching = false;

  List<dynamic> get _searchResults {
    if (_searchQuery.isEmpty) return [];
    final query = _searchQuery.toLowerCase();
    return _memories.where((m) {
      final name = (m['name']?.toString() ?? '').toLowerCase();
      final desc = (m['description']?.toString() ?? '').toLowerCase();
      final tag = (m['tag']?.toString() ?? '').toLowerCase();
      return name.contains(query) ||
          desc.contains(query) ||
          tag.contains(query);
    }).toList();
  }

  Future<void> _deepSearch() async {
    setState(() {
      _isDeepSearching = true;
    });
    try {
      final nextOffset = _currentOffset + _pageSize;
      final response = await widget.apiService.getMemories(
        length: 100,
        offset: nextOffset,
      );
      final newMemories = response['documents'] as List<dynamic>? ?? [];
      _totalMemories = response['total'] ?? _totalMemories;

      if (_localE2eStatus == 'true' &&
          _unlockPasswordController.text.isNotEmpty) {
        bool badPassword = false;
        final key = encrypt.Key.fromUtf8(
          _unlockPasswordController.text.padRight(32).substring(0, 32),
        );
        final encrypter = encrypt.Encrypter(encrypt.AES(key));

        String decryptField(String text) {
          if (badPassword) return text;
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
            badPassword = true;
            return text;
          }
        }

        for (var memory in newMemories) {
          if (badPassword) break;
          if (memory['public'] == true) continue;
          if (memory['description'] != null) {
            memory['description'] = decryptField(memory['description']);
          }
          if (memory['name'] != null) {
            memory['name'] = decryptField(memory['name']);
          }
          if (memory['tag'] != null) {
            memory['tag'] = decryptField(memory['tag']);
          }
          if (memory['tagColor'] != null) {
            memory['tagColor'] = decryptField(memory['tagColor']);
          }
          if (memory['mood'] != null) {
            memory['mood'] = decryptField(memory['mood']);
          }
        }

        if (badPassword) {
          await _storage.delete(key: 'memory_lanes_password');
          if (mounted) {
            setState(() {
              _isUnlocked = false;
              _unlockPasswordController.clear();
              _isDeepSearching = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Incorrect encryption password!')),
            );
          }
          return;
        }
      }

      setState(() {
        _currentOffset = nextOffset + 100 - _pageSize;
        final existingIds = _memories.map((m) => m['id'] ?? m['\$id']).toSet();
        final uniqueNew = newMemories
            .where((m) => !existingIds.contains(m['id'] ?? m['\$id']))
            .toList();

        _memories.addAll(uniqueNew);
        _groupMemoriesList();
        _hasMore =
            _memories.where((m) => m['isDraft'] != true).length <
            _totalMemories;
      });
    } catch (e) {
      debugPrint('Deep search failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isDeepSearching = false;
        });
      }
    }
  }

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

  int _currentOffset = 0;
  static const int _pageSize = 30;
  int _totalMemories = 0;

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
      if (mounted) {
        setState(() {
          _pin = pin;
          _isPinLocked = true;
        });
      }
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

    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
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
      _currentOffset = 0;
    });
    try {
      final response = await widget.apiService.getMemories(
        length: _pageSize,
        offset: _currentOffset,
      );
      final memories = response['documents'] as List<dynamic>? ?? [];
      _totalMemories = response['total'] ?? 0;

      final drafts = await DraftManager.getDrafts();
      final draftMemories = drafts
          .map(
            (d) => {
              'id': d.id,
              'name': d.title,
              'description': d.description,
              'tag': d.tag,
              'tagColor': d.tagColor,
              'mood': d.mood,
              'createdAt': DateTime.fromMillisecondsSinceEpoch(
                d.timestamp,
              ).toIso8601String(),
              'isDraft': true,
              'draftObject': d,
            },
          )
          .toList();

      if (_localE2eStatus == 'true' &&
          _unlockPasswordController.text.isNotEmpty) {
        bool badPassword = false;
        final key = encrypt.Key.fromUtf8(
          _unlockPasswordController.text.padRight(32).substring(0, 32),
        );
        final encrypter = encrypt.Encrypter(encrypt.AES(key));

        String decryptField(String text) {
          if (badPassword) return text;
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
            badPassword = true;
            return text;
          }
        }

        for (var memory in memories) {
          if (badPassword) break;
          if (memory['public'] == true) continue;
          if (memory['description'] != null) {
            memory['description'] = decryptField(memory['description']);
          }
          if (memory['name'] != null) {
            memory['name'] = decryptField(memory['name']);
          }
          if (memory['tag'] != null) {
            memory['tag'] = decryptField(memory['tag']);
          }
          if (memory['tagColor'] != null) {
            memory['tagColor'] = decryptField(memory['tagColor']);
          }
          if (memory['mood'] != null) {
            memory['mood'] = decryptField(memory['mood']);
          }
        }

        if (badPassword) {
          await _storage.delete(key: 'memory_lanes_password');
          if (mounted) {
            setState(() {
              _isUnlocked = false;
              _unlockPasswordController.clear();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Incorrect encryption password!')),
            );
          }
          return;
        }
      }

      if (mounted) {
        setState(() {
          _memories = [...draftMemories, ...memories];
          _groupMemoriesList();
          _hasMore =
              _memories.where((m) => m['isDraft'] != true).length <
              _totalMemories;
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
    if (!_hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    final nextOffset = _currentOffset + _pageSize;

    try {
      final response = await widget.apiService.getMemories(
        length: _pageSize,
        offset: nextOffset,
      );
      final newMemories = response['documents'] as List<dynamic>? ?? [];
      _totalMemories = response['total'] ?? _totalMemories;

      if (mounted) {
        if (newMemories.isEmpty) {
          setState(() => _hasMore = false);
        } else {
          if (_localE2eStatus == 'true' &&
              _unlockPasswordController.text.isNotEmpty) {
            bool badPassword = false;
            final key = encrypt.Key.fromUtf8(
              _unlockPasswordController.text.padRight(32).substring(0, 32),
            );
            final encrypter = encrypt.Encrypter(encrypt.AES(key));

            String decryptField(String text) {
              if (badPassword) return text;
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
                badPassword = true;
                return text;
              }
            }

            for (var memory in newMemories) {
              if (badPassword) break;
              if (memory['public'] == true) continue;
              if (memory['description'] != null) {
                memory['description'] = decryptField(memory['description']);
              }
              if (memory['name'] != null) {
                memory['name'] = decryptField(memory['name']);
              }
              if (memory['tag'] != null) {
                memory['tag'] = decryptField(memory['tag']);
              }
              if (memory['tagColor'] != null) {
                memory['tagColor'] = decryptField(memory['tagColor']);
              }
              if (memory['mood'] != null) {
                memory['mood'] = decryptField(memory['mood']);
              }
            }

            if (badPassword) {
              await _storage.delete(key: 'memory_lanes_password');
              setState(() {
                _isUnlocked = false;
                _unlockPasswordController.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Incorrect encryption password!')),
              );
              return;
            }
          }

          setState(() {
            _currentOffset = nextOffset;
            final existingIds = _memories
                .map((m) => m[r'$id'] ?? m['id'])
                .toSet();
            final uniqueNew = newMemories
                .where((m) => !existingIds.contains(m[r'$id'] ?? m['id']))
                .toList();

            if (uniqueNew.isEmpty) {
              _hasMore = false;
            } else {
              _memories.addAll(uniqueNew);
              _groupMemoriesList();
              _hasMore =
                  _memories.where((m) => m['isDraft'] != true).length <
                  _totalMemories;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Load more failed: $e');
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
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    if (_isPinLocked) {
      return LockScreen(
        onPinEntered: (enteredPin) async {
          if (enteredPin == _pin) {
            setState(() => _isPinLocked = false);
            return true;
          } else {
            return false;
          }
        },
        onCancel: () => Navigator.pop(context),
      );
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

  Future<void> _showPinSetupDialog() async {
    if (_pin != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Remove PIN',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Text(
            'Are you sure you want to remove the PIN lock?',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _storage.delete(key: 'memory_lanes_pin');
        setState(() => _pin = null);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('PIN removed')));
        }
      }
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LockScreen(
          isSetup: true,
          title: 'Set a PIN',
          onPinEntered: (newPin) async {
            await _storage.write(key: 'memory_lanes_pin', value: newPin);
            if (mounted) {
              setState(() {
                _pin = newPin;

                _isPinLocked = false;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN setup successfully')),
              );
            }
            return true;
          },
        ),
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
              'Enter encryption password',
              style: GoogleFonts.gabarito(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _unlockPasswordController,
              obscureText: true,
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Encryption Password',
                labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                border: const OutlineInputBorder(),
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
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Forgot or Lost your Key?'),
                    content: Text(
                      "Unfortunately, since Memory Lanes uses End-to-End Encryption, we do not store your key on our servers to ensure complete privacy. \n\nWe don't know it, you forgot it... meaning it's gone. HAHAHAHAHA! We're sorry to say but your encrypted memories are permanently inaccessible. There is no way to recover them.",
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Okay :('),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Forgot/lost encryption password?'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainView(BuildContext context, ColorScheme colorScheme) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search memories...',
                  border: InputBorder.none,
                ),
                style: GoogleFonts.gabarito(color: colorScheme.onSurface),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
              )
            : const Text('Memory Lanes'),
        centerTitle: !_isSearching,
        leading: _isSearching
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: colorScheme.onSurface,
                ),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
              )
            : null,
        actions: [
          if (!_isSearching)
            IconButton(
              icon: Icon(Icons.search_rounded, color: colorScheme.onSurface),
              tooltip: 'Search',
              onPressed: () => setState(() => _isSearching = true),
            ),
          if (!_isSearching && _localE2eStatus == 'true' && _isUnlocked)
            IconButton(
              icon: Icon(Icons.key_rounded, color: colorScheme.onSurface),
              tooltip: 'View Encryption Password',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Your Encryption Password'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Save this key securely! If you log into a new device and forget it, your memories will be lost forever!',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SelectableText(
                          _unlockPasswordController.text,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (!_isSearching)
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
          : _isSearching
          ? _buildSearchResults(context, colorScheme)
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

  Widget _buildSearchResults(BuildContext context, ColorScheme colorScheme) {
    if (_searchQuery.isEmpty) {
      return Center(
        child: Text(
          'Type to search...',
          style: GoogleFonts.gabarito(
            fontSize: 18,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final results = _searchResults;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No local results found.',
              style: GoogleFonts.gabarito(
                fontSize: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (_hasMore)
              _isDeepSearching
                  ? const CircularProgressIndicator()
                  : FilledButton.icon(
                      onPressed: _deepSearch,
                      icon: const Icon(Icons.travel_explore),
                      label: const Text('Search with more power'),
                    )
            else if (!_isDeepSearching)
              Text(
                'All memories searched.',
                style: GoogleFonts.gabarito(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length + 1,
      itemBuilder: (context, index) {
        if (index == results.length) {
          if (_hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: _isDeepSearching
                    ? const CircularProgressIndicator()
                    : FilledButton.tonalIcon(
                        onPressed: _deepSearch,
                        icon: const Icon(Icons.travel_explore),
                        label: const Text('Search with more power'),
                      ),
              ),
            );
          }
          return const SizedBox(height: 32);
        }

        final memory = results[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildMemoryCard(
            context,
            colorScheme,
            memory,
            _getColor(memory['tagColor']),
          ),
        );
      },
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
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      year.toString(),
                      style: GoogleFonts.gabarito(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.outline.withOpacity(0.5),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      isCollapsed ? Icons.expand_more : Icons.expand_less,
                      color: colorScheme.primary,
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
                        color: colorScheme.primary,
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
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(8, 8),
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withOpacity(0.5),
                        ),
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
    int count = 1,
  }) {
    final isDraft = memory['isDraft'] == true;
    final tag = memory['tag'];
    final cardColor = _getColor(memory['tagColor']);

    return Material(
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDraft
              ? colorScheme.primary.withOpacity(0.5)
              : colorScheme.outlineVariant.withOpacity(0.5),
          width: isDraft ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isStackTop
            ? null
            : () async {
                if (isDraft) {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CreateMemoryPage(
                        apiService: widget.apiService,
                        e2eEnabled: _localE2eStatus == 'true',
                        draft: memory['draftObject'],
                      ),
                    ),
                  );

                  if (result == true || result == null) {
                    _loadMemories();
                  }
                } else {
                  _openMemory(memory);
                }
              },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDraft)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Draft',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
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
                        style: TextStyle(
                          color: colorScheme.onPrimary,
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
        builder: (_) => MemoryDetailPage(
          memory: memory,
          apiService: widget.apiService,
          e2eEnabled: _localE2eStatus == 'true',
        ),
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
                        onChanged: (val) async {
                          setState(() => _e2eEnabled = val);
                          if (val && _passwordController.text.isEmpty) {
                            try {
                              final wordListStr = await DefaultAssetBundle.of(
                                context,
                              ).loadString('assets/eff_large_wordlist.txt');
                              final lines = wordListStr.split('\n');
                              final words = <String>[];
                              for (var line in lines) {
                                final parts = line.split('\t');
                                if (parts.length >= 2) {
                                  words.add(parts[1].trim());
                                }
                              }
                              if (words.isNotEmpty) {
                                final random = Random.secure();
                                final wordCount = 7 + random.nextInt(3);
                                final selectedWords = <String>[];
                                for (var i = 0; i < wordCount; i++) {
                                  selectedWords.add(
                                    words[random.nextInt(words.length)],
                                  );
                                }
                                final key = selectedWords.join('-');
                                _passwordController.text = key;
                                setState(() {
                                  _obscurePassword = false;
                                });
                              }
                            } catch (e) {}
                          }
                        },
                      ),
                      if (_e2eEnabled) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Recovery Passphrase',
                                    style: GoogleFonts.gabarito(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: 20,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.copy_rounded,
                                          size: 20,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          Clipboard.setData(
                                            ClipboardData(
                                              text: _passwordController.text,
                                            ),
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Passphrase copied!',
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_obscurePassword)
                                Text(
                                  '••••••••••••••••••••••••••••••••',
                                  style: TextStyle(
                                    fontSize: 24,
                                    letterSpacing: 4,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                )
                              else
                                SelectableText(
                                  _passwordController.text,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 18,
                                    height: 1.5,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              try {
                                final wordListStr = await DefaultAssetBundle.of(
                                  context,
                                ).loadString('assets/eff_large_wordlist.txt');
                                final lines = wordListStr.split('\n');
                                final words = <String>[];
                                for (var line in lines) {
                                  final parts = line.split('\t');
                                  if (parts.length >= 2) {
                                    words.add(parts[1].trim());
                                  }
                                }

                                if (words.isNotEmpty) {
                                  final random = Random.secure();
                                  final wordCount = 7 + random.nextInt(3);
                                  final selectedWords = <String>[];
                                  for (var i = 0; i < wordCount; i++) {
                                    selectedWords.add(
                                      words[random.nextInt(words.length)],
                                    );
                                  }

                                  final key = selectedWords.join('-');
                                  _passwordController.text = key;
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to generate: $e'),
                                    ),
                                  );
                                }
                              }

                              setState(() {
                                _obscurePassword = false;
                              });
                            },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Generate Another One'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildWarningItem(
                          context,
                          'If you lose this password, your memories are gone forever and no one, not even AurAchieve, can recover your data.',
                          isError: true,
                        ),
                        _buildWarningItem(
                          context,
                          'Memories will be encrypted on your device before being saved to our servers. Media upload size limits may be smaller.',
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
                  if (_e2eEnabled) {
                    if (_passwordController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please set a password.')),
                      );
                      return;
                    }
                    if (_passwordController.text.length < 12) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Encryption key must be at least 12 characters.',
                          ),
                        ),
                      );
                      return;
                    }

                    bool confirmed = false;
                    await showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) {
                        int countdown = 5;
                        Timer? t;
                        return StatefulBuilder(
                          builder: (context, setStateDialog) {
                            t ??= Timer.periodic(const Duration(seconds: 1), (
                              timer,
                            ) {
                              if (countdown > 0) {
                                setStateDialog(() => countdown--);
                              } else {
                                timer.cancel();
                              }
                            });
                            return AlertDialog(
                              title: Text(
                                'Save Your Passphrase',
                                style: GoogleFonts.gabarito(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              content: Text(
                                'If you lose this passphrase, your memories are gone forever. We cannot recover your data. Have you written it down or saved it securely?',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    t?.cancel();
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: countdown > 0
                                      ? null
                                      : () {
                                          t?.cancel();
                                          Navigator.of(context).pop(true);
                                        },
                                  child: Text(
                                    countdown > 0
                                        ? 'Wait ${countdown}s'
                                        : 'I Have Saved It',
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ).then((value) => confirmed = value == true);

                    if (!confirmed) return;
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
