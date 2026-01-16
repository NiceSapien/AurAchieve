import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api_service.dart';

class CreateMemoryPage extends StatefulWidget {
  final ApiService apiService;
  final bool e2eEnabled;

  const CreateMemoryPage({
    super.key,
    required this.apiService,
    this.e2eEnabled = false,
  });

  @override
  State<CreateMemoryPage> createState() => _CreateMemoryPageState();
}

class _CreateMemoryPageState extends State<CreateMemoryPage> {
  final _titleController = TextEditingController();
  final _tagController = TextEditingController();
  late final quill.QuillController _quillController;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();

  bool _isPublic = false;
  bool _isSaving = false;
  String _selectedColor = 'blue';
  String? _selectedMood;
  DateTime _selectedDate = DateTime.now();
  bool _toolbarExpanded = false;

  static const List<String> _allowedMoods = [
    '😀',
    '😢',
    '😡',
    '🥳',
    '😴',
    '🔥',
    '❤️',
    '✨',
  ];

  final List<File> _mediaFiles = [];
  final List<String> _mediaTypes = [];
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  int? _playingIndex;

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
    _quillController = quill.QuillController.basic();
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _playingIndex = null);
      }
    });
  }

  @override
  void dispose() {
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

  Future<void> _checkE2EWarning() async {
    if (widget.e2eEnabled) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Encryption Warning',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Text(
            'Media attachments (images, videos, audio) are NOT end-to-end encrypted. They are, however, encrypted and secured from other people.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I Understand'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    await _checkE2EWarning();
    if (_mediaFiles.length >= 3) {
      _showError('Max 3 files allowed');
      return;
    }
    if (_mediaTypes.where((t) => t == 'image').length >= 2) {
      _showError('Max 2 images allowed');
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final file = File(picked.path);
      if (await file.length() > 30 * 1024 * 1024) {
        _showError('File too large (Max 30MB)');
        return;
      }

      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.webp';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        format: CompressFormat.webp,
      );

      if (result != null) {
        setState(() {
          _mediaFiles.add(File(result.path));
          _mediaTypes.add('image');
        });
      }
    }
  }

  Future<void> _pickVideo() async {
    await _checkE2EWarning();
    if (_mediaFiles.length >= 3) {
      _showError('Max 3 files allowed');
      return;
    }
    if (_mediaTypes.contains('video')) {
      _showError('Max 1 video allowed');
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      final file = File(picked.path);
      if (!file.path.toLowerCase().endsWith('.mp4')) {
        _showError('Only .mp4 videos are allowed');
        return;
      }
      if (await file.length() > 30 * 1024 * 1024) {
        _showError('File too large (Max 30MB)');
        return;
      }
      setState(() {
        _mediaFiles.add(file);
        _mediaTypes.add('video');
      });
    }
  }

  Future<void> _showRecordingDialog() async {
    await _checkE2EWarning();
    if (_mediaFiles.length >= 3) {
      _showError('Max 3 files allowed');
      return;
    }
    if (_mediaTypes.contains('audio')) {
      _showError('Max 1 audio file allowed');
      return;
    }

    final file = await showDialog<File>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const RecordingDialog(),
    );

    if (file != null) {
      if (await file.length() > 30 * 1024 * 1024) {
        _showError('Recording too large');
        return;
      }
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
      List<String> fileIds = [];
      for (int i = 0; i < _mediaFiles.length; i++) {
        final file = _mediaFiles[i];
        final type = _mediaTypes[i];
        final ext = file.path.split('.').last;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        String name = '${type}_$timestamp.$ext';
        name = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '');

        final id = await widget.apiService.uploadMemoryFile(
          file,
          name,
          isPublic: _isPublic,
        );
        fileIds.add(id);
      }

      final delta = _quillController.document.toDelta();
      String description = jsonEncode(delta.toJson());

      String? name = _titleController.text.trim();
      String? tag = _tagController.text.trim().isNotEmpty
          ? _tagController.text.trim()
          : null;
      String? tagColor = _selectedColor;
      String? mood = _selectedMood;

      if (widget.e2eEnabled && !_isPublic) {
        const storage = FlutterSecureStorage();
        final keyString = await storage.read(key: 'memory_lanes_password');
        if (keyString != null && keyString.isNotEmpty) {
          final key = encrypt.Key.fromUtf8(
            keyString.padRight(32).substring(0, 32),
          );
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
      }

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
                children: _allowedMoods.map((mood) {
                  final isSelected = _selectedMood == mood;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedMood = mood);
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
                }).toList(),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Memory',
          style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
        ),
        actions: [
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

                  if (_mediaFiles.isNotEmpty) ...[
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _mediaFiles.length,
                        itemBuilder: (context, index) {
                          final file = _mediaFiles[index];
                          final type = _mediaTypes[index];
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
                                        border: Border.all(
                                          color: colorScheme.outlineVariant,
                                        ),
                                        image: type == 'image'
                                            ? DecorationImage(
                                                image: FileImage(file),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      child: type != 'image'
                                          ? Center(
                                              child: type == 'audio'
                                                  ? IconButton(
                                                      icon: Icon(
                                                        _playingIndex == index
                                                            ? Icons.stop
                                                            : Icons.play_arrow,
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
                                                      color:
                                                          colorScheme.onSurface,
                                                      size: 32,
                                                    ),
                                            )
                                          : null,
                                    ),
                                    if (type == 'audio')
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Voice note',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorScheme.onSurfaceVariant,
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
                                      _mediaFiles.removeAt(index);
                                      _mediaTypes.removeAt(index);
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
                              color: _isAttributeActive(quill.Attribute.italic)
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
                                  _isAttributeActive(quill.Attribute.underline)
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
                            onPressed: () =>
                                _toggleAttribute(quill.Attribute.strikeThrough),
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
                                textController.text = _quillController.document
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
                                              decoration: const InputDecoration(
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
                                          onPressed: () => Navigator.pop(ctx, {
                                            'text': textController.text,
                                            'url': urlController.text,
                                          }),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );

                              if (result != null && result['url']!.isNotEmpty) {
                                final url = result['url']!;
                                final text = result['text'] ?? url;

                                if (hasSelection) {
                                  _quillController.formatSelection(
                                    quill.LinkAttribute(url),
                                  );
                                } else {
                                  final index =
                                      _quillController.selection.baseOffset;
                                  _quillController.document.insert(index, text);
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
                                    () => _toggleAttribute(quill.Attribute.ul),
                                    color:
                                        _isAttributeActive(quill.Attribute.ul)
                                        ? colorScheme.primary
                                        : null,
                                  ),
                                  _buildMediaButton(
                                    Icons.format_list_numbered,
                                    'Number',
                                    () => _toggleAttribute(quill.Attribute.ol),
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

      _path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.mp3';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
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
