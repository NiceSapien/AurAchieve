import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class LockScreen extends StatefulWidget {
  final bool isSetup;
  final String? title;
  final String? subtitle;
  final Future<bool> Function(String)? onPinEntered;
  final VoidCallback? onCancel;

  const LockScreen({
    super.key,
    this.isSetup = false,
    this.title,
    this.subtitle,
    this.onPinEntered,
    this.onCancel,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _MorphingKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _MorphingKey({required this.label, required this.onTap});

  @override
  State<_MorphingKey> createState() => _MorphingKeyState();
}

class _MorphingKeyState extends State<_MorphingKey>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    HapticFeedback.lightImpact();
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(35),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  widget.onTap();
                },
                onHighlightChanged: (value) {
                  if (value) {
                    HapticFeedback.lightImpact();
                    _controller.forward();
                  } else {
                    _controller.reverse();
                  }
                },
                borderRadius: BorderRadius.circular(35),
                child: Center(
                  child: Text(
                    widget.label,
                    style: GoogleFonts.gabarito(
                      fontSize: 32,
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LockScreenState extends State<LockScreen> {
  
  final List<String> _pin = [];
  String? _firstPin;
  String _message = '';
  bool _isError = false;

  void _handleKeyPress(String key) {
    if (_pin.length >= 4) return;
    
    setState(() {
      _pin.add(key);
      _isError = false;
      _message = '';
    });

    if (_pin.length == 4) {
      _submitPin();
    }
  }

  

  void _handleDelete() {
    if (_pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin.removeLast();
      _isError = false;
      _message = '';
    });
  }

  Future<void> _submitPin() async {
    final pinString = _pin.join();

    if (widget.isSetup) {
      if (_firstPin == null) {
        
        setState(() {
          _firstPin = pinString;
          _pin.clear();
          _message = 'Confirm your PIN';
        });
      } else {
        
        if (pinString == _firstPin) {
          if (widget.onPinEntered != null) {
            await widget.onPinEntered!(pinString);
          }
        } else {
          _showError('PINs do not match. Try again.');
          setState(() {
            _firstPin = null;
            _pin.clear();
          });
        }
      }
    } else {
      
      if (widget.onPinEntered != null) {
        final success = await widget.onPinEntered!(pinString);
        if (!success) {
          _showError('Incorrect PIN');
        }
      }
    }
  }

  void _showError(String msg) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isError = true;
      _message = msg;
      _pin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final defaultTitle = widget.isSetup
        ? (_firstPin == null ? 'Set a PIN' : 'Confirm PIN')
        : 'Enter PIN';

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: scheme.onSurface),
          onPressed: widget.onCancel ?? () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.title ?? defaultTitle,
                    style: GoogleFonts.gabarito(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _message.isNotEmpty ? _message : (widget.subtitle ?? ''),
                    style: GoogleFonts.gabarito(
                      fontSize: 16,
                      color: _isError ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final filled = index < _pin.length;

                      
                      
                      final ShapeBorder shape = switch (index) {
                        0 => const StarBorder(
                          points: 4,
                          innerRadiusRatio: 0.7,
                          pointRounding: 0.5,
                        ), 
                        1 => RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ), 
                        2 => const CircleBorder(), 
                        3 => const BeveledRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ), 
                        _ => const CircleBorder(),
                      };

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutBack,
                          width: 24,
                          height: 24,
                          decoration: ShapeDecoration(
                            color: filled
                                ? (_isError ? scheme.error : scheme.primary)
                                : scheme.surfaceContainerHighest,
                            shape: shape,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildKey('1'),
                      const SizedBox(width: 16),
                      _buildKey('2'),
                      const SizedBox(width: 16),
                      _buildKey('3'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildKey('4'),
                      const SizedBox(width: 16),
                      _buildKey('5'),
                      const SizedBox(width: 16),
                      _buildKey('6'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildKey('7'),
                      const SizedBox(width: 16),
                      _buildKey('8'),
                      const SizedBox(width: 16),
                      _buildKey('9'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      
                      Expanded(
                        child: GestureDetector(
                          onTap: _handleDelete,
                          child: Container(
                            height: 70,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withOpacity(
                                0.5,
                              ),
                              borderRadius: BorderRadius.circular(35),
                            ),
                            child: Icon(
                              Icons.backspace_outlined,
                              color: scheme.onSurfaceVariant,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      _buildKey('0'),
                      const SizedBox(width: 16),
                      
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            
                          },
                          child: Container(
                            height: 70,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withOpacity(
                                0.5,
                              ),
                              borderRadius: BorderRadius.circular(35),
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: scheme.onSurfaceVariant,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKey(String val) {
    
    return _MorphingKey(label: val, onTap: () => _handleKeyPress(val));
  }
}
