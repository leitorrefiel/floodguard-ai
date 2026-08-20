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
  final _search = TextEditingController();

  HazardType _type = HazardType.floodedRoad;
  String _severity = 'Moderate';
  String _severityFilter = 'All';
  HazardType? _typeFilter;
  List<HazardReport> _reports = const [];
  HazardReport? _editingReport;
  String _storageLabel = 'Local device storage';
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
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    final reports = await _reportService.getReports();
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _storageLabel = _reportService.storageLabel;
      _isLoading = false;
    });
  }

  Future<void> _saveReport() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final description = _description.text.trim();
    final location = _location.text.trim();
    final wasEditing = _editingReport != null;

    try {
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
      _message(
        '${wasEditing ? 'Hazard report updated' : 'Hazard report created'} via $_storageLabel.',
      );
    } catch (_) {
      if (mounted) _message('Unable to save the hazard report.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
    if (mounted) _message('Hazard report deleted via $_storageLabel.');
  }

  List<HazardReport> get _filteredReports {
    final query = _search.text.trim().toLowerCase();
    return _reports.where((report) {
      final matchesText =
          query.isEmpty ||
          hazardTypeLabel(report.type).toLowerCase().contains(query) ||
          report.location.toLowerCase().contains(query) ||
          report.description.toLowerCase().contains(query);
      final matchesSeverity =
          _severityFilter == 'All' || report.severity == _severityFilter;
      final matchesType = _typeFilter == null || report.type == _typeFilter;
      return matchesText && matchesSeverity && matchesType;
    }).toList();
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
  Widget build(BuildContext context) {
    final filteredReports = _filteredReports;
    return Scaffold(
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
              Text('${filteredReports.length}/${_reports.length} shown'),
            ],
          ),
          const SizedBox(height: 4),
          Text('Storage: $_storageLabel'),
          const SizedBox(height: 10),
          _buildFilters(),
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
                subtitle: Text('Create a report to store it with the API.'),
              ),
            )
          else if (filteredReports.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.search_off_outlined, color: AppTheme.blue),
                title: Text('No matching reports'),
                subtitle: Text('Clear search or filters to view all reports.'),
              ),
            )
          else
            ...filteredReports.map(_buildReportCard),
        ],
      ),
    );
  }

  Widget _buildFilters() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Search reports',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear search',
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _severityFilter,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Severity filter',
            ),
            items: ['All', 'Low', 'Moderate', 'High', 'Critical']
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _severityFilter = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<HazardType?>(
            initialValue: _typeFilter,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Hazard type filter',
            ),
            items: [
              const DropdownMenuItem<HazardType?>(
                value: null,
                child: Text('All hazard types'),
              ),
              ...HazardType.values.map(
                (type) => DropdownMenuItem<HazardType?>(
                  value: type,
                  child: Text(hazardTypeLabel(type)),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _typeFilter = value),
          ),
        ],
      ),
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
