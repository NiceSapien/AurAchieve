import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api_service.dart';
import 'package:auraascend/screens/reminder_setup_screen.dart';

class HabitSetup extends StatefulWidget {
  final String userName;
  final ApiService apiService;
  const HabitSetup({
    super.key,
    required this.userName,
    required this.apiService,
  });
  @override
  State<HabitSetup> createState() => _HabitSetupState();
}

class _HabitSetupState extends State<HabitSetup> {
  int _introPage = 0;
  int? _editingIndex;
  final List<String> _values = [
    'habit',
    'time/location',
    'type of person I want to be',
  ];
  final List<String> _placeholders = [
    'habit',
    'time/location',
    'type of person I want to be',
  ];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  static const habitSuggestions = ['exercise', 'study'];
  static const cueSuggestions = [];
  static const goalSuggestions = [];
  final bool _suggestionsExpanded = true;
  bool _introForward = true;
  final bool _submitting = false;

  bool get _isComplete =>
      _values[0].trim().isNotEmpty &&
      _values[0] != _placeholders[0] &&
      _values[1].trim().isNotEmpty &&
      _values[1] != _placeholders[1] &&
      _values[2].trim().isNotEmpty &&
      _values[2] != _placeholders[2];

  Future<void> _continueToReminders() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReminderSetupScreen(
          apiService: widget.apiService,
          habitName: _values[0].trim(),
          habitCue: _values[1].trim(),
          habitGoal: _values[2].trim(),
        ),
      ),
    );
    if (result == true && mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _nextIntro() {
    setState(() {
      if (_introPage < 2) {
        _introForward = true;
        _introPage++;
      } else {
        _introPage = 3;
        _startEdit(0);
      }
    });
  }

  void _backIntro() {
    setState(() {
      if (_introPage > 0) {
        _introForward = false;
        _introPage--;
      }
    });
  }

  void _startEdit(int index) {
    setState(() {
      _editingIndex = index;
      _inputController.text = (_values[index] == _placeholders[index])
          ? ''
          : _values[index];
    });
  }

  void _saveEdit(
    String? suggestion, {
    bool goNext = false,
    bool goBack = false,
  }) {
    if (_editingIndex == null) return;
    final idx = _editingIndex!;
    final text = suggestion ?? _inputController.text.trim();
    setState(() {
      if (text.isNotEmpty) _values[idx] = text;
      if (goNext && idx < 2) {
        _startEdit(idx + 1);
      } else if (goBack && idx > 0) {
        _startEdit(idx - 1);
      } else if (!goNext && !goBack && idx == 2) {
        FocusScope.of(context).unfocus();
      }
    });
  }

  void _finalizeAndContinue() {
    if (_editingIndex != null) {
      final idx = _editingIndex!;
      final t = _inputController.text.trim();
      if (t.isNotEmpty) _values[idx] = t;
    }
    setState(() => _editingIndex = null);
    FocusScope.of(context).unfocus();
    _continueToReminders();
  }

  Widget _buildIntroSentence() {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) {
          final offsetAnim = Tween<Offset>(
            begin: Offset(_introForward ? 0.3 : -0.3, 0),
            end: Offset.zero,
          ).animate(CurveTween(curve: Curves.easeOut).animate(anim));
          return ClipRect(
            child: SlideTransition(
              position: offsetAnim,
              child: FadeTransition(opacity: anim, child: child),
            ),
          );
        },
        child: Padding(
          key: ValueKey(_introPage),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              [
                "Let's craft a powerful habit statement.",
                "You'll fill in 3 quick pieces.",
                "Then we'll set a reminder.",
              ][_introPage],
              style: GoogleFonts.gabarito(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditableSentence() {
    final cs = Theme.of(context).colorScheme;
    TextStyle base = GoogleFonts.gabarito(
      fontSize: 22,
      fontWeight: FontWeight.w500,
      color: cs.onSurface,
    );
    TextStyle underline = base.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: cs.primary,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        alignment: WrapAlignment.start,
        runSpacing: 8,
        children: [
          GestureDetector(
            onTap: () => _startEdit(0),
            child: Text(_values[0], style: underline),
          ),
          Text(' at ', style: base),
          GestureDetector(
            onTap: () => _startEdit(1),
            child: Text(_values[1], style: underline),
          ),
          Text(' so that I can become ', style: base),
          GestureDetector(
            onTap: () => _startEdit(2),
            child: Text(_values[2], style: underline),
          ),
        ],
      ),
    );
  }

  Widget _buildEditSuggestions() {
    if (_editingIndex == null) return const SizedBox.shrink();
    final list = [
      habitSuggestions,
      cueSuggestions,
      goalSuggestions,
    ][_editingIndex!];
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: list
            .map(
              (s) => ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(
                  s,
                  style: GoogleFonts.gabarito(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () => _saveEdit(s, goNext: _editingIndex != 2),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildEditInput() {
    if (_editingIndex == null) return const SizedBox.shrink();
    final label = ['habit', 'time/location', 'type of person I want to be'];
    return SafeArea(
      top: false,
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _inputController,
              autofocus: true,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              cursorColor: Theme.of(context).colorScheme.primary,
              onSubmitted: (_) {
                if (_editingIndex == 2 && _isComplete) {
                  _finalizeAndContinue();
                } else {
                  _saveEdit(null, goNext: true);
                }
              },
              decoration: InputDecoration(
                hintText: "Enter your ${label[_editingIndex!]}",
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back',
                  onPressed: _editingIndex == 0
                      ? null
                      : () => _saveEdit(null, goBack: true),
                ),
                if (_editingIndex == 2)
                  FilledButton(
                    onPressed: _isComplete ? _finalizeAndContinue : null,
                    child: const Text('Continue'),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded),
                    tooltip: 'Next',
                    onPressed: () => _saveEdit(null, goNext: true),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _editTitle {
    if (_editingIndex == null) return 'Add a habit';
    return ['What habit?', 'When/where?', 'Goal identity'][_editingIndex!];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _introPage < 3
            ? Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  _buildIntroSentence(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (_introPage > 0)
                          TextButton(
                            onPressed: _backIntro,
                            child: const Text('Back'),
                          )
                        else
                          const SizedBox(width: 60),
                        FilledButton(
                          onPressed: _nextIntro,
                          child: Text(_introPage < 2 ? 'Next' : 'Continue'),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 32,
                          left: 24,
                          right: 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _editTitle,
                              style: GoogleFonts.gabarito(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildEditableSentence(),
                            _buildEditSuggestions(),
                            const SizedBox(height: 50),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_isComplete && _editingIndex == null)
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _continueToReminders,
                            child: const Text('Continue'),
                          ),
                        ),
                      ),
                    ),
                  _buildEditInput(),
                ],
              ),
      ),
    );
  }
}
