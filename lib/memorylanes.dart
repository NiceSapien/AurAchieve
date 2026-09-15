import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'screens/create_memory.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'utils/crypto_utils.dart';
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
  List<dynamic> _lanes = [];
  Map<String, dynamic>? _activeLane;
  String? _currentUserId;
  final _storage = const FlutterSecureStorage();
  final _unlockPasswordController = TextEditingController();

  bool _isPinLocked = false;
  String? _pin;
  final _pinController = TextEditingController();

  bool _isCalendarView = false;
  bool _compactView = false;
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
      final laneId = _activeLane?['id']?.toString();
      final response = await widget.apiService.getMemories(
        laneId: laneId,
        length: 100,
        offset: nextOffset,
      );
      final newMemories = response['documents'] as List<dynamic>? ?? [];
      _totalMemories = response['total'] ?? _totalMemories;

      final activeLaneE2e = _activeLane?['isE2e'] == true;
      final activeKeyString = activeLaneE2e
          ? await _getActiveLaneKey(laneId)
          : null;

      if (activeLaneE2e && activeKeyString != null) {
        bool badPassword = false;

        String decryptField(String text) {
          if (badPassword) return text;
          try {
            if (text.contains(':')) {
              final parts = text.split(':');
              if (parts.length == 2) {
                final iv = encrypt.IV.fromBase64(parts[0]);
                final ciphertext = parts[1];

                // 1. Try PBKDF2 decryption
                try {
                  final key = derivePBKDF2Key(activeKeyString);
                  final encrypter = encrypt.Encrypter(encrypt.AES(key));
                  final decrypted = encrypter.decrypt64(ciphertext, iv: iv);
                  if (decrypted.startsWith('{"') ||
                      decrypted.startsWith('[') ||
                      !decrypted.contains('\x00')) {
                    return decrypted;
                  }
                } catch (_) {}

                // 2. Fallback to legacy decryption
                final key = getLegacyKey(activeKeyString);
                final encrypter = encrypt.Encrypter(encrypt.AES(key));
                return encrypter.decrypt64(ciphertext, iv: iv);
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
          await _storage.delete(key: 'memory_lanes_password_$laneId');
          if (mounted) {
            setState(() {
              _isUnlocked = false;
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
    _activeLane = {
      'id': null,
      'name': 'Personal',
      'isE2e': _localE2eStatus == 'true',
    };
    _lanes = [_activeLane!];
    _introController = AnimationController(vsync: this);
    _scrollController.addListener(_onScroll);
    _checkInitialState();
    _loadCompactViewSetting();
  }

  Future<void> _loadCompactViewSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _compactView = prefs.getBool('compact_memories_list') ?? false;
      });
    } catch (_) {}
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

  Future<void> _setupRsaKeyPair() async {
    try {
      String? localPrivateKey = await _storage.read(
        key: 'memory_lanes_private_key',
      );
      String? localPublicKey = await _storage.read(
        key: 'memory_lanes_public_key',
      );

      final profile = await widget.apiService.getUserProfile();
      final serverPublicKey = profile['publicKey'];

      if (localPrivateKey == null ||
          localPublicKey == null ||
          serverPublicKey == null ||
          serverPublicKey.isEmpty) {
        final keyPair = generateRSAKeyPair();
        final pubJson = encodePublicKey(keyPair.publicKey);
        final privJson = encodePrivateKey(keyPair.privateKey);

        await _storage.write(key: 'memory_lanes_private_key', value: privJson);
        await _storage.write(key: 'memory_lanes_public_key', value: pubJson);

        await widget.apiService.savePublicKey(pubJson);
      }
    } catch (e) {
      debugPrint('Error setting up RSA keys: $e');
    }
  }

  Future<String?> _getActiveLaneKey(String? laneId) async {
    if (laneId == null) {
      return _unlockPasswordController.text;
    }
    String? key = await _storage.read(key: 'memory_lanes_password_$laneId');
    if (key != null && key.isNotEmpty) return key;

    try {
      final encryptedKey = await widget.apiService.getLaneKey(laneId);
      if (encryptedKey != null) {
        final privateKeyJson = await _storage.read(
          key: 'memory_lanes_private_key',
        );
        if (privateKeyJson != null) {
          final decryptedKey = decryptLaneKeyWithJsonPrivateKey(
            encryptedKey,
            privateKeyJson,
          );
          await _storage.write(
            key: 'memory_lanes_password_$laneId',
            value: decryptedKey,
          );
          await prewarmPBKDF2Key(decryptedKey);
          return decryptedKey;
        }
      }
    } catch (e) {
      debugPrint('Failed to resolve active lane key: $e');
    }
    return null;
  }

  Future<void> _fetchLanes() async {
    try {
      final fetched = await widget.apiService.getLanes();
      if (_currentUserId == null) {
        try {
          final profile = await widget.apiService.getUserProfile();
          _currentUserId =
              (profile['userId'] ?? profile[r'$id'] ?? profile['id'])
                  ?.toString();
        } catch (_) {}
      }

      final prefs = await SharedPreferences.getInstance();
      final savedLaneId = prefs.getString('last_opened_lane_id');

      setState(() {
        _lanes = [
          {'id': null, 'name': 'Personal', 'isE2e': _localE2eStatus == 'true'},
          ...fetched,
        ];

        final activeId = _activeLane?['id']?.toString() ?? savedLaneId;
        final matchedIndex = _lanes.indexWhere(
          (l) => l['id']?.toString() == activeId,
        );
        if (matchedIndex != -1) {
          _activeLane = _lanes[matchedIndex];
        } else {
          _activeLane = _lanes.first;
        }
      });
    } catch (e) {
      debugPrint('Failed to fetch lanes: $e');
    }
  }

  Future<void> _createNewLane(String name, bool isE2e) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final laneData = await widget.apiService.createLane(
        name: name,
        isE2e: isE2e,
      );
      final String laneId = (laneData['id'] ?? laneData[r'$id'] ?? '')
          .toString();

      if (isE2e) {
        final random = Random.secure();
        final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
        final String laneKey = base64Encode(keyBytes);

        final myPublicKeyJson = await _storage.read(
          key: 'memory_lanes_public_key',
        );
        if (myPublicKeyJson != null) {
          final encryptedLaneKey = encryptLaneKeyWithJsonPublicKey(
            laneKey,
            myPublicKeyJson,
          );

          final profile = await widget.apiService.getUserProfile();
          final String myUserId =
              (profile['userId'] ?? profile[r'$id'] ?? profile['id'] ?? '')
                  .toString();

          await widget.apiService.saveLaneKey(
            laneId,
            myUserId,
            encryptedLaneKey,
          );
          await _storage.write(
            key: 'memory_lanes_password_$laneId',
            value: laneKey,
          );
        }
      }

      await _fetchLanes();

      if (mounted) {
        final newLane = _lanes.firstWhere(
          (l) => l['id'] == laneId,
          orElse: () => _lanes.first,
        );
        setState(() {
          _activeLane = newLane;
        });
        Navigator.pop(context); // Dismiss loading spinner
        _loadMemories();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading spinner
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create lane: $e')));
      }
    }
  }

  void _showLaneSwitcherBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Text(
                  'Select Memory Lane',
                  style: GoogleFonts.gabarito(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _lanes.length,
                  itemBuilder: (context, index) {
                    final lane = _lanes[index];
                    final isSelected = _activeLane?['id'] == lane['id'];
                    final isE2e = lane['isE2e'] == true;
                    final isPersonal = lane['id'] == null;

                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primaryContainer.withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary.withOpacity(0.3)
                              : Colors.transparent,
                        ),
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primary.withOpacity(0.15)
                                : colorScheme.onSurface.withOpacity(0.04),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPersonal
                                ? Icons.person_rounded
                                : Icons.people_rounded,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          lane['name'] ?? 'Lane',
                          style: GoogleFonts.gabarito(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          isPersonal
                              ? 'Only visible to you'
                              : ((lane['creatorId']?.toString() ==
                                        _currentUserId)
                                    ? (isE2e
                                          ? 'Owner of E2EE shared space'
                                          : 'Owner of the shared space')
                                    : (isE2e
                                          ? 'Member of E2EE shared space'
                                          : 'Member of the shared space')),
                          style: GoogleFonts.gabarito(
                            fontSize: 11,
                            color: isSelected
                                ? colorScheme.primary.withOpacity(0.8)
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: isE2e
                            ? Icon(
                                Icons.security_rounded,
                                size: 16,
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.outline,
                              )
                            : null,
                        onTap: () async {
                          Navigator.pop(context);
                          setState(() {
                            _activeLane = lane;
                          });
                          try {
                            final prefs = await SharedPreferences.getInstance();
                            if (lane['id'] != null) {
                              await prefs.setString(
                                'last_opened_lane_id',
                                lane['id'].toString(),
                              );
                            } else {
                              await prefs.remove('last_opened_lane_id');
                            }
                          } catch (_) {}
                          _loadMemories();
                        },
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    'Create New Memory Lane',
                    style: GoogleFonts.gabarito(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateLaneDialog();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreateLaneDialog() {
    final nameController = TextEditingController();
    bool isE2e = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final colorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            title: Text(
              'Create Memory Lane',
              style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Lane Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: Text(
                    'End-to-End Encrypted',
                    style: GoogleFonts.gabarito(fontSize: 14),
                  ),
                  subtitle: Text(
                    'E2E lanes encrypt your memories before sending them to the cloud.',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: isE2e,
                  onChanged: (val) {
                    setDialogState(() {
                      isE2e = val;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;
                  Navigator.pop(context);
                  await _createNewLane(nameController.text.trim(), isE2e);
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLaneSettingsSheet() {
    final searchController = TextEditingController();
    bool isSearchingUser = false;
    Map<String, dynamic>? foundUser;
    String? searchError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final colorScheme = Theme.of(context).colorScheme;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lane Settings - ${_activeLane?['name']}',
                  style: GoogleFonts.gabarito(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _activeLane?['isE2e'] == true
                      ? 'End-to-End Encrypted Shared Lane'
                      : 'Shared Lane',
                  style: GoogleFonts.gabarito(
                    fontSize: 12,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final laneId = _activeLane?['id']?.toString();
                    final laneCreatorId = _activeLane?['creatorId']?.toString();
                    final isCreator =
                        laneCreatorId == null ||
                        _currentUserId == null ||
                        laneCreatorId == _currentUserId;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isCreator) ...[
                          Text(
                            'Invite Partner to Lane',
                            style: GoogleFonts.gabarito(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: searchController,
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Enter email address',
                                    errorText: searchError,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: isSearchingUser
                                    ? null
                                    : () async {
                                        final query = searchController.text
                                            .trim();
                                        if (query.isEmpty) return;
                                        setSheetState(() {
                                          isSearchingUser = true;
                                          searchError = null;
                                          foundUser = null;
                                        });
                                        try {
                                          final res = await widget.apiService
                                              .searchUser(query);
                                          final foundId =
                                              (res['userId'] ??
                                                      res['id'] ??
                                                      res[r'$id'])
                                                  ?.toString();
                                          if (foundId != null &&
                                              foundId == _currentUserId) {
                                            setSheetState(() {
                                              searchError =
                                                  'You can\'t add yourself';
                                              isSearchingUser = false;
                                            });
                                          } else {
                                            setSheetState(() {
                                              foundUser = res;
                                              isSearchingUser = false;
                                            });
                                          }
                                        } catch (e) {
                                          String msg = e.toString().replaceAll(
                                            'Exception: ',
                                            '',
                                          );
                                          if (msg.contains('{') &&
                                              msg.contains('}')) {
                                            try {
                                              final jsonStart = msg.indexOf(
                                                '{',
                                              );
                                              final jsonStr = msg.substring(
                                                jsonStart,
                                              );
                                              final decoded = jsonDecode(
                                                jsonStr,
                                              );
                                              if (decoded is Map &&
                                                  decoded['error'] != null) {
                                                msg = decoded['error']
                                                    .toString();
                                              }
                                            } catch (_) {}
                                          }
                                          setSheetState(() {
                                            searchError = msg.isNotEmpty
                                                ? msg
                                                : 'User not found';
                                            isSearchingUser = false;
                                          });
                                        }
                                      },
                                child: isSearchingUser
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Search'),
                              ),
                            ],
                          ),
                          if (foundUser != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.primary.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor:
                                        colorScheme.primaryContainer,
                                    foregroundColor:
                                        colorScheme.onPrimaryContainer,
                                    child: Text(
                                      (foundUser!['name']?.toString() ?? 'U')[0]
                                          .toUpperCase(),
                                      style: GoogleFonts.gabarito(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          foundUser!['name'] ?? 'User',
                                          style: GoogleFonts.gabarito(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                        if (foundUser!['username'] != null)
                                          Text(
                                            '@${foundUser!['username']}',
                                            style: GoogleFonts.gabarito(
                                              fontSize: 12,
                                              color: colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () async {
                                      final partnerId =
                                          (foundUser!['userId'] ??
                                                  foundUser!['id'] ??
                                                  foundUser!['_id'] ??
                                                  foundUser!['user_id'] ??
                                                  foundUser![r'$id'])
                                              ?.toString();
                                      final partnerPublicKeyStr =
                                          foundUser!['publicKey'];
                                      final laneId = _activeLane?['id'];

                                      if (laneId == null) return;
                                      if (partnerId == null ||
                                          partnerId.isEmpty ||
                                          partnerId == 'null') {
                                        setSheetState(() {
                                          searchError =
                                              'Could not get user ID for the selected user.';
                                        });
                                        return;
                                      }

                                      try {
                                        await widget.apiService.inviteToLane(
                                          laneId,
                                          partnerId,
                                        );

                                        if (_activeLane?['isE2e'] == true) {
                                          if (partnerPublicKeyStr == null ||
                                              partnerPublicKeyStr
                                                  .toString()
                                                  .isEmpty) {
                                            throw Exception(
                                              'Partner has not set up their encryption key yet.',
                                            );
                                          }

                                          final String?
                                          myLaneKey = await _storage.read(
                                            key:
                                                'memory_lanes_password_$laneId',
                                          );
                                          if (myLaneKey != null) {
                                            final encryptedLaneKey =
                                                encryptLaneKeyWithJsonPublicKey(
                                                  myLaneKey,
                                                  partnerPublicKeyStr,
                                                );
                                            await widget.apiService.saveLaneKey(
                                              laneId,
                                              partnerId,
                                              encryptedLaneKey,
                                            );
                                          }
                                        }

                                        if (context.mounted) {
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Successfully added member to lane!',
                                              ),
                                            ),
                                          );
                                        }
                                        await _fetchLanes();
                                      } catch (e) {
                                        String msg = e
                                            .toString()
                                            .replaceAll('Exception: ', '')
                                            .replaceAll(
                                              'Failed to invite member: ',
                                              '',
                                            );
                                        if (msg.contains('{') &&
                                            msg.contains('}')) {
                                          try {
                                            final jsonStart = msg.indexOf('{');
                                            final jsonStr = msg.substring(
                                              jsonStart,
                                            );
                                            final decoded = jsonDecode(jsonStr);
                                            if (decoded is Map &&
                                                decoded['error'] != null) {
                                              msg = decoded['error'].toString();
                                            }
                                          } catch (_) {}
                                        }
                                        setSheetState(() {
                                          searchError = msg;
                                        });
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.person_add_alt_1_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Add'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          'Members in this Lane',
                          style: GoogleFonts.gabarito(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (laneId != null)
                          FutureBuilder<List<dynamic>>(
                            future: widget.apiService.getLaneMembers(laneId),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              if (snapshot.hasError ||
                                  !snapshot.hasData ||
                                  snapshot.data!.isEmpty) {
                                return Text(
                                  'Unable to load members',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                );
                              }
                              final members = snapshot.data!;
                              return Column(
                                children: members.map((m) {
                                  final mUserId =
                                      (m['userId'] ?? m['id'] ?? m[r'$id'])
                                          ?.toString();
                                  final isMemberOwner =
                                      mUserId != null &&
                                      mUserId == laneCreatorId;
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor:
                                          colorScheme.primaryContainer,
                                      child: Icon(
                                        Icons.person,
                                        size: 18,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    title: Text(
                                      mUserId == _currentUserId
                                          ? 'You ($mUserId)'
                                          : (mUserId ?? 'Member'),
                                      style: GoogleFonts.gabarito(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMemberOwner
                                            ? colorScheme.primaryContainer
                                            : colorScheme
                                                  .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        isMemberOwner ? 'Owner' : 'Member',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isMemberOwner
                                              ? colorScheme.onPrimaryContainer
                                              : colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        const SizedBox(height: 16),
                        if (!isCreator && laneId != null) ...[
                          const Divider(),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.error,
                                side: BorderSide(color: colorScheme.error),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              icon: const Icon(Icons.exit_to_app_rounded),
                              label: Text(
                                'Leave Memory Lane',
                                style: GoogleFonts.gabarito(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Leave Memory Lane?'),
                                    content: const Text(
                                      'You will no longer have access to this shared lane. The lane and its memories will remain for other members.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: colorScheme.error,
                                          foregroundColor: colorScheme.onError,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Leave'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  Navigator.pop(context);
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                  try {
                                    await widget.apiService.leaveLane(laneId);
                                    await _storage.delete(
                                      key: 'memory_lanes_password_$laneId',
                                    );
                                    await _fetchLanes();
                                    if (mounted) {
                                      setState(
                                        () => _activeLane = _lanes.first,
                                      );
                                      Navigator.pop(context);
                                      _loadMemories();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'You have left the memory lane.',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to leave lane: $e',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (isCreator)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.error,
                                side: BorderSide(color: colorScheme.error),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              icon: const Icon(Icons.delete_forever_rounded),
                              label: Text(
                                'Delete Memory Lane',
                                style: GoogleFonts.gabarito(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Memory Lane?'),
                                    content: const Text(
                                      'Are you sure you want to permanently delete this memory lane? This action cannot be undone, and all shared memories in this lane will be lost forever.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: colorScheme.error,
                                          foregroundColor: colorScheme.onError,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  Navigator.pop(context);
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                  try {
                                    if (laneId != null) {
                                      await widget.apiService.deleteLane(
                                        laneId,
                                      );
                                      await _storage.delete(
                                        key: 'memory_lanes_password_$laneId',
                                      );
                                    }
                                    await _fetchLanes();
                                    if (mounted) {
                                      setState(
                                        () => _activeLane = _lanes.first,
                                      );
                                      Navigator.pop(context);
                                      _loadMemories();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Memory lane deleted successfully.',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to delete lane: $e',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _checkInitialState() async {
    await _setupRsaKeyPair();
    await _fetchLanes();

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
          await prewarmPBKDF2Key(cached);
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
      final laneId = _activeLane?['id']?.toString();
      final response = await widget.apiService.getMemories(
        laneId: laneId,
        length: _pageSize,
        offset: _currentOffset,
      );
      final memories = response['documents'] as List<dynamic>? ?? [];
      _totalMemories = response['total'] ?? 0;

      final drafts = await DraftManager.getDrafts();
      final draftMemories = drafts
          .where((d) => laneId == null)
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

      final activeLaneE2e = _activeLane?['isE2e'] == true;
      final activeKeyString = activeLaneE2e
          ? await _getActiveLaneKey(laneId)
          : null;

      if (activeLaneE2e && activeKeyString != null) {
        bool badPassword = false;

        String decryptField(String text) {
          if (badPassword) return text;
          try {
            if (text.contains(':')) {
              final parts = text.split(':');
              if (parts.length == 2) {
                final iv = encrypt.IV.fromBase64(parts[0]);
                final ciphertext = parts[1];

                // 1. Try PBKDF2 decryption
                try {
                  final key = derivePBKDF2Key(activeKeyString);
                  final encrypter = encrypt.Encrypter(encrypt.AES(key));
                  final decrypted = encrypter.decrypt64(ciphertext, iv: iv);
                  if (decrypted.startsWith('{"') ||
                      decrypted.startsWith('[') ||
                      !decrypted.contains('\x00')) {
                    return decrypted;
                  }
                } catch (_) {}

                // 2. Fallback to legacy decryption
                final key = getLegacyKey(activeKeyString);
                final encrypter = encrypt.Encrypter(encrypt.AES(key));
                return encrypter.decrypt64(ciphertext, iv: iv);
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
          await _storage.delete(key: 'memory_lanes_password_$laneId');
          if (mounted) {
            setState(() {
              _isUnlocked = false;
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
      final laneId = _activeLane?['id']?.toString();
      final response = await widget.apiService.getMemories(
        laneId: laneId,
        length: _pageSize,
        offset: nextOffset,
      );
      final newMemories = response['documents'] as List<dynamic>? ?? [];
      _totalMemories = response['total'] ?? _totalMemories;

      if (mounted) {
        if (newMemories.isEmpty) {
          setState(() => _hasMore = false);
        } else {
          final activeLaneE2e = _activeLane?['isE2e'] == true;
          final activeKeyString = activeLaneE2e
              ? await _getActiveLaneKey(laneId)
              : null;

          if (activeLaneE2e && activeKeyString != null) {
            bool badPassword = false;

            String decryptField(String text) {
              if (badPassword) return text;
              try {
                if (text.contains(':')) {
                  final parts = text.split(':');
                  if (parts.length == 2) {
                    final iv = encrypt.IV.fromBase64(parts[0]);
                    final ciphertext = parts[1];

                    // 1. Try PBKDF2 decryption
                    try {
                      final key = derivePBKDF2Key(activeKeyString);
                      final encrypter = encrypt.Encrypter(encrypt.AES(key));
                      final decrypted = encrypter.decrypt64(ciphertext, iv: iv);
                      if (decrypted.startsWith('{"') ||
                          decrypted.startsWith('[') ||
                          !decrypted.contains('\x00')) {
                        return decrypted;
                      }
                    } catch (_) {}

                    // 2. Fallback to legacy decryption
                    final key = getLegacyKey(activeKeyString);
                    final encrypter = encrypt.Encrypter(encrypt.AES(key));
                    return encrypter.decrypt64(ciphertext, iv: iv);
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
              await _storage.delete(key: 'memory_lanes_password_$laneId');
              setState(() {
                _isUnlocked = false;
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
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                        const Center(child: CircularProgressIndicator()),
                  );
                  await prewarmPBKDF2Key(_unlockPasswordController.text);
                  if (context.mounted) {
                    Navigator.pop(context);
                    await _storage.write(
                      key: 'memory_lanes_password',
                      value: _unlockPasswordController.text,
                    );
                    _unlock();
                  }
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
            : GestureDetector(
                onTap: _showLaneSwitcherBottomSheet,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _activeLane?['name'] ?? 'Memory Lanes',
                      style: GoogleFonts.gabarito(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
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
          if (!_isSearching) ...[
            IconButton(
              icon: Icon(Icons.search_rounded, color: colorScheme.onSurface),
              tooltip: 'Search',
              onPressed: () => setState(() => _isSearching = true),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurface),
              onSelected: (value) async {
                switch (value) {
                  case 'settings':
                    _showLaneSettingsSheet();
                    break;
                  case 'key':
                    final activeKey = await _getActiveLaneKey(
                      _activeLane?['id']?.toString(),
                    );
                    if (activeKey == null) return;
                    if (context.mounted) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Lane Encryption Password'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Save this key securely! If your partner logs in, they will need this key if they do not have a private key backup.',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              SelectableText(
                                activeKey,
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
                    }
                    break;
                  case 'pin':
                    _showPinSetupDialog();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (_activeLane?['id'] != null)
                  const PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.people_outline_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('Lane Settings / Invite'),
                      ],
                    ),
                  ),
                if (_activeLane?['isE2e'] == true)
                  const PopupMenuItem(
                    value: 'key',
                    child: Row(
                      children: [
                        Icon(Icons.key_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('Encryption Password'),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'pin',
                  child: Row(
                    children: [
                      Icon(
                        _pin != null ? Icons.lock : Icons.lock_open,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(_pin != null ? 'Disable PIN' : 'Setup PIN'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoadingMemories
          ? const Center(child: CircularProgressIndicator())
          : _isSearching
          ? _buildSearchResults(context, colorScheme)
          : _memories.isEmpty
          ? _buildEmptyState(context, colorScheme)
          : _isCalendarView
          ? _buildCalendarView(context, colorScheme)
          : _buildListView(context, colorScheme),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreateMemoryPage(
                apiService: widget.apiService,
                e2eEnabled: _activeLane?['isE2e'] == true,
                laneId: _activeLane?['id']?.toString(),
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

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    final isShared = _activeLane?['id'] != null;
    final isE2e = _activeLane?['isE2e'] == true;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primaryContainer,
                      colorScheme.secondaryContainer,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.15),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  isShared
                      ? Icons.people_alt_rounded
                      : Icons.auto_stories_rounded,
                  size: 36,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isShared
                    ? (_activeLane?['name'] ?? 'Shared Memory Lane')
                    : 'Personal',
                textAlign: TextAlign.center,
                style: GoogleFonts.gabarito(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isShared
                    ? 'A secure, private space to document your journeys, save milestones, and build a shared history together in real-time.'
                    : 'Your private sanctuary to record thoughts, reflections, and milestones. Safe, secure, and always accessible.',
                textAlign: TextAlign.center,
                style: GoogleFonts.gabarito(
                  fontSize: 14,
                  height: 1.4,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (isE2e) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.security_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'End-to-End Encrypted',
                        style: GoogleFonts.gabarito(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () async {
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreateMemoryPage(
                        apiService: widget.apiService,
                        e2eEnabled: _activeLane?['isE2e'] == true,
                        laneId: _activeLane?['id']?.toString(),
                      ),
                    ),
                  );
                  if (result == true) {
                    _loadMemories();
                  }
                },
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  'Write First Memory',
                  style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              if (isShared)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _showLaneSettingsSheet,
                  icon: const Icon(Icons.person_add_rounded),
                  label: Text(
                    'Invite Partner / Add Friend',
                    style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
                  ),
                )
              else
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _showLaneSwitcherBottomSheet,
                  icon: const Icon(Icons.people_rounded),
                  label: Text(
                    'Explore Shared Lanes',
                    style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
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
            showDate: true,
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

  String _getDescriptionPreview(String? descriptionText) {
    if (descriptionText == null || descriptionText.isEmpty) return '';
    String desc = descriptionText;
    if (desc.contains('%%LISTENED_TO:')) {
      desc = desc.split('%%LISTENED_TO:')[0].trim();
    }
    try {
      final decoded = jsonDecode(desc);
      if (decoded is List) {
        final buffer = StringBuffer();
        for (var op in decoded) {
          if (op is Map && op.containsKey('insert')) {
            final insert = op['insert'];
            if (insert is String) {
              buffer.write(insert);
            }
          }
        }
        return buffer.toString().trim();
      }
    } catch (_) {}
    return desc.trim();
  }

  Future<void> _confirmAndDeleteMemory(
    BuildContext context,
    dynamic memory,
  ) async {
    final isDraft = memory['isDraft'] == true;
    final id = (memory['\$id'] ?? memory['id'] ?? memory['memoryId'] ?? '')
        .toString();
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) {
        final cs = Theme.of(dCtx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: cs.error),
              const SizedBox(width: 10),
              Text(
                isDraft ? 'Delete draft?' : 'Delete memory?',
                style: GoogleFonts.gabarito(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          content: Text(
            isDraft
                ? 'Are you sure you want to delete this draft? This cannot be undone.'
                : 'Are you sure you want to permanently delete this memory? This cannot be undone.',
            style: GoogleFonts.gabarito(
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                textStyle: GoogleFonts.gabarito(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: cs.errorContainer,
                foregroundColor: cs.error,
                textStyle: GoogleFonts.gabarito(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        if (isDraft) {
          final draft = memory['draftObject'];
          if (draft != null) {
            await DraftManager.deleteDraft(draft.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Draft deleted successfully')),
              );
            }
          }
        } else {
          await widget.apiService.deleteMemory(id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Memory deleted successfully')),
            );
          }
        }
        _loadMemories();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  Widget _buildMemoryCard(
    BuildContext context,
    ColorScheme colorScheme,
    dynamic memory,
    Color color, {
    bool isStackTop = false,
    int count = 1,
    bool showDate = false,
  }) {
    final isDraft = memory['isDraft'] == true;
    final tag = memory['tag'];
    final mood = memory['mood'];
    final cardColor = _getColor(memory['tagColor']);
    final description = memory['description'];
    final files = memory['files'] as List<dynamic>? ?? [];

    final descPreview = _getDescriptionPreview(description);
    final hasFiles = files.isNotEmpty;

    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDraft
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
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
                        e2eEnabled: _activeLane?['isE2e'] == true,
                        draft: memory['draftObject'],
                        laneId: _activeLane?['id']?.toString(),
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
        onLongPress: isStackTop
            ? null
            : () => _confirmAndDeleteMemory(context, memory),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
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
                      style: GoogleFonts.gabarito(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  if (showDate && memory['createdAt'] != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      () {
                        try {
                          final parsedDate = DateTime.parse(
                            memory['createdAt'],
                          );
                          return DateFormat('MMM d, yyyy').format(parsedDate);
                        } catch (_) {
                          return '';
                        }
                      }(),
                      style: GoogleFonts.gabarito(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (isStackTop) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '+${count - 1}',
                        style: GoogleFonts.gabarito(
                          color: colorScheme.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (!_compactView && descPreview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  descPreview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.gabarito(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
              if ((tag != null && tag.toString().isNotEmpty) ||
                  (mood != null && mood.toString().isNotEmpty) ||
                  hasFiles) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (tag != null && tag.toString().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cardColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: cardColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.label_outline_rounded,
                              size: 12,
                              color: cardColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              tag.toString(),
                              style: GoogleFonts.gabarito(
                                fontSize: 11,
                                color: cardColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (mood != null && mood.toString().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              mood.toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Mood',
                              style: GoogleFonts.gabarito(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (hasFiles)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.attach_file_rounded,
                              size: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              files.length.toString(),
                              style: GoogleFonts.gabarito(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
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
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        key: const ValueKey(1),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 200,
            width: 200,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(24),
            child: _showIntroAnimation
                ? Lottie.asset(
                    'assets/anim/memorylanes.json',
                    controller: _introController,
                    onLoaded: _onIntroLoaded,
                    fit: BoxFit.contain,
                  )
                : Lottie.asset('assets/anim/notepad.json', fit: BoxFit.contain),
          ),
          const SizedBox(height: 36),
          Text(
            'Memory Lanes',
            style: GoogleFonts.gabarito(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Capture the beautiful milestones and lessons of your life. Keep them in your private journal, or create Shared Lanes with partners and close friends to walk down memory lane together!',
            textAlign: TextAlign.center,
            style: GoogleFonts.gabarito(
              fontSize: 15,
              height: 1.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          // Features preview
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                _buildIntroFeatureRow(
                  colorScheme,
                  Icons.person_outline_rounded,
                  'Personal Journal',
                  'A private space to record daily reflections and personal milestones.',
                ),
                const SizedBox(height: 12),
                _buildIntroFeatureRow(
                  colorScheme,
                  Icons.people_outline_rounded,
                  'Shared Lanes',
                  'Collaborative memory spaces to build timelines with friends and partners.',
                ),
                const SizedBox(height: 12),
                _buildIntroFeatureRow(
                  colorScheme,
                  Icons.security_rounded,
                  'End-to-End Encryption',
                  'Optional E2E encryption keeps your memories entirely private.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          FilledButton(
            onPressed: () => setState(() => _currentStep = 2),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Next',
                  style: GoogleFonts.gabarito(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroFeatureRow(
    ColorScheme colorScheme,
    IconData icon,
    String title,
    String desc,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: colorScheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.gabarito(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: GoogleFonts.gabarito(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityStep(ColorScheme colorScheme) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        key: const ValueKey(2),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 160,
            width: 160,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(20),
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
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: colorScheme.outlineVariant.withOpacity(0.4),
              ),
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
                        'Standard Encryption',
                        style: GoogleFonts.gabarito(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        'Always active on our cloud',
                        style: GoogleFonts.gabarito(
                          color: colorScheme.primary,
                          fontSize: 12,
                        ),
                      ),
                      secondary: Icon(
                        Icons.security,
                        color: colorScheme.primary,
                      ),
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
                                color: colorScheme.outlineVariant.withOpacity(
                                  0.5,
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
                                  final wordListStr =
                                      await DefaultAssetBundle.of(
                                        context,
                                      ).loadString(
                                        'assets/eff_large_wordlist.txt',
                                      );
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
                            'If you lose this password, your memories are gone forever and no one can recover your data.',
                            isError: true,
                          ),
                          _buildWarningItem(
                            context,
                            'Memories will be encrypted on your device before being saved to our servers.',
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isSettingUp
                      ? null
                      : () async {
                          if (_e2eEnabled) {
                            if (_passwordController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please set a password.'),
                                ),
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
                                    t ??= Timer.periodic(
                                      const Duration(seconds: 1),
                                      (timer) {
                                        if (countdown > 0) {
                                          setStateDialog(() => countdown--);
                                        } else {
                                          timer.cancel();
                                        }
                                      },
                                    );
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
                                                  Navigator.of(
                                                    context,
                                                  ).pop(true);
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
                            await widget.apiService.setupMemoryLanes(
                              e2e: _e2eEnabled,
                            );

                            if (_e2eEnabled) {
                              await prewarmPBKDF2Key(_passwordController.text);
                              await _storage.write(
                                key: 'memory_lanes_password',
                                value: _passwordController.text,
                              );
                              _unlockPasswordController.text =
                                  _passwordController.text;
                            }

                            setState(() {
                              _localE2eStatus = _e2eEnabled ? 'true' : 'false';
                            });
                            _unlock();
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Setup failed: $e')),
                            );
                          } finally {
                            if (mounted) setState(() => _isSettingUp = false);
                          }
                        },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54),
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
              ),
            ],
          ),
        ],
      ),
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
