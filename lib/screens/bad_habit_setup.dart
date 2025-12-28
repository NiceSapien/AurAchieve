import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api_service.dart';

class BadHabitSetup extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic>? initialHabit;

  const BadHabitSetup({super.key, required this.apiService, this.initialHabit});

  @override
  State<BadHabitSetup> createState() => _BadHabitSetupState();
}

class _BadHabitSetupState extends State<BadHabitSetup> {
  int? _editingIndex;
  final List<String> _values = ["bad habit", "consequence"];
  final List<String> _placeholders = ["bad habit", "consequence"];
  final TextEditingController _inputController = TextEditingController();
  String _severity = 'average';
  bool _submitting = false;
  bool _isEditing = false;

  final Map<String, String> _severityLabels = {
    'average': "Somewhat Bad",
    'high': "Bad",
    'vhigh': "Very Bad",
    'extreme': "Extremely Bad",
  };

  static const habitSuggestions = [
    'bite my nails',
    'smoke cigarettes',
    'procrastinate',
    'eat junk food',
    'stay up too late',
    'spend too much money',
    'check my phone too often',
    'skip the gym',
    'interrupt people',
  ];

  static const consequenceSuggestions = [
    'I will get sick',
    'I will lose money',
    'I will waste time',
    'I will feel guilty',
    'my health will suffer',
    'I will be stressed',
    'I will regret it',
    'I will lose focus',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialHabit != null) {
      _isEditing = true;
      final h = widget.initialHabit!;
      _values[0] = (h['habitName'] ?? h['habit'] ?? _placeholders[0])
          .toString();
      _values[1] = (h['habitGoal'] ?? h['goal'] ?? _placeholders[1]).toString();
      _severity = (h['severity'] ?? 'average').toString();
      if (!_severityLabels.containsKey(_severity)) _severity = 'average';
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

  Future<void> _submit() async {
    if (_values[0] == _placeholders[0] || _values[0].trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a bad habit')));
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_isEditing) {
        final id =
            (widget.initialHabit![r'$id'] ??
                    widget.initialHabit!['id'] ??
                    widget.initialHabit!['habitId'])
                .toString();
        final updated = await widget.apiService.editBadHabit(
          habitId: id,
          habitName: _values[0].trim(),
          severity: _severity,
          habitGoal: _values[1] == _placeholders[1] ? '' : _values[1].trim(),
        );
        if (mounted) Navigator.pop(context, updated);
      } else {
        await widget.apiService.createBadHabit(
          habitName: _values[0].trim(),
          severity: _severity,
          habitGoal: _values[1] == _placeholders[1] ? '' : _values[1].trim(),
        );
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${_isEditing ? 'update' : 'add'} bad habit: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
            Text("If I ", style: normalStyle),
            GestureDetector(
              onTap: () => _startEdit(0),
              child: Text(
                _values[0],
                style: _values[0] == _placeholders[0]
                    ? placeholderStyle
                    : underlineStyle,
              ),
            ),
            Text(", then ", style: normalStyle),
            GestureDetector(
              onTap: () => _startEdit(1),
              child: Text(
                _values[1],
                style: _values[1] == _placeholders[1]
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

  Widget _buildSeveritySelector() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          "How bad is this habit?",
          style: GoogleFonts.gabarito(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: _severityLabels.entries.map((entry) {
            final isSelected = _severity == entry.key;
            return ChoiceChip(
              label: Text(entry.value),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) setState(() => _severity = entry.key);
              },
              labelStyle: GoogleFonts.gabarito(
                color: isSelected ? cs.onPrimary : cs.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              selectedColor: cs.primary,
              checkmarkColor: cs.onPrimary,
              backgroundColor: cs.surfaceContainerHighest,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildEditInput() {
    if (_editingIndex == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final suggestions = _editingIndex == 0
        ? habitSuggestions
        : consequenceSuggestions;

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
    final cs = Theme.of(context).colorScheme;
    final isComplete =
        _values[0] != _placeholders[0] && _values[0].trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Bad Habit' : 'New Bad Habit',
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
                  children: [
                    _buildEditableSentence(),
                    if (_editingIndex == null) ...[
                      const SizedBox(height: 48),
                      _buildSeveritySelector(),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_editingIndex != null)
            _buildEditInput()
          else
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: isComplete && !_submitting ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  ),
                  child: _submitting
                      ? SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onError,
                          ),
                        )
                      : Text(
                          _isEditing ? "Save" : "Break this habit",
                          style: GoogleFonts.gabarito(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
