// lib/pages/medication/add_medication_page.dart

import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_manager_service.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:flutter/material.dart';

class AddMedicationPage extends StatefulWidget {
  final MedicationManager medicationManager;
  final Medication? existingMedication;

  const AddMedicationPage({
    Key? key,
    required this.medicationManager,
    this.existingMedication,
  }) : super(key: key);

  @override
  State<AddMedicationPage> createState() => _AddMedicationPageState();
}

class _AddMedicationPageState extends State<AddMedicationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedColor = '#3498db';
  String _selectedIcon = '💊';
  DosageUnit _selectedUnit = DosageUnit.mg;
  double _dosage = 0.0;

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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _saveMedication() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

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

      if (widget.existingMedication != null) {
        // Update existing medication
        // You might want to add an update method to your MedicationManager
        widget.medicationManager.addMedication(medication);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${medication.name} updated successfully')),
        );
      } else {
        // Add new medication
        widget.medicationManager.addMedication(medication);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${medication.name} added successfully')),
        );
      }

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

  Color _parseColor(String colorHex) {
    try {
      return Color(int.parse(colorHex.substring(1, 7), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.blue;
    }
  }

  Color _getTextColor(Color backgroundColor) {
    // Calculate the perceptive luminance - human eye favors green color
    final luminance =
        (0.299 * backgroundColor.red +
            0.587 * backgroundColor.green +
            0.114 * backgroundColor.blue) /
        255;

    return luminance > 0.5 ? Colors.black : Colors.white;
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
                        textInputAction: TextInputAction.done,
                      ),
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
}
