// lib/pages/medication/add_medication_page.dart

import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_manager_service.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_schedule_model.dart';
import 'package:flutter/material.dart';

class AddMedicationPage extends StatefulWidget {
  final MedicationManager medicationManager;
  final Medication? existingMedication;
  final MedicationSchedule? existingSchedule;

  const AddMedicationPage({
    Key? key,
    required this.medicationManager,
    this.existingMedication,
    this.existingSchedule,
  }) : super(key: key);

  @override
  State<AddMedicationPage> createState() => _AddMedicationPageState();
}

class _AddMedicationPageState extends State<AddMedicationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _instructionsController = TextEditingController();

  String _selectedColor = '#3498db';
  String _selectedIcon = '💊';
  DosageUnit _selectedUnit = DosageUnit.mg;
  double _dosage = 0.0;

  // Scheduling variables
  MedicationFrequency _selectedFrequency = MedicationFrequency.daily;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  final List<TimeOfDay> _selectedTimes = [];
  final List<int> _selectedDays = []; // 0-6 for Monday-Sunday
  final List<DateTime> _selectedCustomDates = [];
  int _reminderMinutesBefore = 15;

  // Color options for medication
  final List<Map<String, dynamic>> _colorOptions = [
    {'color': '#3498db', 'name': 'Blue'},
    {'color': '#e74c3c', 'name': 'Red'},
    {'color': '#2ecc71', 'name': 'Green'},
    {'color': '#f39c12', 'name': 'Orange'},
    {'color': '#9b59b6', 'name': 'Purple'},
    {'color': '#1abc9c', 'name': 'Teal'},
  ];

  // Icon options for medication
  final List<String> _iconOptions = [
    '💊',
    '💉',
    '🩺',
    '❤️',
    '🧠',
    '🦴',
    '👁️',
    '👂',
    '🫀',
    '🫁',
    '🧴',
  ];

  // Day options
  final List<Map<String, dynamic>> _dayOptions = [
    {'index': 0, 'name': 'Monday', 'short': 'Mon'},
    {'index': 1, 'name': 'Tuesday', 'short': 'Tue'},
    {'index': 2, 'name': 'Wednesday', 'short': 'Wed'},
    {'index': 3, 'name': 'Thursday', 'short': 'Thu'},
    {'index': 4, 'name': 'Friday', 'short': 'Fri'},
    {'index': 5, 'name': 'Saturday', 'short': 'Sat'},
    {'index': 6, 'name': 'Sunday', 'short': 'Sun'},
  ];

  @override
  void initState() {
    super.initState();
    // Pre-fill form if editing existing medication
    if (widget.existingMedication != null) {
      _nameController.text = widget.existingMedication!.name;
      _dosageController.text = widget.existingMedication!.dosage.toString();
      _descriptionController.text =
          widget.existingMedication!.description ?? '';
      _selectedColor = widget.existingMedication!.color;
      _selectedIcon = widget.existingMedication!.icon;
      _selectedUnit = widget.existingMedication!.unit;
      _dosage = widget.existingMedication!.dosage;
    }

    // Pre-fill schedule if editing existing schedule
    if (widget.existingSchedule != null) {
      _selectedFrequency = widget.existingSchedule!.frequency;
      _startDate = widget.existingSchedule!.startDate;
      _endDate = widget.existingSchedule!.endDate;
      _selectedTimes.addAll(widget.existingSchedule!.timesPerDay);
      _selectedDays.addAll(widget.existingSchedule!.daysOfWeek);
      _selectedCustomDates.addAll(widget.existingSchedule!.specificDates);
      _instructionsController.text =
          widget.existingSchedule!.instructions ?? '';
      _reminderMinutesBefore = widget.existingSchedule!.reminderMinutesBefore;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _descriptionController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  void _saveMedication() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      // Validate scheduling
      if (_selectedTimes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add at least one intake time')),
        );
        return;
      }

      if (_selectedFrequency == MedicationFrequency.weekly &&
          _selectedDays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one day for weekly schedule'),
          ),
        );
        return;
      }

      if (_selectedFrequency == MedicationFrequency.custom &&
          _selectedCustomDates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please select at least one date for custom schedule',
            ),
          ),
        );
        return;
      }

      final medication = Medication(
        medicationId: widget.existingMedication?.medicationId,
        name: _nameController.text.trim(),
        dosage: _dosage,
        unit: _selectedUnit,
        description:
            _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
        color: _selectedColor,
        icon: _selectedIcon,
      );

      // Create schedule
      final schedule = MedicationSchedule(
        scheduleId: widget.existingSchedule?.scheduleId,
        medication: medication,
        startDate: _startDate,
        endDate: _endDate,
        frequency: _selectedFrequency,
        timesPerDay: _selectedTimes,
        daysOfWeek: _selectedDays,
        specificDates: _selectedCustomDates,
        instructions:
            _instructionsController.text.trim().isEmpty
                ? null
                : _instructionsController.text.trim(),
        reminderMinutesBefore: _reminderMinutesBefore,
      );

      // Add medication and schedule to manager
      widget.medicationManager.addMedication(medication);
      widget.medicationManager.createSchedule(schedule);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${medication.name} ${widget.existingMedication != null ? 'updated' : 'added'} successfully',
          ),
        ),
      );

      Navigator.pop(context, medication);
    }
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Choose Color'),
            content: SizedBox(
              width: double.maxFinite,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _colorOptions.length,
                itemBuilder: (context, index) {
                  final colorOption = _colorOptions[index];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedColor = colorOption['color'];
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: _parseColor(colorOption['color']),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              _selectedColor == colorOption['color']
                                  ? Colors.black
                                  : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          colorOption['name'],
                          style: TextStyle(
                            color: _getTextColor(
                              _parseColor(colorOption['color']),
                            ),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
    );
  }

  void _showIconPicker() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Choose Icon'),
            content: SizedBox(
              width: double.maxFinite,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _iconOptions.length,
                itemBuilder: (context, index) {
                  final icon = _iconOptions[index];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIcon = icon;
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            _selectedIcon == icon
                                ? Colors.blue.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(icon, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
    );
  }

  Future<void> _addTime() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime != null) {
      setState(() {
        _selectedTimes.add(pickedTime);
        _selectedTimes.sort((a, b) => a.hour.compareTo(b.hour));
      });
    }
  }

  void _removeTime(TimeOfDay time) {
    setState(() {
      _selectedTimes.remove(time);
    });
  }

  void _toggleDay(int dayIndex) {
    setState(() {
      if (_selectedDays.contains(dayIndex)) {
        _selectedDays.remove(dayIndex);
      } else {
        _selectedDays.add(dayIndex);
      }
      _selectedDays.sort();
    });
  }

  Future<void> _pickStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<void> _addCustomDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedCustomDates.add(picked);
        _selectedCustomDates.sort((a, b) => a.compareTo(b));
      });
    }
  }

  void _removeCustomDate(DateTime date) {
    setState(() {
      _selectedCustomDates.remove(date);
    });
  }

  Color _parseColor(String colorHex) {
    try {
      return Color(int.parse(colorHex.substring(1, 7), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.blue;
    }
  }

  Color _getTextColor(Color backgroundColor) {
    final luminance =
        (0.299 * backgroundColor.red +
            0.587 * backgroundColor.green +
            0.114 * backgroundColor.blue) /
        255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  Widget _buildFrequencySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Schedule Frequency',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<MedicationFrequency>(
          value: _selectedFrequency,
          decoration: const InputDecoration(
            labelText: 'Frequency',
            border: OutlineInputBorder(),
          ),
          items:
              MedicationFrequency.values.map((frequency) {
                return DropdownMenuItem<MedicationFrequency>(
                  value: frequency,
                  child: Text(_getFrequencyDisplayName(frequency)),
                );
              }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedFrequency = value!;
            });
          },
        ),
      ],
    );
  }

  Widget _buildDaysSection() {
    if (_selectedFrequency != MedicationFrequency.weekly)
      return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Select Days',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _dayOptions.map((day) {
                final isSelected = _selectedDays.contains(day['index']);
                return FilterChip(
                  label: Text(day['short']),
                  selected: isSelected,
                  onSelected: (selected) => _toggleDay(day['index']),
                  selectedColor: Colors.blue.withOpacity(0.2),
                  checkmarkColor: Colors.blue,
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildTimesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Intake Times',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: _addTime,
              icon: const Icon(Icons.add_alarm),
              tooltip: 'Add Time',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selectedTimes.isEmpty)
          const Text(
            'No times added. Tap the + button to add intake times.',
            style: TextStyle(color: Colors.grey),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                _selectedTimes.map((time) {
                  return Chip(
                    label: Text(_formatTime(time)),
                    onDeleted: () => _removeTime(time),
                    deleteIconColor: Colors.red,
                  );
                }).toList(),
          ),
      ],
    );
  }

  Widget _buildCustomDatesSection() {
    if (_selectedFrequency != MedicationFrequency.custom)
      return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Specific Dates',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: _addCustomDate,
              icon: const Icon(Icons.add_circle),
              tooltip: 'Add Date',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selectedCustomDates.isEmpty)
          const Text(
            'No dates added. Tap the + button to add specific dates.',
            style: TextStyle(color: Colors.grey),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                _selectedCustomDates.map((date) {
                  return Chip(
                    label: Text(_formatDate(date)),
                    onDeleted: () => _removeCustomDate(date),
                    deleteIconColor: Colors.red,
                  );
                }).toList(),
          ),
      ],
    );
  }

  Widget _buildDateRangeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Schedule Dates',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ListTile(
                title: const Text('Start Date'),
                subtitle: Text(_formatDate(_startDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickStartDate,
              ),
            ),
            Expanded(
              child: ListTile(
                title: const Text('End Date (Optional)'),
                subtitle: Text(
                  _endDate != null ? _formatDate(_endDate!) : 'No end date',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _pickEndDate,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReminderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Reminder Settings',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: _reminderMinutesBefore,
          decoration: const InputDecoration(
            labelText: 'Remind Before',
            border: OutlineInputBorder(),
          ),
          items:
              [5, 10, 15, 30, 60].map((minutes) {
                return DropdownMenuItem<int>(
                  value: minutes,
                  child: Text('$minutes minutes before'),
                );
              }).toList(),
          onChanged: (value) {
            setState(() {
              _reminderMinutesBefore = value!;
            });
          },
        ),
      ],
    );
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _getFrequencyDisplayName(MedicationFrequency frequency) {
    switch (frequency) {
      case MedicationFrequency.daily:
        return 'Daily';
      case MedicationFrequency.weekly:
        return 'Weekly';
      case MedicationFrequency.monthly:
        return 'Monthly';
      case MedicationFrequency.asNeeded:
        return 'As Needed';
      case MedicationFrequency.custom:
        return 'Custom Dates';
    }
  }

  String _getUnitDisplayName(DosageUnit unit) {
    switch (unit) {
      case DosageUnit.mg:
        return 'mg';
      case DosageUnit.mcg:
        return 'mcg';
      case DosageUnit.ml:
        return 'ml';
      case DosageUnit.tablet:
        return 'Tablet';
      case DosageUnit.capsule:
        return 'Capsule';
      case DosageUnit.drop:
        return 'Drop';
      case DosageUnit.spray:
        return 'Spray';
      case DosageUnit.puff:
        return 'Puff';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingMedication != null
              ? 'Edit Medication'
              : 'Add New Medication',
        ),
        actions: [
          IconButton(onPressed: _saveMedication, icon: const Icon(Icons.save)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Medication Icon & Color Selection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Appearance',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          // Icon Selection
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Icon'),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: _showIconPicker,
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _selectedIcon,
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 20),
                          // Color Selection
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Color'),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: _showColorPicker,
                                  child: Container(
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: _parseColor(_selectedColor),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Selected Color',
                                        style: TextStyle(
                                          color: _getTextColor(
                                            _parseColor(_selectedColor),
                                          ),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Medication Details
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Medication Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Medication Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Medication Name*',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.medication),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter medication name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Dosage and Unit
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _dosageController,
                              decoration: const InputDecoration(
                                labelText: 'Dosage*',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter dosage';
                                }
                                final dosage = double.tryParse(value);
                                if (dosage == null || dosage <= 0) {
                                  return 'Please enter a valid dosage';
                                }
                                return null;
                              },
                              onSaved: (value) {
                                _dosage = double.parse(value!);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<DosageUnit>(
                              value: _selectedUnit,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  DosageUnit.values.map((unit) {
                                    return DropdownMenuItem<DosageUnit>(
                                      value: unit,
                                      child: Text(_getUnitDisplayName(unit)),
                                    );
                                  }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedUnit = value!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Description
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description (Optional)',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),

                      // Instructions
                      TextFormField(
                        controller: _instructionsController,
                        decoration: const InputDecoration(
                          labelText: 'Instructions (Optional)',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Scheduling Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Scheduling',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      _buildFrequencySection(),
                      _buildDaysSection(),
                      _buildTimesSection(),
                      _buildCustomDatesSection(),
                      _buildDateRangeSection(),
                      _buildReminderSection(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Save Button
              ElevatedButton(
                onPressed: _saveMedication,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: Text(
                  widget.existingMedication != null
                      ? 'Update Medication'
                      : 'Save Medication',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
