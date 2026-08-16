import 'package:flutter/material.dart';

import '../models/hazard_report.dart';
import '../services/hazard_report_service.dart';
import '../utils/app_theme.dart';

class ReportHazardScreen extends StatefulWidget {
  const ReportHazardScreen({super.key});

  @override
  State<ReportHazardScreen> createState() => _ReportHazardScreenState();
}

class _ReportHazardScreenState extends State<ReportHazardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reportService = HazardReportService();
  final _location = TextEditingController(text: 'Baliwag, Bulacan, PH');
  final _description = TextEditingController();

  HazardType _type = HazardType.floodedRoad;
  String _severity = 'Moderate';
  List<HazardReport> _reports = const [];
  HazardReport? _editingReport;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  @override
  void dispose() {
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    final reports = await _reportService.getReports();
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _isLoading = false;
    });
  }

  Future<void> _saveReport() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final description = _description.text.trim();
    final location = _location.text.trim();
    final wasEditing = _editingReport != null;

    if (_editingReport == null) {
      await _reportService.createReport(
        type: _type,
        severity: _severity,
        location: location,
        description: description,
      );
    } else {
      await _reportService.updateReport(
        _editingReport!.copyWith(
          type: _type,
          severity: _severity,
          location: location,
          description: description,
        ),
      );
    }

    if (!mounted) return;
    _resetForm();
    await _loadReports();
    if (!mounted) return;
    setState(() => _isSaving = false);
    _message(wasEditing ? 'Hazard report updated.' : 'Hazard report created.');
  }

  Future<void> _deleteReport(HazardReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete report?'),
        content: Text(
          'This will permanently remove the ${hazardTypeLabel(report.type)} report.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _reportService.deleteReport(report.id);
    if (!mounted) return;
    if (_editingReport?.id == report.id) _resetForm();
    await _loadReports();
    if (mounted) _message('Hazard report deleted.');
  }

  void _editReport(HazardReport report) {
    setState(() {
      _editingReport = report;
      _type = report.type;
      _severity = report.severity;
      _location.text = report.location;
      _description.text = report.description;
    });
  }

  void _resetForm() {
    setState(() {
      _editingReport = null;
      _type = HazardType.floodedRoad;
      _severity = 'Moderate';
      _location.text = 'Baliwag, Bulacan, PH';
      _description.clear();
    });
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hazard Reports')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildForm(context),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Saved Reports',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text('${_reports.length} total'),
          ],
        ),
        const SizedBox(height: 10),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_reports.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.inbox_outlined, color: AppTheme.blue),
              title: Text('No hazard reports yet'),
              subtitle: Text('Create a report to store it on this device.'),
            ),
          )
        else
          ..._reports.map(_buildReportCard),
      ],
    ),
  );

  Widget _buildForm(BuildContext context) => Form(
    key: _formKey,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _editingReport == null ? 'Create Report' : 'Update Report',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            const Text(
              'Hazard Type',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: HazardType.values
                  .map(
                    (type) => ChoiceChip(
                      label: Text(hazardTypeLabel(type)),
                      selected: _type == type,
                      avatar: Icon(_icon(type), color: AppTheme.blue),
                      onSelected: (_) => setState(() => _type = type),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Location',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Location is required.';
                }
                if (value.trim().length < 3) {
                  return 'Enter a more specific location.';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),
            const Text(
              'Severity Level',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              children: ['Low', 'Moderate', 'High', 'Critical']
                  .map(
                    (value) => ChoiceChip(
                      label: Text(value),
                      selected: _severity == value,
                      onSelected: (_) => setState(() => _severity = value),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _description,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Description',
                hintText: 'Provide more details about the hazard.',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isNotEmpty && text.length < 8) {
                  return 'Use at least 8 characters or leave it blank.';
                }
                return null;
              },
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveReport,
                    icon: Icon(
                      _editingReport == null
                          ? Icons.add_circle_outline
                          : Icons.save_outlined,
                    ),
                    label: Text(
                      _editingReport == null ? 'Create Report' : 'Save Changes',
                    ),
                  ),
                ),
                if (_editingReport != null) ...[
                  const SizedBox(width: 10),
                  IconButton.outlined(
                    onPressed: _isSaving ? null : _resetForm,
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel editing',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildReportCard(HazardReport report) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: _severityColor(report.severity).withValues(alpha: .12),
        child: Icon(_icon(report.type), color: _severityColor(report.severity)),
      ),
      title: Text(
        hazardTypeLabel(report.type),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${report.location}\n${report.severity} severity'
        '${report.description.isEmpty ? '' : ' - ${report.description}'}',
      ),
      isThreeLine: true,
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            onPressed: () => _editReport(report),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit report',
          ),
          IconButton(
            onPressed: () => _deleteReport(report),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete report',
          ),
        ],
      ),
    ),
  );

  Color _severityColor(String severity) => switch (severity) {
    'Low' => Colors.green,
    'High' => Colors.orange,
    'Critical' => Colors.red,
    _ => AppTheme.blue,
  };

  IconData _icon(HazardType type) => switch (type) {
    HazardType.floodedRoad => Icons.directions_car_outlined,
    HazardType.cloggedDrainage => Icons.water_damage_outlined,
    HazardType.blockedWaterway => Icons.waves_outlined,
    HazardType.overflowingCanal => Icons.water_outlined,
  };
}
