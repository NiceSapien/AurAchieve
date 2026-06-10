import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../api_service.dart';
import 'create_memory.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import '../utils/crypto_utils.dart';
import 'package:flutter_avif/flutter_avif.dart';

class MemoryDetailPage extends StatefulWidget {
  final Map<String, dynamic> memory;
  final ApiService? apiService;
  final bool e2eEnabled;

  const MemoryDetailPage({
    super.key,
    required this.memory,
    this.apiService,
    this.e2eEnabled = false,
  });

  @override
  State<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends State<MemoryDetailPage> {
  late quill.QuillController _quillController;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _showFullDate = false;

  Map<String, dynamic>? _selectedSong;
  final AudioPlayer _musicPlayer = AudioPlayer();
  Duration _musicDuration = Duration.zero;
  Duration _musicPosition = Duration.zero;
  bool _isPlayingMusic = false;
  String? _playingMusicUrl;
  bool _soundtrackSeeking = true;
  String? _currentUserUsername;
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _loadSeekingSetting();
    _initQuill();
    _initAudioListeners();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      if (widget.apiService != null) {
        final user = await widget.apiService!.account.get();
        if (mounted) {
          setState(() {
            _currentUserName = user.name;
          });
        }
        final page = await widget.apiService!.getAuraPage();
        if (mounted && page.isNotEmpty) {
          setState(() {
            _currentUserUsername = page['username'];
          });
        }
      }
    } catch (_) {}
  }

  void _initAudioListeners() {
    _musicPlayer.onDurationChanged.listen((d) {
      if (mounted) {
        setState(() {
          _musicDuration = d;
        });
      }
    });
    _musicPlayer.onPositionChanged.listen((p) {
      if (mounted) {
        setState(() {
          _musicPosition = p;
        });
      }
    });
    _musicPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlayingMusic = state == PlayerState.playing;
        });
      }
    });
    _musicPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlayingMusic = false;
          _musicPosition = Duration.zero;
        });
      }
    });
  }

  void _initQuill() {
    String description = widget.memory['description'] ?? '';
    if (description.contains('%%LISTENED_TO:')) {
      final parts = description.split('%%LISTENED_TO:');
      description = parts[0].trim();
      final songPart = parts[1].replaceAll('%%', '').trim();
      try {
        _selectedSong = jsonDecode(songPart);
      } catch (_) {}
    }

    try {
      final json = jsonDecode(description);
      _quillController = quill.QuillController(
        document: quill.Document.fromJson(json),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    } catch (e) {
      _quillController = quill.QuillController(
        document: quill.Document()..insert(0, description),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    }
  }

  @override
  void dispose() {
    _quillController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _musicPlayer.dispose();
    super.dispose();
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

  Widget _buildDateChip(ColorScheme colorScheme, DateTime date) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showFullDate = !_showFullDate;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              _showFullDate
                  ? DateFormat('MMMM d, yyyy h:mm a').format(date)
                  : DateFormat('MMMM d, yyyy').format(date),
              style: GoogleFonts.gabarito(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorChip(ColorScheme colorScheme, String author) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_outline_rounded,
            size: 14,
            color: colorScheme.secondary,
          ),
          const SizedBox(width: 6),
          Text(
            'By $author',
            style: GoogleFonts.gabarito(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodChip(ColorScheme colorScheme, String mood) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mood, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            'Mood',
            style: GoogleFonts.gabarito(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String tag, Color tagColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tagColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.label_outline_rounded, size: 14, color: tagColor),
          const SizedBox(width: 6),
          Text(
            tag,
            style: GoogleFonts.gabarito(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tagColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = widget.memory['name'] ?? 'Untitled';
    final createdAt = widget.memory['createdAt'];
    final tag = widget.memory['tag'];
    final mood = widget.memory['mood'];
    final author = widget.memory['author']?.toString();
    final isOwnMemory =
        author == null ||
        author.isEmpty ||
        author == _currentUserUsername ||
        author == _currentUserName;
    final tagColorName = widget.memory['tagColor'];
    final files = widget.memory['files'] as List<dynamic>? ?? [];
    final isPublic = widget.memory['public'] == true;

    DateTime? date;
    if (createdAt != null) {
      try {
        date = DateTime.parse(createdAt);
      } catch (_) {}
    }

    Color tagColor = Colors.blue;
    if (tagColorName != null) {
      switch (tagColorName) {
        case 'red':
          tagColor = Colors.red;
          break;
        case 'green':
          tagColor = Colors.green;
          break;
        case 'orange':
          tagColor = Colors.orange;
          break;
        case 'purple':
          tagColor = Colors.purple;
          break;
        case 'pink':
          tagColor = Colors.pink;
          break;
        case 'teal':
          tagColor = Colors.teal;
          break;
        default:
          tagColor = Colors.blue;
      }
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar.medium(
              backgroundColor: colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: colorScheme.onSurface,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.gabarito(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              actions: [
                if (isPublic)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
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
                          Icons.public_rounded,
                          size: 12,
                          color: colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Public',
                          style: GoogleFonts.gabarito(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: colorScheme.onSurface,
                  ),
                  onPressed: () async {
                    final choice = await showModalBottomSheet<String>(
                      context: context,
                      builder: (_) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              title: const Text('Delete'),
                              onTap: () => Navigator.of(context).pop('delete'),
                            ),
                            ListTile(
                              leading: const Icon(Icons.edit_outlined),
                              title: const Text('Edit'),
                              onTap: () => Navigator.of(context).pop('edit'),
                            ),
                          ],
                        ),
                      ),
                    );

                    if (choice == 'delete') {
                      final id =
                          (widget.memory[r'$id'] ??
                                  widget.memory['id'] ??
                                  widget.memory['memoryId'] ??
                                  '')
                              ?.toString();
                      if (id == null || id.isEmpty) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Unable to determine memory id'),
                            ),
                          );
                        }
                        return;
                      }

                      if (!context.mounted) return;
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
                                Icon(
                                  Icons.delete_outline_rounded,
                                  color: cs.error,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Delete memory?',
                                  style: GoogleFonts.gabarito(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            content: Text(
                              'Are you sure you want to permanently delete this memory? This cannot be undone.',
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
                          if (widget.apiService == null) {
                            throw Exception('API service unavailable');
                          }

                          await widget.apiService!.deleteMemory(id);
                          if (context.mounted && Navigator.canPop(context)) {
                            Navigator.of(context).pop(true);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to delete: $e')),
                            );
                          }
                        }
                      }
                    } else if (choice == 'edit') {
                      if (widget.apiService == null) return;
                      if (!context.mounted) return;
                      final result = await Navigator.of(context).push<bool?>(
                        MaterialPageRoute(
                          builder: (_) => CreateMemoryPage(
                            apiService: widget.apiService!,
                            existingMemory: widget.memory,
                            e2eEnabled: widget.e2eEnabled,
                          ),
                        ),
                      );
                      if (result == true && context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    }
                  },
                ),
              ],
            ),
          ];
        },
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (date != null) _buildDateChip(colorScheme, date),
                  if (!isOwnMemory && author.isNotEmpty)
                    _buildAuthorChip(colorScheme, author),
                  if (mood != null && mood.toString().isNotEmpty)
                    _buildMoodChip(colorScheme, mood.toString()),
                  if (tag != null && tag.toString().isNotEmpty)
                    _buildTagChip(tag.toString(), tagColor),
                ],
              ),
              const SizedBox(height: 24),
              if (files.isNotEmpty) ...[
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final fileId = files[index].toString();
                      return Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: _MediaItem(
                          fileId: fileId,
                          apiService: widget.apiService,
                          e2eEnabled: widget.e2eEnabled,
                          isPublic: isPublic,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],
              DefaultTextStyle(
                style: GoogleFonts.gabarito(
                  fontSize: 16,
                  height: 1.6,
                  color: colorScheme.onSurface,
                ),
                child: quill.QuillEditor(
                  controller: _quillController,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  config: const quill.QuillEditorConfig(
                    autoFocus: false,
                    expands: false,
                    padding: EdgeInsets.zero,
                    showCursor: false,
                    enableInteractiveSelection: true,
                  ),
                ),
              ),
              _buildListenedToCard(colorScheme, isOwnMemory),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
      await _musicPlayer.pause();
    } else if (_playingMusicUrl == playUrl &&
        !_isPlayingMusic &&
        _musicPosition > Duration.zero) {
      await _musicPlayer.resume();
    } else {
      await _musicPlayer.stop();
      setState(() {
        _playingMusicUrl = playUrl;
      });
      await _musicPlayer.play(UrlSource(playUrl));
    }
  }

  Widget _buildListenedToCard(ColorScheme colorScheme, bool isOwnMemory) {
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
      margin: const EdgeInsets.only(top: 24, bottom: 8),
      padding: const EdgeInsets.all(16),
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
                isOwnMemory
                    ? 'WHAT I\'VE BEEN LISTENING TO'
                    : 'BEEN LISTENING TO',
                style: GoogleFonts.gabarito(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap: trackViewUrl.toString().isNotEmpty
                    ? () => _launchUrl(trackViewUrl.toString())
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: artworkUrl.isNotEmpty
                      ? Image.network(
                          artworkUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
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
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: trackViewUrl.toString().isNotEmpty
                      ? () => _launchUrl(trackViewUrl.toString())
                      : null,
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
                          _musicPlayer.seek(
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
                  _formatDuration(_musicPosition),
                  style: GoogleFonts.gabarito(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  _formatDuration(_musicDuration),
                  style: GoogleFonts.gabarito(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
          if (trackViewUrl.toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(
              color: colorScheme.outlineVariant,
              height: 1,
              thickness: 0.5,
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _launchUrl(trackViewUrl.toString()),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.apple, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Open on Apple Music',
                    style: GoogleFonts.gabarito(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaItem extends StatefulWidget {
  final String fileId;
  final ApiService? apiService;
  final bool e2eEnabled;
  final bool isPublic;
  const _MediaItem({
    required this.fileId,
    this.apiService,
    required this.e2eEnabled,
    required this.isPublic,
  });

  @override
  State<_MediaItem> createState() => _MediaItemState();
}

class _MediaItemState extends State<_MediaItem> {
  late String _url;
  late String _type;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAudio = false;
  bool _isLoading = true;
  Map<String, String> _headers = {};
  File? _audioFile;
  File? _decryptedFile;
  bool _isEncrypted = false;

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

    _isEncrypted = widget.e2eEnabled && !widget.isPublic;
    _initializeMedia();
  }

  Future<void> _initializeMedia() async {
    try {
      if (widget.apiService != null) {
        final jwt = await widget.apiService!.getJwtToken();
        if (jwt != null) {
          _headers = {
            'X-Appwrite-Project': AppConfig.appwriteProjectId,
            'X-Appwrite-JWT': jwt,
          };
        }
      }

      if (_isEncrypted && widget.apiService != null) {
        const secureStorage = FlutterSecureStorage();
        final keyString = await secureStorage.read(key: 'memory_lanes_password');
        if (keyString != null && keyString.isNotEmpty) {
          final bytes = await widget.apiService!.storage.getFileView(
            bucketId: AppConfig.memoryLanesBucketId,
            fileId: widget.fileId,
          );
          if (bytes.length > 16) {
            List<int>? decrypted;
            final ivBytes = bytes.sublist(0, 16);
            final iv = encrypt.IV(ivBytes);
            final encryptedBytes = bytes.sublist(16);

            // 1. Try PBKDF2 decryption
            try {
              final key = derivePBKDF2Key(keyString);
              final encrypter = encrypt.Encrypter(encrypt.AES(key));
              decrypted = encrypter.decryptBytes(
                encrypt.Encrypted(encryptedBytes),
                iv: iv,
              );

              // Validate file signature/headers to ensure it's not garbage
              bool isValid = false;
              if (decrypted.length > 4) {
                if (_type == 'image') {
                  // WebP ('RIFF' = 82, 73, 70, 70) or JPEG (255, 216, 255) or PNG (137, 80, 78)
                  if ((decrypted[0] == 82 && decrypted[1] == 73 && decrypted[2] == 70 && decrypted[3] == 70) ||
                      (decrypted[0] == 255 && decrypted[1] == 216 && decrypted[2] == 255) ||
                      (decrypted[0] == 137 && decrypted[1] == 80 && decrypted[2] == 78 && decrypted[3] == 71)) {
                    isValid = true;
                  }
                } else if (_type == 'audio') {
                  // Opus/Ogg ('OggS' = 79, 103, 103, 83) or AAC/ADTS (255, 241) or MPEG/MP3 (255, 251)
                  if ((decrypted[0] == 79 && decrypted[1] == 103 && decrypted[2] == 103 && decrypted[3] == 83) ||
                      (decrypted[0] == 255 && (decrypted[1] & 0xF0) == 0xF0)) {
                    isValid = true;
                  }
                } else if (_type == 'video') {
                  // MP4/HEVC (contains 'ftyp' at offset 4)
                  if (decrypted.length > 8) {
                    final isFtyp = (decrypted[4] == 102 && decrypted[5] == 116 && decrypted[6] == 121 && decrypted[7] == 112);
                    if (isFtyp) isValid = true;
                  }
                }
              }
              if (!isValid) {
                decrypted = null; // force fallback
              }
            } catch (_) {
              decrypted = null;
            }

            // 2. Fallback to legacy key decryption
            if (decrypted == null) {
              try {
                final key = getLegacyKey(keyString);
                final encrypter = encrypt.Encrypter(encrypt.AES(key));
                decrypted = encrypter.decryptBytes(
                  encrypt.Encrypted(encryptedBytes),
                  iv: iv,
                );
              } catch (_) {}
            }

            if (decrypted != null) {
              final dir = await getTemporaryDirectory();
              _decryptedFile = File('${dir.path}/dec_${widget.fileId}');
              await _decryptedFile!.writeAsBytes(decrypted);
            }
          }
        }
      }

      if (_type == 'video') {
        if (_isEncrypted && _decryptedFile != null) {
          _videoController = VideoPlayerController.file(_decryptedFile!);
        } else {
          _videoController = VideoPlayerController.networkUrl(
            Uri.parse(_url),
            httpHeaders: _headers,
          );
        }
        await _videoController!.initialize();
        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: false,
          looping: false,
          aspectRatio: _videoController!.value.aspectRatio,
        );
      } else if (_type == 'audio') {
        if (_isEncrypted && _decryptedFile != null) {
          _audioFile = _decryptedFile;
        } else if (widget.apiService != null) {
          final bytes = await widget.apiService!.storage.getFileView(
            bucketId: AppConfig.memoryLanesBucketId,
            fileId: widget.fileId,
          );
          final dir = await getTemporaryDirectory();
          _audioFile = File('${dir.path}/${widget.fileId}');
          await _audioFile!.writeAsBytes(bytes);
        }
        _audioPlayer.onPlayerComplete.listen((_) {
          if (mounted) {
            setState(() => _isPlayingAudio = false);
          }
        });
      }
    } catch (e) {
      debugPrint('Error initializing media: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    _audioPlayer.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: colorScheme.surfaceContainerHigh,
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_type == 'image') {
      return GestureDetector(
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
                    child: _isEncrypted && _decryptedFile != null
                        ? AvifImage.file(
                            _decryptedFile!,
                            fit: BoxFit.contain,
                          )
                        : AvifImage.network(
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
          child: _isEncrypted && _decryptedFile != null
              ? AvifImage.file(
                  _decryptedFile!,
                  fit: BoxFit.cover,
                  width: 200,
                  height: 200,
                )
              : AvifImage.network(
                  _url,
                  headers: _headers,
                  fit: BoxFit.cover,
                  width: 200,
                  height: 200,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: 200,
                      height: 200,
                      color: colorScheme.surfaceContainerHigh,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (ctx, err, stack) => Container(
                    width: 200,
                    height: 200,
                    color: colorScheme.surfaceContainerHigh,
                    child: const Icon(Icons.broken_image),
                  ),
                ),
        ),
      );
    } else if (_type == 'video') {
      if (_chewieController != null && _videoController!.value.isInitialized) {
        return Container(
          width: 300,
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.black,
          ),
          clipBehavior: Clip.antiAlias,
          child: Chewie(controller: _chewieController!),
        );
      } else {
        return Container(
          width: 300,
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: colorScheme.surfaceContainerHigh,
          ),
          child: const Center(child: Icon(Icons.error_outline)),
        );
      }
    } else if (_type == 'audio') {
      return Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: colorScheme.surfaceContainerHigh,
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _isPlayingAudio
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      size: 40,
                    ),
                    color: colorScheme.primary,
                    onPressed: () async {
                      try {
                        if (_isPlayingAudio) {
                          await _audioPlayer.pause();
                        } else {
                          if (_audioFile != null) {
                            await _audioPlayer.play(
                              DeviceFileSource(_audioFile!.path),
                            );
                          } else {
                            await _audioPlayer.play(UrlSource(_url));
                          }
                        }
                        setState(() => _isPlayingAudio = !_isPlayingAudio);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error playing audio: $e')),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Audio Recording',
                          style: GoogleFonts.gabarito(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        StreamBuilder<Duration>(
                          stream: _audioPlayer.onPositionChanged,
                          builder: (context, snapshot) {
                            final position = snapshot.data ?? Duration.zero;
                            return StreamBuilder<Duration>(
                              stream: _audioPlayer.onDurationChanged,
                              builder: (context, snapshot) {
                                final duration = snapshot.data ?? Duration.zero;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 4,
                                        activeTrackColor: colorScheme.primary,
                                        inactiveTrackColor:
                                            colorScheme.secondaryContainer,
                                        thumbColor: colorScheme.primary,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6,
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
                                          value: position.inSeconds
                                              .toDouble()
                                              .clamp(
                                                0.0,
                                                duration.inSeconds.toDouble(),
                                              ),
                                          max: duration.inSeconds > 0
                                              ? duration.inSeconds.toDouble()
                                              : 1.0,
                                          onChanged: (val) {
                                            _audioPlayer.seek(
                                              Duration(seconds: val.toInt()),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(position),
                                          style: GoogleFonts.gabarito(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.7),
                                          ),
                                        ),
                                        Text(
                                          _formatDuration(duration),
                                          style: GoogleFonts.gabarito(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
