import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../api_service.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audioplayers/audioplayers.dart';

class MemoryDetailPage extends StatefulWidget {
  final Map<String, dynamic> memory;
  final ApiService? apiService;

  const MemoryDetailPage({super.key, required this.memory, this.apiService});

  @override
  State<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends State<MemoryDetailPage> {
  late quill.QuillController _quillController;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _showFullDate = false;

  @override
  void initState() {
    super.initState();
    _initQuill();
  }

  void _initQuill() {
    final description = widget.memory['description'] ?? '';
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = widget.memory['name'] ?? 'Untitled';
    final createdAt = widget.memory['createdAt'];
    final tag = widget.memory['tag'];
    final mood = widget.memory['mood'];
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              Theme.of(context).brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (mood != null && mood.toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                mood.toString(),
                style: const TextStyle(fontSize: 24),
              ),
            ),
          if (isPublic)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                'Public',
                style: GoogleFonts.gabarito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurface),
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
                  builder: (_) => AlertDialog(
                    title: Text(
                      'Delete memory?',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    content: Text(
                      'This will permanently delete the memory.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
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
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              name,
              style: GoogleFonts.gabarito(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                height: 1.1,
                color: colorScheme.onSurface,
              ),
            ),
            if (date != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showFullDate = !_showFullDate;
                  });
                },
                child: Text(
                  _showFullDate
                      ? DateFormat('MMMM d, yyyy h:mm a').format(date)
                      : DateFormat('MMMM d, yyyy').format(date),
                  style: GoogleFonts.gabarito(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (tag != null && tag.toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: tagColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: tagColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      tag,
                      style: GoogleFonts.gabarito(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tagColor,
                      ),
                    ),
                  ),
                  if (mood != null && mood.toString().isNotEmpty) ...[
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
            if ((tag == null || tag.toString().isEmpty) &&
                mood != null &&
                mood.toString().isNotEmpty) ...[
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 32),
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
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _MediaItem extends StatefulWidget {
  final String fileId;
  final ApiService? apiService;
  const _MediaItem({required this.fileId, this.apiService});

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

  @override
  void initState() {
    super.initState();
    _url =
        '${AppConfig.appwriteEndpoint}/storage/buckets/6957d8c0001c106bf6cf/files/${widget.fileId}/view?project=${AppConfig.appwriteProjectId}';

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
      if (widget.apiService != null) {
        final jwt = await widget.apiService!.getJwtToken();
        if (jwt != null) {
          _headers = {
            'X-Appwrite-Project': AppConfig.appwriteProjectId,
            'X-Appwrite-JWT': jwt,
          };
        }
      }

      if (_type == 'video') {
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(_url),
          httpHeaders: _headers,
        );
        await _videoController!.initialize();
        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: false,
          looping: false,
          aspectRatio: _videoController!.value.aspectRatio,
        );
      } else if (_type == 'audio') {
        if (widget.apiService != null) {
          final bytes = await widget.apiService!.storage.getFileView(
            bucketId: '6957d8c0001c106bf6cf',
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
                    child: Image.network(
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
          child: Image.network(
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: colorScheme.surfaceContainerHighest,
            border: Border.all(color: colorScheme.outlineVariant),
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
                                return Row(
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderThemeData(
                                          trackHeight: 2,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                enabledThumbRadius: 6,
                                              ),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                overlayRadius: 12,
                                              ),
                                        ),
                                        child: Slider(
                                          value: position.inSeconds
                                              .toDouble()
                                              .clamp(
                                                0,
                                                duration.inSeconds.toDouble(),
                                              ),
                                          max: duration.inSeconds.toDouble(),
                                          onChanged: (val) {
                                            _audioPlayer.seek(
                                              Duration(seconds: val.toInt()),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(duration),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
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
