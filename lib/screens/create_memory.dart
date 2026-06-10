import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;
import 'package:uuid/uuid.dart';
import '../api_service.dart';
import '../utils/draft_utils.dart';
import '../utils/crypto_utils.dart';
import 'package:http/http.dart' as http;

class CreateMemoryPage extends StatefulWidget {
  final ApiService apiService;
  final bool e2eEnabled;
  final DraftMemory? draft;
  final Map<String, dynamic>? existingMemory;

  const CreateMemoryPage({
    super.key,
    required this.apiService,
    this.e2eEnabled = false,
    this.draft,
    this.existingMemory,
  });

  @override
  State<CreateMemoryPage> createState() => _CreateMemoryPageState();
}

class _CreateMemoryPageState extends State<CreateMemoryPage> {
  final _titleController = TextEditingController();
  final _tagController = TextEditingController();
  late quill.QuillController _quillController;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();

  bool _isPublic = false;
  bool _isSaving = false;
  String _selectedColor = 'blue';
  String? _selectedMood;
  DateTime _selectedDate = DateTime.now();
  bool _toolbarExpanded = false;
  bool _hasUnsavedChanges = false;
  bool _skipSaveDraft = false;
  Timer? _autoSaveTimer;
  String? _currentDraftId;
  List<String> _existingFileIds = [];

  List<String> _recentMoods = [];

  static const List<String> _allowedMoods = [
    '😀',
    '😢',
    '😡',
    '🥳',
    '😴',
    '🔥',
    '💔',
  ];

  final List<File> _mediaFiles = [];
  final List<String> _mediaTypes = [];
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  int? _playingIndex;
  Map<String, dynamic>? _selectedSong;
  Duration _musicDuration = Duration.zero;
  Duration _musicPosition = Duration.zero;
  bool _isPlayingMusic = false;
  String? _playingMusicUrl;
  bool _soundtrackSeeking = true;

  final List<Map<String, dynamic>> _colors = [
    {'name': 'blue', 'color': Colors.blue},
    {'name': 'red', 'color': Colors.red},
    {'name': 'green', 'color': Colors.green},
    {'name': 'orange', 'color': Colors.orange},
    {'name': 'purple', 'color': Colors.purple},
    {'name': 'pink', 'color': Colors.pink},
    {'name': 'teal', 'color': Colors.teal},
  ];

  @override
  void initState() {
    super.initState();
    _loadSeekingSetting();
    _loadRecentMoods();
    _quillController = quill.QuillController.basic();
    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) {
        setState(() {
          _musicDuration = d;
        });
      }
    });
    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) {
        setState(() {
          _musicPosition = p;
        });
      }
    });
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlayingMusic = state == PlayerState.playing;
        });
      }
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingIndex = null;
          _isPlayingMusic = false;
          _musicPosition = Duration.zero;
        });
      }
    });

    if (widget.existingMemory != null) {
      _currentDraftId =
          (widget.existingMemory![r'$id'] ??
                  widget.existingMemory!['id'] ??
                  widget.existingMemory!['memoryId'])
              ?.toString() ??
          const Uuid().v4();
      _titleController.text = widget.existingMemory!['name'] ?? '';
      _tagController.text = (widget.existingMemory!['tag'] ?? '').toString();
      _selectedColor = widget.existingMemory!['tagColor'] ?? 'blue';
      _selectedMood = widget.existingMemory!['mood'];
      _isPublic = widget.existingMemory!['public'] == true;
      if (widget.existingMemory!['createdAt'] != null) {
        try {
          _selectedDate = DateTime.parse(widget.existingMemory!['createdAt']);
        } catch (_) {}
      }
      String desc = widget.existingMemory!['description'] ?? '';
      if (desc.contains('%%LISTENED_TO:')) {
        final parts = desc.split('%%LISTENED_TO:');
        desc = parts[0].trim();
        final songPart = parts[1].replaceAll('%%', '').trim();
        try {
          _selectedSong = jsonDecode(songPart);
        } catch (_) {}
      }
      try {
        final json = jsonDecode(desc);
        _quillController = quill.QuillController(
          document: quill.Document.fromJson(json),
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (e) {
        _quillController = quill.QuillController(
          document: quill.Document()..insert(0, desc),
          selection: const TextSelection.collapsed(offset: 0),
        );
      }
      if (widget.existingMemory!['files'] is List) {
        _existingFileIds = List<String>.from(widget.existingMemory!['files']);
      }
    } else if (widget.draft != null) {
      _currentDraftId = widget.draft!.id;
      _restoreDraft(widget.draft!);
    } else {
      _currentDraftId = const Uuid().v4();
    }

    _titleController.addListener(_onContentChanged);
    _tagController.addListener(_onContentChanged);
    _quillController.document.changes.listen((event) {
      _onContentChanged();
    });
  }

  Future<void> _loadSeekingSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _soundtrackSeeking = prefs.getBool('soundtrack_seeking') ?? true;
        });
      }
    } catch (_) {}
  }

  void _onContentChanged() {
    if (!_hasUnsavedChanges) {
      _hasUnsavedChanges = true;
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), _saveDraft);
  }

  void _restoreDraft(DraftMemory draft) {
    setState(() {
      _titleController.text = draft.title;
      _tagController.text = draft.tag ?? '';
      _selectedColor = draft.tagColor ?? 'blue';
      _selectedMood = draft.mood;
      String desc = draft.description;
      if (desc.contains('%%LISTENED_TO:')) {
        final parts = desc.split('%%LISTENED_TO:');
        desc = parts[0].trim();
        final songPart = parts[1].replaceAll('%%', '').trim();
        try {
          _selectedSong = jsonDecode(songPart);
        } catch (_) {}
      }
      if (desc.isNotEmpty) {
        try {
          final delta = jsonDecode(desc);
          final doc = quill.Document.fromJson(delta);

          final oldController = _quillController;
          _quillController = quill.QuillController(
            document: doc,
            selection: const TextSelection.collapsed(offset: 0),
          );
          oldController.dispose();
        } catch (_) {}
      }

      _mediaFiles.clear();
      _mediaTypes.clear();
      for (int i = 0; i < draft.mediaPaths.length; i++) {
        final path = draft.mediaPaths[i];
        final type = i < draft.mediaTypes.length
            ? draft.mediaTypes[i]
            : 'image';

        final file = File(path);
        if (file.existsSync()) {
          _mediaFiles.add(file);
          _mediaTypes.add(type);
        }
      }
    });
  }

  Future<void> _saveDraft() async {
    if (_skipSaveDraft || widget.existingMemory != null) return;

    final prefs = await SharedPreferences.getInstance();
    final saveDrafts = prefs.getBool('save_drafts') ?? true;
    if (!saveDrafts) return;

    if (_titleController.text.isEmpty &&
        _tagController.text.isEmpty &&
        _quillController.document.isEmpty() &&
        _mediaFiles.isEmpty) {
      return;
    }

    _currentDraftId ??= const Uuid().v4();

    String descStr = jsonEncode(_quillController.document.toDelta().toJson());
    if (_selectedSong != null) {
      descStr += '\n\n%%LISTENED_TO:${jsonEncode(_selectedSong)}%%';
    }

    final draft = DraftMemory(
      id: _currentDraftId!,
      title: _titleController.text,
      tag: _tagController.text,
      tagColor: _selectedColor,
      mood: _selectedMood,
      description: descStr,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      mediaPaths: _mediaFiles.map((f) => f.path).toList(),
      mediaTypes: _mediaTypes,
    );

    await DraftManager.saveDraft(draft);
  }

  Future<void> _deleteCurrentDraft() async {
    _skipSaveDraft = true;
    if (_currentDraftId != null) {
      await DraftManager.deleteDraft(_currentDraftId!);
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _saveDraft();
    _titleController.dispose();
    _tagController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  bool _isAttributeActive(quill.Attribute attribute) {
    final style = _quillController.getSelectionStyle();
    return style.attributes.containsKey(attribute.key) &&
        style.attributes[attribute.key]!.value == attribute.value;
  }

  void _toggleAttribute(quill.Attribute attribute) {
    final isActive = _isAttributeActive(attribute);
    if (isActive) {
      _quillController.formatSelection(quill.Attribute.clone(attribute, null));
    } else {
      _quillController.formatSelection(attribute);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final file = File(picked.path);

      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.avif';

      try {
        final originalBytes = await file.readAsBytes();
        final avifBytes = await encodeAvif(
          originalBytes,
          speed: 8,
          minQuantizer: 20,
          maxQuantizer: 35,
        );
        final resultFile = File(targetPath);
        await resultFile.writeAsBytes(avifBytes);

        setState(() {
          _mediaFiles.add(resultFile);
          _mediaTypes.add('image');
        });
      } catch (e) {
        _showError('Failed to encode image to AVIF: $e');
      }
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      final file = File(picked.path);
      final dir = await getTemporaryDirectory();
      final tempFile = File(
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.hevc',
      );
      await file.copy(tempFile.path);
      setState(() {
        _mediaFiles.add(tempFile);
        _mediaTypes.add('video');
      });
    }
  }

  Future<void> _showRecordingDialog() async {
    final file = await showDialog<File>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const RecordingDialog(),
    );

    if (file != null) {
      setState(() {
        _mediaFiles.add(file);
        _mediaTypes.add('audio');
      });
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      _showError('Please enter a title');
      return;
    }

    setState(() => _isSaving = true);
    try {
      String? keyString;
      if (widget.e2eEnabled && !_isPublic) {
        const storage = FlutterSecureStorage();
        keyString = await storage.read(key: 'memory_lanes_password');
      }

      List<String> fileIds = List.from(_existingFileIds);
      for (int i = 0; i < _mediaFiles.length; i++) {
        final file = _mediaFiles[i];
        final type = _mediaTypes[i];
        final ext = file.path.split('.').last;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        String name = '${type}_$timestamp.$ext';
        name = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '');

        File fileToUpload = file;
        File? tempEncryptedFile;

        if (keyString != null && keyString.isNotEmpty) {
          final key = derivePBKDF2Key(keyString);
          final encrypter = encrypt.Encrypter(encrypt.AES(key));
          final iv = encrypt.IV.fromLength(16);
          final fileBytes = await file.readAsBytes();
          final encrypted = encrypter.encryptBytes(fileBytes, iv: iv);

          final dir = await getTemporaryDirectory();
          tempEncryptedFile = File(
            '${dir.path}/enc_${DateTime.now().millisecondsSinceEpoch}_$name',
          );
          final writer = await tempEncryptedFile.open(mode: FileMode.write);
          await writer.writeFrom(iv.bytes);
          await writer.writeFrom(encrypted.bytes);
          await writer.close();

          fileToUpload = tempEncryptedFile;
        }

        final id = await widget.apiService.uploadMemoryFile(
          fileToUpload,
          name,
          isPublic: _isPublic,
        );
        fileIds.add(id);

        if (tempEncryptedFile != null) {
          try {
            await tempEncryptedFile.delete();
          } catch (_) {}
        }
      }

      final delta = _quillController.document.toDelta();
      String description = jsonEncode(delta.toJson());
      if (_selectedSong != null) {
        description += '\n\n%%LISTENED_TO:${jsonEncode(_selectedSong)}%%';
      }

      String? name = _titleController.text.trim();
      String? tag = _tagController.text.trim().isNotEmpty
          ? _tagController.text.trim()
          : null;
      String? tagColor = _selectedColor;
      String? mood = _selectedMood;

      if (keyString != null && keyString.isNotEmpty) {
        final key = derivePBKDF2Key(keyString);
        final encrypter = encrypt.Encrypter(encrypt.AES(key));

        String encryptField(String text) {
          final iv = encrypt.IV.fromLength(16);
          final encrypted = encrypter.encrypt(text, iv: iv);
          return '${iv.base64}:${encrypted.base64}';
        }

        description = encryptField(description);
        name = encryptField(name);
        if (tag != null) tag = encryptField(tag);
        tagColor = encryptField(tagColor);
        if (mood != null) mood = encryptField(mood);
      }

      if (widget.existingMemory != null) {
        final existingId =
            (widget.existingMemory![r'$id'] ??
                    widget.existingMemory!['id'] ??
                    widget.existingMemory!['memoryId'])
                .toString();
        await widget.apiService.editMemory(
          existingId,
          name: name,
          description: description,
          isPublic: _isPublic,
          tag: tag,
          tagColor: tagColor,
          mood: mood,
          createdAt: _selectedDate.toIso8601String(),
          files: fileIds.isNotEmpty ? fileIds : null,
        );
      } else {
        await widget.apiService.createMemory(
          name: name,
          description: description,
          isPublic: _isPublic,
          tag: tag,
          tagColor: tagColor,
          mood: mood,
          createdAt: _selectedDate.toIso8601String(),
          files: fileIds.isNotEmpty ? fileIds : null,
        );
      }

      await _deleteCurrentDraft();

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showError('Failed to save memory: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Add Tag'),
              onTap: () {
                Navigator.pop(context);
                _showTagDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Add Image'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Add Video'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.mic_none),
              title: const Text('Record Audio'),
              onTap: () {
                Navigator.pop(context);
                _showRecordingDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMusicSearchBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MusicSearchBottomSheet(
        onSongSelected: (song) {
          setState(() {
            _selectedSong = {
              'trackName': song['trackName'],
              'artistName': song['artistName'],
              'artworkUrl100': song['artworkUrl100'],
              'previewUrl': song['previewUrl'],
              'trackViewUrl': song['trackViewUrl'],
            };
          });
        },
      ),
    );
  }

  final Map<String, String> _resolvedUrls = {};

  Future<void> _togglePlaySelectedMusic(
    String previewUrl,
    String? trackViewUrl,
  ) async {
    String playUrl = previewUrl;
    if (trackViewUrl != null && trackViewUrl.isNotEmpty) {
      if (_resolvedUrls.containsKey(trackViewUrl)) {
        playUrl = _resolvedUrls[trackViewUrl]!;
      } else {
        try {
          final response = await http
              .get(Uri.parse(trackViewUrl))
              .timeout(const Duration(seconds: 3));
          if (response.statusCode == 200) {
            final body = response.body;
            final regExp = RegExp(r'https://[^\s"]+?\.plus\.aac\.ep\.m4a');
            final match = regExp.firstMatch(body);
            if (match != null) {
              playUrl = match.group(0)!;
            }
          }
        } catch (_) {}
        _resolvedUrls[trackViewUrl] = playUrl;
      }
    }

    if (_playingMusicUrl == playUrl && _isPlayingMusic) {
      await _audioPlayer.pause();
    } else if (_playingMusicUrl == playUrl &&
        !_isPlayingMusic &&
        _musicPosition > Duration.zero) {
      await _audioPlayer.resume();
    } else {
      await _audioPlayer.stop();
      setState(() {
        _playingMusicUrl = playUrl;
        _playingIndex = null;
      });
      await _audioPlayer.play(UrlSource(playUrl));
    }
  }

  void _removeSelectedMusic() {
    setState(() {
      _selectedSong = null;
      _playingMusicUrl = null;
      _isPlayingMusic = false;
    });
    _audioPlayer.stop();
  }

  String _formatMusicDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildSelectedMusicCard(ColorScheme colorScheme) {
    if (_selectedSong == null) return const SizedBox.shrink();

    final trackName = _selectedSong!['trackName'] ?? 'Unknown Track';
    final artistName = _selectedSong!['artistName'] ?? 'Unknown Artist';
    final artworkUrl = _selectedSong!['artworkUrl100'] ?? '';
    final previewUrl = _selectedSong!['previewUrl'] ?? '';
    final trackViewUrl = _selectedSong!['trackViewUrl'] ?? '';

    final isCurrentPlaying =
        _playingMusicUrl == previewUrl ||
        (_resolvedUrls[trackViewUrl] != null &&
            _playingMusicUrl == _resolvedUrls[trackViewUrl]);
    final isPlaying = isCurrentPlaying && _isPlayingMusic;

    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.music_note_rounded,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'WHAT I\'VE BEEN LISTENING TO',
                style: GoogleFonts.gabarito(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: artworkUrl.isNotEmpty
                    ? Image.network(
                        artworkUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 48,
                          height: 48,
                          color: colorScheme.surfaceContainer,
                          child: Icon(
                            Icons.music_note_rounded,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        color: colorScheme.surfaceContainer,
                        child: Icon(
                          Icons.music_note_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trackName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.gabarito(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (previewUrl.isNotEmpty)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isPlaying
                          ? colorScheme.primary.withValues(alpha: 0.5)
                          : colorScheme.outlineVariant,
                      width: 1.5,
                    ),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 22,
                      color: isPlaying
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () =>
                        _togglePlaySelectedMusic(previewUrl, trackViewUrl),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 22),
                color: colorScheme.error,
                onPressed: _removeSelectedMusic,
              ),
            ],
          ),
          if (isCurrentPlaying) ...[
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: colorScheme.secondaryContainer,
                thumbColor: colorScheme.primary,
                thumbShape: _soundtrackSeeking
                    ? const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                        pressedElevation: 0,
                      )
                    : const RoundSliderThumbShape(
                        enabledThumbRadius: 0,
                        disabledThumbRadius: 0,
                        pressedElevation: 0,
                      ),
                overlayColor: colorScheme.primary.withValues(alpha: 0.08),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                trackShape: const RoundedRectSliderTrackShape(),
                showValueIndicator: ShowValueIndicator.never,
                padding: EdgeInsets.zero,
              ),
              child: SizedBox(
                height: 24,
                child: Slider(
                  value: _musicPosition.inMilliseconds.toDouble().clamp(
                    0.0,
                    _musicDuration.inMilliseconds.toDouble(),
                  ),
                  max: _musicDuration.inMilliseconds > 0
                      ? _musicDuration.inMilliseconds.toDouble()
                      : 1.0,
                  onChanged: _soundtrackSeeking
                      ? (val) {
                          _audioPlayer.seek(
                            Duration(milliseconds: val.toInt()),
                          );
                        }
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatMusicDuration(_musicPosition),
                  style: GoogleFonts.gabarito(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  _formatMusicDuration(_musicDuration),
                  style: GoogleFonts.gabarito(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showTagDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              'Add Tag',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _tagController,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Tag Name',
                    labelStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _colors.map((c) {
                    final isSelected = _selectedColor == c['name'];
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() => _selectedColor = c['name']);
                        setState(() {});
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c['color'],
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.black, width: 2)
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadRecentMoods() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentMoods =
          prefs.getStringList('recent_moods') ?? _allowedMoods.take(7).toList();
    });
  }

  Future<void> _selectMood(String mood) async {
    setState(() => _selectedMood = mood);

    final prefs = await SharedPreferences.getInstance();
    List<String> recents =
        prefs.getStringList('recent_moods') ?? _allowedMoods.take(7).toList();

    recents.remove(mood);
    recents.insert(0, mood);

    if (recents.length > 7) {
      recents = recents.sublist(0, 7);
    }

    await prefs.setStringList('recent_moods', recents);
    setState(() => _recentMoods = recents);
  }

  void _showFullEmojiPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: emoji_picker.EmojiPicker(
          onEmojiSelected: (category, emoji) {
            Navigator.pop(context);
            _selectMood(emoji.emoji);
          },
          config: const emoji_picker.Config(
            checkPlatformCompatibility: true,
            emojiViewConfig: emoji_picker.EmojiViewConfig(columns: 7),
          ),
        ),
      ),
    );
  }

  void _showMoodPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How are you feeling?',
                style: GoogleFonts.gabarito(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: [
                  ..._recentMoods.map((mood) {
                    final isSelected = _selectedMood == mood;
                    return GestureDetector(
                      onTap: () {
                        _selectMood(mood);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: Text(mood, style: const TextStyle(fontSize: 32)),
                      ),
                    );
                  }),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _showFullEmojiPicker();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add_reaction_outlined,
                        size: 32,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop &&
            _hasUnsavedChanges &&
            !_skipSaveDraft &&
            widget.existingMemory == null) {
          await _saveDraft();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Memory saved as draft'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Memory',
            style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
          ),
          bottom: widget.draft != null
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(24.0),
                  child: Container(
                    color: colorScheme.secondaryContainer,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Center(
                      child: Text(
                        'Editing Draft',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                )
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.music_note_rounded),
              tooltip: 'What have you been listening to?',
              onPressed: _showMusicSearchBottomSheet,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Media/Tag',
              onPressed: _showAddMenu,
            ),
            IconButton(
              icon: Icon(
                _isPublic ? Icons.public : Icons.public_off,
                color: _isPublic ? colorScheme.primary : null,
              ),
              tooltip: 'Toggle Public',
              onPressed: () async {
                if (!_isPublic) {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        'Make Public?',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      content: Text(
                        'This memory will be visible to everyone if you have an Aura Page. Are you sure?',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Make Public'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    setState(() => _isPublic = true);
                  }
                } else {
                  setState(() => _isPublic = false);
                }
              },
            ),
            if (widget.draft != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete Draft',
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        'Delete Draft?',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      content: Text(
                        'This action cannot be undone.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      actions: [
                        TextButton(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.pop(context, false),
                        ),
                        TextButton(
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                          onPressed: () => Navigator.pop(context, true),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _deleteCurrentDraft();
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  }
                },
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Save',
                      style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleController,
                      style: GoogleFonts.gabarito(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Add title',
                        hintStyle: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        border: InputBorder.none,
                      ),
                    ),

                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2100),
                        );

                        if (date == null) return;
                        if (!context.mounted) return;

                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_selectedDate),
                        );

                        if (time != null && mounted) {
                          setState(() {
                            _selectedDate = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            );
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat(
                                'MMM d, yyyy h:mm a',
                              ).format(_selectedDate),
                              style: GoogleFonts.gabarito(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_tagController.text.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              _colors.firstWhere(
                                    (c) => c['name'] == _selectedColor,
                                    orElse: () => _colors[0],
                                  )['color']
                                  as Color,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _tagController.text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _tagController.clear();
                                  _selectedColor = 'blue';
                                });
                              },
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_existingFileIds.isNotEmpty ||
                        _mediaFiles.isNotEmpty) ...[
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              _existingFileIds.length + _mediaFiles.length,
                          itemBuilder: (context, index) {
                            if (index < _existingFileIds.length) {
                              final fileId = _existingFileIds[index];
                              return _ExistingMediaPreview(
                                key: ValueKey('existing_$fileId'),
                                fileId: fileId,
                                apiService: widget.apiService,
                                onDelete: () {
                                  setState(() {
                                    _existingFileIds.removeAt(index);
                                    _hasUnsavedChanges = true;
                                  });
                                },
                              );
                            } else {
                              final localIndex =
                                  index - _existingFileIds.length;
                              final file = _mediaFiles[localIndex];
                              final type = _mediaTypes[localIndex];
                              return Stack(
                                children: [
                                  Container(
                                    width: 100,
                                    margin: const EdgeInsets.only(right: 12),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 80,
                                          width: 100,
                                          decoration: BoxDecoration(
                                            color: colorScheme
                                                .surfaceContainerHigh,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: colorScheme.outlineVariant,
                                            ),
                                          ),
                                          child: type == 'image'
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(11),
                                                  child: AvifImage.file(
                                                    file,
                                                    fit: BoxFit.cover,
                                                    width: 100,
                                                    height: 80,
                                                  ),
                                                )
                                              : Center(
                                                  child: type == 'audio'
                                                      ? IconButton(
                                                          icon: Icon(
                                                            _playingIndex ==
                                                                    index
                                                                ? Icons.stop
                                                                : Icons
                                                                      .play_arrow,
                                                            color: colorScheme
                                                                .onSurface,
                                                            size: 32,
                                                          ),
                                                          onPressed: () async {
                                                            if (_playingIndex ==
                                                                index) {
                                                              await _audioPlayer
                                                                  .stop();
                                                              setState(
                                                                () =>
                                                                    _playingIndex =
                                                                        null,
                                                              );
                                                            } else {
                                                              await _audioPlayer
                                                                  .stop();
                                                              await _audioPlayer
                                                                  .play(
                                                                    DeviceFileSource(
                                                                      file.path,
                                                                    ),
                                                                  );
                                                              setState(
                                                                () =>
                                                                    _playingIndex =
                                                                        index,
                                                              );
                                                            }
                                                          },
                                                        )
                                                      : Icon(
                                                          Icons.videocam,
                                                          color: colorScheme
                                                              .onSurface,
                                                          size: 32,
                                                        ),
                                                ),
                                        ),
                                        if (type == 'audio')
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              'Voice note',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    top: -4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _mediaFiles.removeAt(localIndex);
                                          _mediaTypes.removeAt(localIndex);
                                          _playingIndex = null;
                                          _hasUnsavedChanges = true;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surface,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: colorScheme.outlineVariant,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      constraints: const BoxConstraints(minHeight: 300),
                      child: DefaultTextStyle(
                        style: GoogleFonts.gabarito(
                          color: colorScheme.onSurface,
                          fontSize: 16,
                        ),
                        child: quill.QuillEditor.basic(
                          controller: _quillController,
                          focusNode: _editorFocusNode,
                          scrollController: _editorScrollController,
                          config: quill.QuillEditorConfig(
                            placeholder: 'What\'s on your mind?',
                            padding: const EdgeInsets.all(0),
                            autoFocus: false,
                            expands: false,
                          ),
                        ),
                      ),
                    ),
                    _buildSelectedMusicCard(colorScheme),

                    const SizedBox(height: 16),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: GestureDetector(
                  onTap: _showMoodPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_reaction_outlined,
                          color: _selectedMood != null
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedMood != null
                              ? 'Mood: $_selectedMood'
                              : 'Add Mood',
                          style: GoogleFonts.gabarito(
                            fontWeight: FontWeight.w600,
                            color: _selectedMood != null
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (_selectedMood != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => _selectedMood = null),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: SafeArea(
                top: false,
                child: ListenableBuilder(
                  listenable: _quillController,
                  builder: (context, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Undo',
                              icon: const Icon(Icons.undo),
                              onPressed: () => _quillController.undo(),
                            ),
                            IconButton(
                              tooltip: 'Redo',
                              icon: const Icon(Icons.redo),
                              onPressed: () => _quillController.redo(),
                            ),
                            const VerticalDivider(width: 8),
                            IconButton(
                              tooltip: 'Bold',
                              icon: Icon(
                                Icons.format_bold,
                                color: _isAttributeActive(quill.Attribute.bold)
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                              onPressed: () =>
                                  _toggleAttribute(quill.Attribute.bold),
                            ),
                            IconButton(
                              tooltip: 'Italic',
                              icon: Icon(
                                Icons.format_italic,
                                color:
                                    _isAttributeActive(quill.Attribute.italic)
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                              onPressed: () =>
                                  _toggleAttribute(quill.Attribute.italic),
                            ),
                            IconButton(
                              tooltip: 'Underline',
                              icon: Icon(
                                Icons.format_underlined,
                                color:
                                    _isAttributeActive(
                                      quill.Attribute.underline,
                                    )
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                              onPressed: () =>
                                  _toggleAttribute(quill.Attribute.underline),
                            ),
                            IconButton(
                              tooltip: 'Strikethrough',
                              icon: Icon(
                                Icons.format_strikethrough,
                                color:
                                    _isAttributeActive(
                                      quill.Attribute.strikeThrough,
                                    )
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                              onPressed: () => _toggleAttribute(
                                quill.Attribute.strikeThrough,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Link',
                              icon: Icon(
                                Icons.link,
                                color: _isAttributeActive(quill.Attribute.link)
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                              onPressed: () async {
                                final textController = TextEditingController();
                                final urlController = TextEditingController();
                                final hasSelection =
                                    !_quillController.selection.isCollapsed &&
                                    _quillController.selection.isValid;

                                if (hasSelection) {
                                  textController.text = _quillController
                                      .document
                                      .getPlainText(
                                        _quillController.selection.start,
                                        _quillController.selection.end -
                                            _quillController.selection.start,
                                      );
                                }

                                final result =
                                    await showDialog<Map<String, String>>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(
                                          'Insert Link',
                                          style: TextStyle(
                                            color: Theme.of(
                                              ctx,
                                            ).colorScheme.onSurface,
                                          ),
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (!hasSelection)
                                              TextField(
                                                controller: textController,
                                                style: TextStyle(
                                                  color: Theme.of(
                                                    ctx,
                                                  ).colorScheme.onSurface,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Text',
                                                      hintText: '',
                                                    ),
                                              ),
                                            TextField(
                                              controller: urlController,
                                              style: TextStyle(
                                                color: Theme.of(
                                                  ctx,
                                                ).colorScheme.onSurface,
                                              ),
                                              decoration: const InputDecoration(
                                                labelText: 'URL',
                                                hintText: 'aurachieve.com',
                                              ),
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, {
                                                  'text': textController.text,
                                                  'url': urlController.text,
                                                }),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );

                                if (result != null &&
                                    result['url']!.isNotEmpty) {
                                  final url = result['url']!;
                                  final text = result['text'] ?? url;

                                  if (hasSelection) {
                                    _quillController.formatSelection(
                                      quill.LinkAttribute(url),
                                    );
                                  } else {
                                    final index =
                                        _quillController.selection.baseOffset;
                                    _quillController.document.insert(
                                      index,
                                      text,
                                    );
                                    _quillController.formatText(
                                      index,
                                      text.length,
                                      quill.LinkAttribute(url),
                                    );
                                  }
                                }
                              },
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: _toolbarExpanded ? 'Collapse' : 'More',
                              icon: Icon(
                                _toolbarExpanded
                                    ? Icons.expand_less
                                    : Icons.more_horiz,
                              ),
                              onPressed: () => setState(
                                () => _toolbarExpanded = !_toolbarExpanded,
                              ),
                            ),
                          ],
                        ),
                        if (_toolbarExpanded)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildMediaButton(
                                      Icons.format_quote,
                                      'Quote',
                                      () => _toggleAttribute(
                                        quill.Attribute.blockQuote,
                                      ),
                                      color:
                                          _isAttributeActive(
                                            quill.Attribute.blockQuote,
                                          )
                                          ? colorScheme.primary
                                          : null,
                                    ),
                                    _buildMediaButton(
                                      Icons.list,
                                      'Bullet',
                                      () =>
                                          _toggleAttribute(quill.Attribute.ul),
                                      color:
                                          _isAttributeActive(quill.Attribute.ul)
                                          ? colorScheme.primary
                                          : null,
                                    ),
                                    _buildMediaButton(
                                      Icons.format_list_numbered,
                                      'Number',
                                      () =>
                                          _toggleAttribute(quill.Attribute.ol),
                                      color:
                                          _isAttributeActive(quill.Attribute.ol)
                                          ? colorScheme.primary
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaButton(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Icon(icon, color: color ?? Theme.of(context).colorScheme.onSurface),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color ?? Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecordingDialog extends StatefulWidget {
  const RecordingDialog({super.key});

  @override
  State<RecordingDialog> createState() => _RecordingDialogState();
}

class _RecordingDialogState extends State<RecordingDialog> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isPaused = false;
  int _seconds = 0;
  Timer? _timer;
  String? _path;

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_isRecording) {
      _audioRecorder.stop();
    }
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final dir = await getTemporaryDirectory();

      _path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.opus';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.opus),
        path: _path!,
      );

      setState(() {
        _isRecording = true;
      });
      _startTimer();
    } else {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _seconds++;
      });
      if (_seconds >= 300) {
        _stopRecording();
      }
    });
  }

  void _pauseRecording() async {
    if (_isPaused) {
      await _audioRecorder.resume();
      _startTimer();
    } else {
      await _audioRecorder.pause();
      _timer?.cancel();
    }
    setState(() {
      _isPaused = !_isPaused;
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _audioRecorder.stop();
    if (mounted) {
      Navigator.pop(context, path != null ? File(path) : null);
    }
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        'Recording Audio',
        style: TextStyle(color: colorScheme.onSurface),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: _seconds / 300,
                  strokeWidth: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _seconds >= 270 ? Colors.red : colorScheme.primary,
                  ),
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _isPaused
                      ? colorScheme.surfaceContainerHighest
                      : Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mic,
                  size: 32,
                  color: _isPaused ? colorScheme.onSurfaceVariant : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            _formatDuration(_seconds),
            style: GoogleFonts.gabarito(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isPaused ? 'Paused' : 'Recording...',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        IconButton.filledTonal(
          onPressed: () {
            _timer?.cancel();
            _audioRecorder.stop();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.delete),
          tooltip: 'Discard',
        ),
        IconButton.filledTonal(
          onPressed: _pauseRecording,
          icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
          tooltip: _isPaused ? 'Resume' : 'Pause',
        ),
        IconButton.filled(
          onPressed: _stopRecording,
          icon: const Icon(Icons.check),
          tooltip: 'Save',
        ),
      ],
      actionsAlignment: MainAxisAlignment.spaceEvenly,
    );
  }
}

class MusicSearchBottomSheet extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onSongSelected;
  const MusicSearchBottomSheet({super.key, required this.onSongSelected});

  @override
  State<MusicSearchBottomSheet> createState() => _MusicSearchBottomSheetState();
}

class _MusicSearchBottomSheetState extends State<MusicSearchBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  final AudioPlayer _musicPlayer = AudioPlayer();
  List<dynamic> _songs = [];
  bool _isLoading = false;
  String? _playingPreviewUrl;
  PlayerState _playerState = PlayerState.stopped;
  Timer? _debounce;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  final Map<String, String> _resolvedUrls = {};
  bool _soundtrackSeeking = true;

  @override
  void initState() {
    super.initState();
    _loadSeekingSetting();
    _musicPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _playerState = state;
        });
      }
    });
    _musicPlayer.onDurationChanged.listen((d) {
      if (mounted) {
        setState(() {
          _duration = d;
        });
      }
    });
    _musicPlayer.onPositionChanged.listen((p) {
      if (mounted) {
        setState(() {
          _position = p;
        });
      }
    });
    _musicPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingPreviewUrl = null;
          _playerState = PlayerState.stopped;
          _position = Duration.zero;
        });
      }
    });
  }

  Future<void> _loadSeekingSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _soundtrackSeeking = prefs.getBool('soundtrack_seeking') ?? true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _musicPlayer.stop();
    _musicPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isNotEmpty) {
        _searchSongs(query.trim());
      }
    });
  }

  Future<void> _searchSongs(String query) async {
    setState(() {
      _isLoading = true;
      _songs = [];
    });

    try {
      final url = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&limit=25',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _songs = data['results'] ?? [];
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Server returned status code ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to search music: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _togglePlay(String previewUrl, String? trackViewUrl) async {
    String playUrl = previewUrl;
    if (trackViewUrl != null && trackViewUrl.isNotEmpty) {
      if (_resolvedUrls.containsKey(trackViewUrl)) {
        playUrl = _resolvedUrls[trackViewUrl]!;
      } else {
        try {
          final response = await http
              .get(Uri.parse(trackViewUrl))
              .timeout(const Duration(seconds: 3));
          if (response.statusCode == 200) {
            final body = response.body;
            final regExp = RegExp(r'https://[^\s"]+?\.plus\.aac\.ep\.m4a');
            final match = regExp.firstMatch(body);
            if (match != null) {
              playUrl = match.group(0)!;
            }
          }
        } catch (_) {}
        _resolvedUrls[trackViewUrl] = playUrl;
      }
    }

    try {
      if (_playingPreviewUrl == playUrl &&
          _playerState == PlayerState.playing) {
        await _musicPlayer.pause();
      } else if (_playingPreviewUrl == playUrl &&
          _playerState == PlayerState.paused) {
        await _musicPlayer.resume();
      } else {
        await _musicPlayer.stop();
        setState(() {
          _playingPreviewUrl = playUrl;
          _position = Duration.zero;
          _duration = Duration.zero;
        });
        await _musicPlayer.play(UrlSource(playUrl));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play preview: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatMusicDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            spreadRadius: 4,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add a Soundtrack',
                          style: GoogleFonts.gabarito(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Search millions of songs on Apple Music',
                          style: GoogleFonts.gabarito(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                onSubmitted: (value) => _searchSongs(value.trim()),
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search for songs, artists, or albums...',
                  hintStyle: GoogleFonts.gabarito(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Icon(
                      Icons.search_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _songs = [];
                              });
                            },
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.7,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(
                      color: colorScheme.outline.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colorScheme.primary,
                      ),
                    )
                  : _songs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchController.text.isEmpty
                                ? Icons.music_note_rounded
                                : Icons.music_off_rounded,
                            size: 64,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchController.text.isEmpty
                                ? 'Search for music to preview'
                                : 'No songs found',
                            style: GoogleFonts.gabarito(
                              fontSize: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _songs.length,
                      itemBuilder: (context, index) {
                        final song = _songs[index];
                        final trackName = song['trackName'] ?? 'Unknown Track';
                        final artistName =
                            song['artistName'] ?? 'Unknown Artist';
                        final albumName = song['collectionName'] ?? '';
                        final artworkUrl = song['artworkUrl100'] ?? '';
                        final previewUrl = song['previewUrl'] ?? '';
                        final trackViewUrl = song['trackViewUrl'] ?? '';

                        final isCurrentPlaying =
                            _playingPreviewUrl == previewUrl ||
                            (_resolvedUrls[trackViewUrl] != null &&
                                _playingPreviewUrl ==
                                    _resolvedUrls[trackViewUrl]);
                        final isPlaying =
                            isCurrentPlaying &&
                            _playerState == PlayerState.playing;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isCurrentPlaying
                                ? colorScheme.primaryContainer.withValues(
                                    alpha: 0.3,
                                  )
                                : colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isCurrentPlaying
                                  ? colorScheme.primary
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: artworkUrl.isNotEmpty
                                      ? Image.network(
                                          artworkUrl,
                                          width: 50,
                                          height: 50,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Container(
                                                    width: 50,
                                                    height: 50,
                                                    color: colorScheme
                                                        .surfaceContainer,
                                                    child: Icon(
                                                      Icons.music_note_rounded,
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                        )
                                      : Container(
                                          width: 50,
                                          height: 50,
                                          color: colorScheme.surfaceContainer,
                                          child: Icon(
                                            Icons.music_note_rounded,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                ),
                                title: Text(
                                  trackName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.gabarito(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  '$artistName${albumName.isNotEmpty ? " • $albumName" : ""}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (previewUrl.isNotEmpty)
                                      Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          if (isCurrentPlaying)
                                            SizedBox(
                                              width: 40,
                                              height: 40,
                                              child: CircularProgressIndicator(
                                                value:
                                                    _duration.inMilliseconds > 0
                                                    ? _position.inMilliseconds /
                                                          _duration
                                                              .inMilliseconds
                                                    : 0.0,
                                                strokeWidth: 2,
                                                backgroundColor:
                                                    colorScheme.outlineVariant,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(colorScheme.primary),
                                              ),
                                            ),
                                          IconButton(
                                            icon: Icon(
                                              isPlaying
                                                  ? Icons.pause_rounded
                                                  : Icons.play_arrow_rounded,
                                              size: 24,
                                              color: isPlaying
                                                  ? colorScheme.primary
                                                  : colorScheme
                                                        .onSurfaceVariant,
                                            ),
                                            onPressed: () => _togglePlay(
                                              previewUrl,
                                              trackViewUrl,
                                            ),
                                          ),
                                        ],
                                      ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline_rounded,
                                        size: 24,
                                      ),
                                      onPressed: () {
                                        widget.onSongSelected(song);
                                        Navigator.pop(context);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              if (isCurrentPlaying) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 12,
                                    right: 12,
                                    bottom: 8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 4,
                                          activeTrackColor: colorScheme.primary,
                                          inactiveTrackColor:
                                              colorScheme.secondaryContainer,
                                          thumbColor: colorScheme.primary,
                                          thumbShape: _soundtrackSeeking
                                              ? const RoundSliderThumbShape(
                                                  enabledThumbRadius: 6,
                                                  pressedElevation: 0,
                                                )
                                              : const RoundSliderThumbShape(
                                                  enabledThumbRadius: 0,
                                                  disabledThumbRadius: 0,
                                                  pressedElevation: 0,
                                                ),
                                          overlayColor: colorScheme.primary
                                              .withValues(alpha: 0.08),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                overlayRadius: 12,
                                              ),
                                          trackShape:
                                              const RoundedRectSliderTrackShape(),
                                          showValueIndicator:
                                              ShowValueIndicator.never,
                                          padding: EdgeInsets.zero,
                                        ),
                                        child: SizedBox(
                                          height: 24,
                                          child: Slider(
                                            value: _position.inMilliseconds
                                                .toDouble()
                                                .clamp(
                                                  0.0,
                                                  _duration.inMilliseconds
                                                      .toDouble(),
                                                ),
                                            max: _duration.inMilliseconds > 0
                                                ? _duration.inMilliseconds
                                                      .toDouble()
                                                : 1.0,
                                            onChanged: _soundtrackSeeking
                                                ? (val) {
                                                    _musicPlayer.seek(
                                                      Duration(
                                                        milliseconds: val
                                                            .toInt(),
                                                      ),
                                                    );
                                                  }
                                                : null,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatMusicDuration(_position),
                                            style: GoogleFonts.gabarito(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                              color: colorScheme
                                                  .onSurfaceVariant
                                                  .withValues(alpha: 0.7),
                                            ),
                                          ),
                                          Text(
                                            _formatMusicDuration(_duration),
                                            style: GoogleFonts.gabarito(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                              color: colorScheme
                                                  .onSurfaceVariant
                                                  .withValues(alpha: 0.7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.apple,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Powered by Apple Music / iTunes',
                    style: GoogleFonts.gabarito(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
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
}

class _ExistingMediaPreview extends StatefulWidget {
  final String fileId;
  final ApiService apiService;
  final VoidCallback onDelete;

  const _ExistingMediaPreview({
    super.key,
    required this.fileId,
    required this.apiService,
    required this.onDelete,
  });

  @override
  State<_ExistingMediaPreview> createState() => _ExistingMediaPreviewState();
}

class _ExistingMediaPreviewState extends State<_ExistingMediaPreview> {
  late String _url;
  late String _type;
  bool _isLoading = true;
  Map<String, String> _headers = {};
  AudioPlayer? _audioPlayer;
  bool _isPlayingAudio = false;
  File? _audioFile;

  @override
  void initState() {
    super.initState();
    _url =
        '${AppConfig.appwriteEndpoint}/storage/buckets/${AppConfig.memoryLanesBucketId}/files/${widget.fileId}/view?project=${AppConfig.appwriteProjectId}';

    if (widget.fileId.startsWith('image')) {
      _type = 'image';
    } else if (widget.fileId.startsWith('video')) {
      _type = 'video';
    } else if (widget.fileId.startsWith('audio')) {
      _type = 'audio';
    } else {
      _type = 'unknown';
    }

    _initializeMedia();
  }

  Future<void> _initializeMedia() async {
    try {
      final jwt = await widget.apiService.getJwtToken();
      if (jwt != null && mounted) {
        setState(() {
          _headers = {
            'X-Appwrite-Project': AppConfig.appwriteProjectId,
            'X-Appwrite-JWT': jwt,
          };
        });
      }

      if (_type == 'audio') {
        _audioPlayer = AudioPlayer();
        final bytes = await widget.apiService.storage.getFileView(
          bucketId: AppConfig.memoryLanesBucketId,
          fileId: widget.fileId,
        );
        final dir = await getTemporaryDirectory();
        _audioFile = File('${dir.path}/${widget.fileId}');
        await _audioFile!.writeAsBytes(bytes);
        _audioPlayer!.onPlayerComplete.listen((_) {
          if (mounted) {
            setState(() => _isPlayingAudio = false);
          }
        });
      }
    } catch (e) {
      debugPrint('Error initializing existing media: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget content;
    if (_isLoading) {
      content = const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_type == 'image') {
      content = GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.zero,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  InteractiveViewer(
                    child: AvifImage.network(
                      _url,
                      headers: _headers,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AvifImage.network(
            _url,
            headers: _headers,
            fit: BoxFit.cover,
            width: 100,
            height: 80,
            errorBuilder: (ctx, err, stack) => Container(
              color: colorScheme.surfaceContainerHigh,
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),
      );
    } else if (_type == 'video') {
      content = Center(
        child: Icon(Icons.videocam, color: colorScheme.onSurface, size: 32),
      );
    } else if (_type == 'audio') {
      content = Center(
        child: IconButton(
          icon: Icon(
            _isPlayingAudio ? Icons.stop : Icons.play_arrow,
            color: colorScheme.onSurface,
            size: 32,
          ),
          onPressed: () async {
            if (_audioPlayer == null || _audioFile == null) return;
            if (_isPlayingAudio) {
              await _audioPlayer!.stop();
              setState(() => _isPlayingAudio = false);
            } else {
              await _audioPlayer!.play(DeviceFileSource(_audioFile!.path));
              setState(() => _isPlayingAudio = true);
            }
          },
        ),
      );
    } else {
      content = const Center(child: Icon(Icons.insert_drive_file));
    }

    return Stack(
      children: [
        Container(
          width: 100,
          margin: const EdgeInsets.only(right: 12),
          child: Column(
            children: [
              Container(
                height: 80,
                width: 100,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: content,
              ),
              if (_type == 'audio')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Voice note',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (_type == 'video')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Video',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          top: -4,
          right: 4,
          child: GestureDetector(
            onTap: widget.onDelete,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Icon(Icons.close, size: 14, color: colorScheme.onSurface),
            ),
          ),
        ),
      ],
    );
  }
}
