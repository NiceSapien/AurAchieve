import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:http/http.dart' as http;

class SmartAvifImage extends StatefulWidget {
  final String? url;
  final File? file;
  final Map<String, String>? headers;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  const SmartAvifImage.network(
    this.url, {
    super.key,
    this.headers,
    this.width,
    this.height,
    this.fit,
    this.loadingBuilder,
    this.errorBuilder,
  }) : file = null;

  const SmartAvifImage.file(
    this.file, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.errorBuilder,
  }) : url = null,
       loadingBuilder = null,
       headers = null;

  @override
  State<SmartAvifImage> createState() => _SmartAvifImageState();
}

class _SmartAvifImageState extends State<SmartAvifImage> {
  bool _isLoading = true;
  bool _isWebP = false;

  @override
  void initState() {
    super.initState();
    _detectFormat();
  }

  @override
  void didUpdateWidget(SmartAvifImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.file?.path != widget.file?.path ||
        !mapEquals(oldWidget.headers, widget.headers)) {
      _detectFormat();
    }
  }

  Future<void> _detectFormat() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isWebP = false;
    });

    try {
      List<int>? bytes;

      if (widget.file != null) {
        final f = widget.file!;
        if (await f.exists()) {
          final raf = await f.open(mode: FileMode.read);
          bytes = await raf.read(12);
          await raf.close();
        }
      } else if (widget.url != null && widget.url!.isNotEmpty) {
        final response = await http.get(
          Uri.parse(widget.url!),
          headers: {
            if (widget.headers != null) ...widget.headers!,
            'Range': 'bytes=0-11',
          },
        ).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200 || response.statusCode == 206) {
          bytes = response.bodyBytes;
        }
      }

      if (bytes != null && bytes.length >= 12) {
        final isRiff = bytes[0] == 82 && bytes[1] == 73 && bytes[2] == 70 && bytes[3] == 70; // RIFF
        final isWebp = bytes[8] == 87 && bytes[9] == 69 && bytes[10] == 66 && bytes[11] == 80; // WEBP
        if (isRiff && isWebp) {
          _isWebP = true;
        }
      }
    } catch (e) {
      debugPrint('Error detecting image format: $e');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (widget.file != null) {
      if (_isWebP) {
        return Image.file(
          widget.file!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: widget.errorBuilder,
        );
      } else {
        return AvifImage.file(
          widget.file!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: widget.errorBuilder,
        );
      }
    } else if (widget.url != null) {
      if (_isWebP) {
        return Image.network(
          widget.url!,
          headers: widget.headers,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          loadingBuilder: widget.loadingBuilder,
          errorBuilder: widget.errorBuilder,
        );
      } else {
        return AvifImage.network(
          widget.url!,
          headers: widget.headers,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          loadingBuilder: widget.loadingBuilder,
          errorBuilder: widget.errorBuilder,
        );
      }
    }

    return Container(
      width: widget.width,
      height: widget.height,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: const Icon(Icons.broken_image),
    );
  }
}
