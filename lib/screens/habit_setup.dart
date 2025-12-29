import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api_service.dart';
import 'reminder_setup_screen.dart';

class HabitSetup extends StatefulWidget {
  final String userName;
  final ApiService apiService;
  final Map<String, dynamic>? initialHabit;

  const HabitSetup({
    super.key,
    required this.userName,
    required this.apiService,
    this.initialHabit,
  });

  @override
  State<HabitSetup> createState() => _HabitSetupState();
}

class _HabitSetupState extends State<HabitSetup> {
  int? _editingIndex;
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
  bool _isEditing = false;
  bool _submitting = false;

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

  @override
  void initState() {
    super.initState();
    if (widget.initialHabit != null) {
      _isEditing = true;
      final h = widget.initialHabit!;
      _values[0] = (h['habitName'] ?? h['habit'] ?? _placeholders[0])
          .toString();
      _values[1] = (h['habitLocation'] ?? h['location'] ?? _placeholders[1])
          .toString();
      _values[2] = (h['habitGoal'] ?? h['goal'] ?? _placeholders[2]).toString();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _startEdit(int index) {
    setState(() {
      _editingIndex = index;
      _inputController.text = _values[index] == _placeholders[index]
          ? ""
          : _values[index];
    });
  }

  void _saveEdit(String? suggestion) {
    if (_editingIndex != null) {
      setState(() {
        _values[_editingIndex!] = (suggestion ?? _inputController.text).isEmpty
            ? _placeholders[_editingIndex!]
            : (suggestion ?? _inputController.text);
        _editingIndex = null;
        _inputController.clear();
      });
    }
  }

  Future<void> _saveHabit() async {
    if (_values.any((v) => _placeholders.contains(v) || v.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete the sentence first.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final id =
          (widget.initialHabit![r'$id'] ??
                  widget.initialHabit!['id'] ??
                  widget.initialHabit!['habitId'])
              .toString();
      final updatedHabit = await widget.apiService.editHabit(
        habitId: id,
        habitName: _values[0],
        habitLocation: _values[1],
        habitGoal: _values[2],
      );
      if (mounted) Navigator.pop(context, updatedHabit);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update habit: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _continueToReminders() async {
    if (_values.any((v) => _placeholders.contains(v) || v.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete the sentence first.')),
      );
      return;
    }

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

  Widget _buildEditableSentence() {
    final cs = Theme.of(context).colorScheme;
    final normalStyle = GoogleFonts.gabarito(fontSize: 24, color: cs.onSurface);
    final underlineStyle = normalStyle.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: cs.primary,
      decorationThickness: 2,
      decorationStyle: TextDecorationStyle.wavy,
    );
    final placeholderStyle = underlineStyle.copyWith(
      color: cs.onSurface.withOpacity(0.5),
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text("I will ", style: normalStyle),
            GestureDetector(
              onTap: () => _startEdit(0),
              child: Text(
                _values[0],
                style: _values[0] == _placeholders[0]
                    ? placeholderStyle
                    : underlineStyle,
              ),
            ),
            Text(", ", style: normalStyle),
            GestureDetector(
              onTap: () => _startEdit(1),
              child: Text(
                _values[1],
                style: _values[1] == _placeholders[1]
                    ? placeholderStyle
                    : underlineStyle,
              ),
            ),
            Text(" so that I can become ", style: normalStyle),
            GestureDetector(
              onTap: () => _startEdit(2),
              child: Text(
                _values[2],
                style: _values[2] == _placeholders[2]
                    ? placeholderStyle
                    : underlineStyle,
              ),
            ),
            Text(".", style: normalStyle),
          ],
        ),
      ),
    );
  }

  Widget _buildEditInput() {
    if (_editingIndex == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final suggestions = _editingIndex == 0
        ? habitSuggestions
        : (_editingIndex == 1 ? cueSuggestions : goalSuggestions);

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _inputController,
            autofocus: true,
            textAlign: TextAlign.center,
            style: GoogleFonts.gabarito(fontSize: 20, color: cs.onSurface),
            cursorColor: cs.primary,
            decoration: InputDecoration(
              hintText: _placeholders[_editingIndex!],
              border: InputBorder.none,
              hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.3)),
            ),
            onSubmitted: (_) => _saveEdit(null),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ActionChip(
                    label: Text(suggestions[index]),
                    onPressed: () => _saveEdit(suggestions[index]),
                    backgroundColor: cs.surface,
                    side: BorderSide(color: cs.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    labelStyle: GoogleFonts.gabarito(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _editingIndex = null),
                child: Text("Cancel", style: GoogleFonts.gabarito()),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _saveEdit(null),
                child: Text("Done", style: GoogleFonts.gabarito()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = !_values.any(
      (v) => _placeholders.contains(v) || v.trim().isEmpty,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Habit' : 'New Habit',
          style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [_buildEditableSentence()],
                ),
              ),
            ),
          ),
          if (_editingIndex != null)
            _buildEditInput()
          else
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isEditing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : _editReminders,
                          icon: const Icon(Icons.alarm),
                          label: Text(
                            "Edit Reminders",
                            style: GoogleFonts.gabarito(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _submitting
                          ? null
                          : (isComplete
                                ? (_isEditing
                                      ? _saveHabit
                                      : _continueToReminders)
                                : null),
                      child: _submitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isEditing ? "Save" : "Continue",
                              style: GoogleFonts.gabarito(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _editReminders() async {
    if (_values.any((v) => _placeholders.contains(v) || v.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete the sentence first.')),
      );
      return;
    }

    final id =
        (widget.initialHabit![r'$id'] ??
                widget.initialHabit!['id'] ??
                widget.initialHabit!['habitId'])
            .toString();

    List<String>? currentReminders;
    if (widget.initialHabit!['habitReminder'] is List) {
      currentReminders = List<String>.from(
        widget.initialHabit!['habitReminder'].map((e) => e.toString()),
      );
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReminderSetupScreen(
          apiService: widget.apiService,
          habitName: _values[0].trim(),
          habitCue: _values[1].trim(),
          habitGoal: _values[2].trim(),
          existingHabitId: id,
          initialReminders: currentReminders,
        ),
      ),
    );
  }
}
