import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HabitSetup extends StatefulWidget {
  final String userName;
  const HabitSetup({super.key, required this.userName});

  @override
  State<HabitSetup> createState() => _HabitSetupState();
}

class _HabitSetupState extends State<HabitSetup> {
  int _introPage = 0; // 0, 1, 2 for intro, 3 for edit
  int? _editingIndex; // null if not editing, 0/1/2 for which part
  final List<String> _values = [
    "habit",
    "time/location",
    "type of person I want to be",
  ];
  final List<String> _placeholders = [
    "habit",
    "time/location",
    "type of person I want to be",
  ];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const habitSuggestions = [
    'exercise',
    'study',
    'put on my running shoes',
    'take a deep breath',
    'meditate for 10 minutes',
    'write one sentence',
    'text one friend',
    'read 20 pages',
    'pray',
    'go for a walk',
    'eat one bite of salad',
  ];
  static const cueSuggestions = [
    'when I wake up',
    'every day at 7am',
    'after I finish breakfast',
    'in the bathroom',
    'when I close my laptop',
  ];
  static const goalSuggestions = [
    'a stronger person',
    'a smarter person',
    'an active person',
    'a mindful person',
    'a dedicated musician',
    'a writer',
    'a healthy person',
  ];

  final bool _suggestionsExpanded = true;
  bool _introForward = true;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _nextIntro() {
    _introForward = true;
    if (_introPage < 2) {
      setState(() => _introPage++);
    } else {
      setState(() => _introPage = 3);
    }
  }

  void _backIntro() {
    _introForward = false;
    if (_introPage > 0) {
      setState(() => _introPage--);
    }
  }

  void _startEdit(int index) {
    setState(() {
      _editingIndex = index;
      _inputController.text = _values[index] == _placeholders[index]
          ? ""
          : _values[index];
    });
  }

  void _saveEdit(
    String? suggestion, {
    bool goNext = false,
    bool goBack = false,
  }) {
    if (_editingIndex != null) {
      setState(() {
        _values[_editingIndex!] = (suggestion ?? _inputController.text).isEmpty
            ? _placeholders[_editingIndex!]
            : (suggestion ?? _inputController.text);
        if (goNext && _editingIndex! < 2) {
          _editingIndex = _editingIndex! + 1;
          _inputController.text =
              _values[_editingIndex!] == _placeholders[_editingIndex!]
              ? ""
              : _values[_editingIndex!];
        } else if (goBack && _editingIndex! > 0) {
          _editingIndex = _editingIndex! - 1;
          _inputController.text =
              _values[_editingIndex!] == _placeholders[_editingIndex!]
              ? ""
              : _values[_editingIndex!];
        } else {
          _editingIndex = null;
          _inputController.clear();
        }
      });
    }
  }

  Widget _buildIntroSentence() {
    final normal = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;
    TextStyle titleStyle = GoogleFonts.gabarito(
      fontSize: 26,
      fontWeight: FontWeight.bold,
      color: normal,
    );
    TextStyle descStyle = GoogleFonts.gabarito(
      fontSize: 16,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    TextStyle normalStyle = GoogleFonts.gabarito(fontSize: 18, color: normal);
    TextStyle underlineStyle = normalStyle.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: primary,
      decorationThickness: 2,
      decorationStyle: TextDecorationStyle.wavy,
    );

    const titles = ["Define your habit", "Get specific", "Goal"];
    const descriptions = [
      "A habit is a regular practice that is small and easy. It makes a big difference in your life in the long term.",
      "Set a time and place so that you don't just sit around and wait for motivation to hit you.",
      "The best form of motivation is always knowing your goal.",
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final pos =
            Tween<Offset>(
              begin: _introForward
                  ? const Offset(0.15, 0)
                  : const Offset(-0.15, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        final scale = Tween<double>(
          begin: 0.98,
          end: 1,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: pos,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
      child: Padding(
        key: ValueKey<int>(_introPage),
        padding: const EdgeInsets.only(bottom: 0, left: 24, right: 24, top: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titles[_introPage],
              style: titleStyle,
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 6),
            Text(
              descriptions[_introPage],
              style: descStyle,
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              child: Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("I will ", style: normalStyle),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      style: _introPage == 0 ? underlineStyle : normalStyle,
                      child: const Text("exercise"),
                    ),
                    Text(", ", style: normalStyle),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      style: _introPage == 1 ? underlineStyle : normalStyle,
                      child: const Text("when I wake up"),
                    ),
                    Text(" so that I can become a ", style: normalStyle),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      style: _introPage == 2 ? underlineStyle : normalStyle,
                      child: const Text("a stronger person"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroSuggestions() {
    final normal = Theme.of(context).colorScheme.onSurface;
    final suggestions = [
      habitSuggestions,
      cueSuggestions,
      goalSuggestions,
    ][_introPage];

    return SizedBox(
      height: 120,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: suggestions.length,
        itemBuilder: (context, idx) => ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 0,
          ),
          minVerticalPadding: 0,
          title: Text(
            suggestions[idx],
            style: GoogleFonts.gabarito(fontSize: 16, color: normal),
          ),
          onTap: () {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
            );
          },
        ),
      ),
    );
  }

  Widget _buildEditableSentence() {
    final normal = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;
    final faded = Theme.of(context).colorScheme.onSurface.withOpacity(0.5);

    TextStyle normalStyle = GoogleFonts.gabarito(fontSize: 20, color: normal);
    TextStyle underlineStyle = normalStyle.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: primary,
      decorationThickness: 2,
      decorationStyle: TextDecorationStyle.wavy,
    );
    TextStyle fadedUnderlineStyle = normalStyle.copyWith(
      color: faded,
      decoration: TextDecoration.underline,
      decorationColor: primary,
      decorationThickness: 2,
      decorationStyle: TextDecorationStyle.wavy,
    );

    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text("I will ", style: normalStyle),
          GestureDetector(
            onTap: () => _startEdit(0),
            child: Text(
              _values[0],
              style: _editingIndex == 0 ? fadedUnderlineStyle : underlineStyle,
            ),
          ),
          Text(", ", style: normalStyle),
          GestureDetector(
            onTap: () => _startEdit(1),
            child: Text(
              _values[1],
              style: _editingIndex == 1 ? fadedUnderlineStyle : underlineStyle,
            ),
          ),
          Text(" so that I can become ", style: normalStyle),
          GestureDetector(
            onTap: () => _startEdit(2),
            child: Text(
              _values[2],
              style: _editingIndex == 2 ? fadedUnderlineStyle : underlineStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditInput() {
    if (_editingIndex == null) return const SizedBox.shrink();

    final label = ["habit", "time/location", "type of person I want to be"];

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
              onSubmitted: (_) => _saveEdit(null),
              decoration: InputDecoration(
                hintText: "Enter your ${label[_editingIndex!]}",
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
                  tooltip: "Back",
                  onPressed: _editingIndex == 0
                      ? null
                      : () => _saveEdit(null, goBack: true),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  tooltip: "Next",
                  onPressed: _editingIndex == 2
                      ? null
                      : () => _saveEdit(null, goNext: true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _editTitle {
    if (_editingIndex == 0) return "Define your habit";
    if (_editingIndex == 1) return "Get specific";
    if (_editingIndex == 2) return "Goal";
    return "Add a habit";
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
                            child: const Text("Back"),
                          )
                        else
                          const SizedBox(width: 60),
                        FilledButton(
                          onPressed: _nextIntro,
                          child: Text(_introPage < 2 ? "Next" : "Continue"),
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
                          top: 32.0,
                          left: 24,
                          right: 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _editingIndex == null
                                  ? "Add a habit"
                                  : _editTitle,
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
                  _buildEditInput(),
                ],
              ),
      ),
    );
  }

  Widget _buildEditSuggestions() {
    if (_editingIndex == null) return const SizedBox.shrink();
    final normal = Theme.of(context).colorScheme.onSurface;
    final suggestions = [
      habitSuggestions,
      cueSuggestions,
      goalSuggestions,
    ][_editingIndex!];

    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          color: Theme.of(context).colorScheme.primaryContainer,
        ),
        child: Column(
          // i want to change background color of this Column and columns DO NOT support decoration:.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 12.0,
              ),
              child: Text(
                "Choose one below or enter your own",
                style: GoogleFonts.gabarito(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            ...suggestions.map((suggestion) {
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 0,
                ),
                minVerticalPadding: 0,
                title: Text(
                  suggestion,
                  style: GoogleFonts.gabarito(fontSize: 16, color: normal),
                ),
                onTap: () {
                  _saveEdit(suggestion, goNext: true);
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
