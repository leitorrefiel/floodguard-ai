import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../models/hazard_report.dart';
import '../services/device_location_service.dart';
import '../services/hazard_report_service.dart';
import '../utils/app_theme.dart';
import 'evacuation_centers_screen.dart';

class ReportHazardScreen extends StatefulWidget {
  const ReportHazardScreen({super.key});

  @override
  State<ReportHazardScreen> createState() => _ReportHazardScreenState();
}

class _ReportHazardScreenState extends State<ReportHazardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reportService = HazardReportService();
  final _locationService = DeviceLocationService();
  final _imagePicker = ImagePicker();
  final _location = TextEditingController(text: 'Baliwag, Bulacan, PH');
  final _description = TextEditingController();
  final _otherType = TextEditingController();

  HazardType _type = HazardType.floodedRoad;
  String _severity = 'Moderate';
  DeviceLocation? _userCurrentLocation;
  ml.LatLng? _hazardReportLocation;
  XFile? _photo;
  List<HazardReport> _reports = const [];
  HazardReport? _editingReport;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _loadReports();
    _loadDefaultLocation();
  }

  @override
  void dispose() {
    _location.dispose();
    _description.dispose();
    _otherType.dispose();
    super.dispose();
  }

  Future<void> _loadDefaultLocation() async {
    setState(() => _isLocating = true);
    try {
      final saved = await _locationService.getSavedLocation();
      final current = saved ?? await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _userCurrentLocation = current;
        _hazardReportLocation = ml.LatLng(current.latitude, current.longitude);
        _location.text = current.label;
      });
    } on LocationAccessException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('Unable to get your location right now.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _loadReports() async {
    final reports = await _reportService.getReports();
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _isLoading = false;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 78,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;
    setState(() => _photo = picked);
  }

  Future<void> _saveReport({bool skipDuplicateCheck = false}) async {
    if (!_formKey.currentState!.validate()) return;
    final hazardPoint = _hazardReportLocation;
    if (hazardPoint == null) {
      _message('Hazard location is required.');
      return;
    }

    if (!skipDuplicateCheck && _editingReport == null) {
      final duplicates = await _reportService.findSimilarReports(
        type: _type,
        latitude: hazardPoint.latitude,
        longitude: hazardPoint.longitude,
      );
      if (duplicates.isNotEmpty && mounted) {
        await _showDuplicateDialog(duplicates.first);
        return;
      }
    }

    setState(() => _isSaving = true);
    final description = _description.text.trim();
    final location = _location.text.trim();
    final otherHazardType = _type == HazardType.other
        ? _otherType.text.trim()
        : null;
    final wasEditing = _editingReport != null;

    HazardReport? savedReport;
    final selectedPhotoPath = _photo?.path;
    try {
      if (_editingReport == null) {
        savedReport = await _reportService.createReport(
          type: _type,
          severity: _severity,
          location: location,
          description: description,
          latitude: hazardPoint.latitude,
          longitude: hazardPoint.longitude,
          localPhotoPath: _photo?.path,
          otherHazardType: otherHazardType,
        );
      } else {
        savedReport = await _reportService.updateReport(
          _editingReport!.copyWith(
            type: _type,
            severity: _severity,
            location: location,
            description: description,
            latitude: hazardPoint.latitude,
            longitude: hazardPoint.longitude,
            photoUrl: _photo?.path ?? _editingReport!.photoUrl,
            otherHazardType: otherHazardType,
            status: _editingReport!.isVerified
                ? HazardReportStatus.pending
                : _editingReport!.status,
            isVerified: false,
          ),
        );
      }

      if (!mounted) return;
      final photoWarning = _reportService.lastPhotoUploadError;
      _logSubmittedReport(savedReport);
      _resetForm();
      await _loadReports();
      if (!mounted) return;
      await _showSubmitSuccess(
        wasEditing: wasEditing,
        report: savedReport,
        failedPhotoPath: photoWarning == null ? null : selectedPhotoPath,
      );
    } catch (_) {
      if (mounted) _message('Unable to save the hazard report.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showDuplicateDialog(HazardReport existing) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Similar ${hazardTypeLabel(existing.type)} report nearby'),
        content: Text(
          'A similar active community report already exists near this location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'view'),
            child: const Text('View Existing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'confirm'),
            child: const Text('Confirm This Hazard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'submit'),
            child: const Text('Submit Anyway'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'view') {
      _editReport(existing);
    } else if (action == 'confirm') {
      final confirmed = await _reportService.confirmReport(existing);
      await _loadReports();
      if (mounted) {
        _message(
          confirmed
              ? 'Community confirmation added.'
              : 'You already confirmed this report.',
        );
      }
    } else if (action == 'submit') {
      await _saveReport(skipDuplicateCheck: true);
    }
  }

  Future<void> _showSubmitSuccess({
    required bool wasEditing,
    HazardReport? report,
    String? failedPhotoPath,
  }) async {
    final photoWarning = _reportService.lastPhotoUploadError;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          wasEditing
              ? 'Report updated successfully.'
              : 'Report submitted successfully.',
        ),
        content: Text(
          'Your report was saved as pending. FloodGuard will run automated credibility checks and update its confidence status shortly.'
          '${photoWarning == null ? '' : '\n\n$photoWarning'}',
        ),
        actions: [
          if (photoWarning != null &&
              report != null &&
              failedPhotoPath != null &&
              failedPhotoPath.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, 'retry-photo'),
              child: const Text('Retry Photo Upload'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'reports'),
            child: const Text('View My Reports'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context, 'map');
            },
            child: const Text('View on Map'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'retry-photo' && report != null && failedPhotoPath != null) {
      await _retryPhotoUpload(report: report, localPhotoPath: failedPhotoPath);
    } else if (action == 'map') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => EvacuationCentersScreen(focusReportId: report?.id),
        ),
      );
    }
  }

  Future<void> _retryPhotoUpload({
    required HazardReport report,
    required String localPhotoPath,
  }) async {
    setState(() => _isSaving = true);
    try {
      await _reportService.retryPhotoUpload(
        report: report,
        localPhotoPath: localPhotoPath,
      );
      await _loadReports();
      if (!mounted) return;
      final warning = _reportService.lastPhotoUploadError;
      _message(warning ?? 'Photo uploaded and report verification updated.');
    } catch (_) {
      if (mounted) {
        _message('Unable to retry photo upload right now.');
      }
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
          'This will permanently remove the ${report.displayType} report from your history.',
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
      _otherType.text = report.otherHazardType ?? '';
      _hazardReportLocation = report.hasCoordinate
          ? ml.LatLng(report.latitude!, report.longitude!)
          : _hazardReportLocation;
      _photo = null;
    });
  }

  void _resetForm() {
    setState(() {
      _editingReport = null;
      _type = HazardType.floodedRoad;
      _severity = 'Moderate';
      _description.clear();
      _otherType.clear();
      _photo = null;
      final current = _userCurrentLocation;
      if (current != null) {
        _location.text = current.label;
        _hazardReportLocation = ml.LatLng(current.latitude, current.longitude);
      } else {
        _location.text = 'Baliwag, Bulacan, PH';
      }
    });
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Hazard')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildForm(context),
          const SizedBox(height: 18),
          _recentReportsSection(context),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _editingReport == null ? 'Report a Hazard' : 'Update Hazard Report',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        const Text(
          'Submitted reports are community observations until verified.',
          style: TextStyle(color: AppTheme.muted),
        ),
        const SizedBox(height: 14),
        _stepCard(number: 1, title: 'Hazard Type', child: _hazardTypeField()),
        if (_type == HazardType.other) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _otherType,
            decoration: const InputDecoration(
              labelText: 'Specify Hazard Type',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (_type != HazardType.other) return null;
              if ((value ?? '').trim().length < 3) {
                return 'Specify the hazard type.';
              }
              return null;
            },
          ),
        ],
        _stepCard(
          number: 2,
          title: 'Photo / Evidence',
          subtitle: 'Add a clear photo if it is safe to do so.',
          child: _photoSection(),
        ),
        _stepCard(
          number: 3,
          title: 'Location',
          subtitle: 'This is the hazard location, separate from your GPS pin.',
          child: _locationSection(),
        ),
        _stepCard(
          number: 4,
          title: 'Severity',
          child: Column(
            children: [
              'Low',
              'Moderate',
              'High',
              'Critical',
            ].map((value) => _severityOption(value)).toList(),
          ),
        ),
        _stepCard(
          number: 5,
          title: 'Description',
          child: TextFormField(
            controller: _description,
            maxLength: 300,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText:
                  'Describe what you observed, road condition, approximate water depth, or anything that may help others.',
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isNotEmpty && text.length < 8) {
                return 'Use at least 8 characters or leave it blank.';
              }
              return null;
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveReport,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(
                  _editingReport == null ? 'Submit Report' : 'Save Changes',
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
  );

  Widget _stepCard({
    required int number,
    required String title,
    String? subtitle,
    required Widget child,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: AppTheme.paleBlue,
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: AppTheme.blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: AppTheme.muted)),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );

  Widget _hazardTypeField() => InkWell(
    onTap: _showHazardTypePicker,
    borderRadius: BorderRadius.circular(12),
    child: InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Hazard Type',
        border: OutlineInputBorder(),
      ),
      child: Row(
        children: [
          Icon(_icon(_type), color: AppTheme.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hazardTypeLabel(_type),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down),
        ],
      ),
    ),
  );

  Future<void> _showHazardTypePicker() async {
    final selected = await showModalBottomSheet<HazardType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Select Hazard Type',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            ...HazardType.values.map(
              (type) => ListTile(
                leading: Icon(_icon(type), color: AppTheme.blue),
                title: Text(hazardTypeLabel(type)),
                trailing: _type == type
                    ? const Icon(Icons.check, color: AppTheme.blue)
                    : null,
                onTap: () => Navigator.pop(context, type),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _type = selected);
  }

  Widget _recentReportsSection(BuildContext context) {
    final recent = _reports.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Reports',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            TextButton(
              onPressed: _reports.isEmpty ? null : _openReportHistory,
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(),
            ),
          )
        else if (recent.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.inbox_outlined, color: AppTheme.blue),
              title: Text('No hazard reports yet'),
              subtitle: Text('Submitted reports will appear here.'),
            ),
          )
        else
          ...recent.map(_buildReportCard),
      ],
    );
  }

  Future<void> _openReportHistory() async {
    final reportToEdit = await Navigator.push<HazardReport>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _ReportHistoryScreen(reports: _reports, onDelete: _deleteReport),
      ),
    );
    if (reportToEdit == null || !mounted) return;
    _editReport(reportToEdit);
  }

  Widget _photoSection() {
    final photo = _photo;
    final editingPhoto = _editingReport?.photoUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(photo.path), height: 132, fit: BoxFit.cover),
          )
        else if (editingPhoto != null && editingPhoto.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _imageForReport(editingPhoto, height: 132),
          )
        else
          Container(
            height: 86,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD5DEEC)),
            ),
            child: const Text('No photo selected'),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take Photo'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        if (photo != null || (editingPhoto?.isNotEmpty ?? false))
          TextButton.icon(
            onPressed: () => setState(() {
              _photo = null;
              if (_editingReport != null) {
                _editingReport = _editingReport!.copyWith(photoUrl: '');
              }
            }),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove Photo'),
          ),
      ],
    );
  }

  Widget _locationSection() {
    final point = _hazardReportLocation;
    return Column(
      children: [
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
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                point == null
                    ? 'Coordinates required'
                    : '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
                style: const TextStyle(color: AppTheme.muted),
              ),
            ),
            TextButton.icon(
              onPressed: _isLocating ? null : _loadDefaultLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('Use GPS'),
            ),
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: point == null ? null : _adjustOnMap,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Adjust on Map'),
          ),
        ),
      ],
    );
  }

  Widget _severityOption(String value) {
    final selected = _severity == value;
    return InkWell(
      onTap: () => setState(() => _severity = value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppTheme.blue : AppTheme.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _severityDescription(value),
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _adjustOnMap() async {
    final start = _hazardReportLocation;
    if (start == null) return;
    final result = await Navigator.push<_PickedHazardLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => _HazardLocationPickerScreen(
          initialPoint: start,
          initialLabel: _location.text,
          userCurrentLocation: _userCurrentLocation == null
              ? null
              : ml.LatLng(
                  _userCurrentLocation!.latitude,
                  _userCurrentLocation!.longitude,
                ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _hazardReportLocation = result.point;
      _location.text = result.label;
    });
  }

  Widget _buildReportCard(
    HazardReport report, {
    ValueChanged<HazardReport>? onEdit,
  }) => Card(
    child: ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: report.photoUrl == null || report.photoUrl!.isEmpty
            ? CircleAvatar(
                backgroundColor: _severityColor(
                  report.severity,
                ).withValues(alpha: .12),
                child: Icon(
                  _icon(report.type),
                  color: _severityColor(report.severity),
                ),
              )
            : _imageForReport(report.photoUrl!, width: 56, height: 56),
      ),
      title: Text(
        report.displayType,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${report.location}\n${hazardReportStatusLabel(report.status)} - ${report.severity} severity'
        ' - ${hazardVerificationStateLabel(report.verificationState)}'
        ' - ${report.confidenceScore}/100 confidence'
        '${report.confirmationCount > 0 ? ' - ${report.confirmationCount} confirmations' : ''}',
      ),
      isThreeLine: true,
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            onPressed: () =>
                onEdit == null ? _editReport(report) : onEdit(report),
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

  Widget _imageForReport(String value, {double? width, double? height}) {
    if (value.startsWith('http')) {
      return Image.network(
        value,
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    }
    return Image.file(
      File(value),
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }

  String _severityDescription(String value) => switch (value) {
    'Low' => 'Minor issue / passable',
    'Moderate' => 'May affect travel or drainage',
    'High' => 'Significant danger / avoid area',
    'Critical' => 'Immediate safety concern',
    _ => '',
  };

  Color _severityColor(String severity) => switch (severity) {
    'Low' => Colors.green,
    'High' => Colors.orange,
    'Critical' => Colors.red,
    _ => AppTheme.blue,
  };

  IconData _icon(HazardType type) => switch (type) {
    HazardType.floodedRoad => Icons.flood_outlined,
    HazardType.cloggedDrainage => Icons.water_damage_outlined,
    HazardType.blockedWaterway => Icons.waves_outlined,
    HazardType.overflowingCanal => Icons.water_outlined,
    HazardType.roadObstruction => Icons.traffic_outlined,
    HazardType.damagedDrainage => Icons.construction_outlined,
    HazardType.other => Icons.report_problem_outlined,
  };

  void _logSubmittedReport(HazardReport report) {
    debugPrint('[Hazard Submit] id: ${report.id}');
    debugPrint(
      '[Hazard Submit] storage source: ${_reportService.storageLabel}',
    );
    debugPrint(
      '[Hazard Submit] status: ${hazardReportStatusValue(report.status)}',
    );
    debugPrint('[Hazard Submit] hazard type: ${report.type.name}');
    debugPrint('[Hazard Submit] latitude: ${report.latitude}');
    debugPrint('[Hazard Submit] longitude: ${report.longitude}');
  }
}

class _ReportHistoryScreen extends StatefulWidget {
  const _ReportHistoryScreen({required this.reports, required this.onDelete});

  final List<HazardReport> reports;
  final Future<void> Function(HazardReport report) onDelete;

  @override
  State<_ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<_ReportHistoryScreen> {
  late List<HazardReport> _reports;
  final _search = TextEditingController();
  String _severityFilter = 'All';
  HazardType? _typeFilter;

  @override
  void initState() {
    super.initState();
    _reports = [...widget.reports];
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<HazardReport> get _filteredReports {
    final query = _search.text.trim().toLowerCase();
    return _reports.where((report) {
      final matchesText =
          query.isEmpty ||
          report.displayType.toLowerCase().contains(query) ||
          report.location.toLowerCase().contains(query) ||
          report.description.toLowerCase().contains(query);
      final matchesSeverity =
          _severityFilter == 'All' || report.severity == _severityFilter;
      final matchesType = _typeFilter == null || report.type == _typeFilter;
      return matchesText && matchesSeverity && matchesType;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredReports = _filteredReports;
    return Scaffold(
      appBar: AppBar(title: const Text('Report History')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Reports',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text('${filteredReports.length}/${_reports.length} shown'),
            ],
          ),
          const SizedBox(height: 10),
          _buildFilters(),
          const SizedBox(height: 10),
          if (_reports.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.inbox_outlined, color: AppTheme.blue),
                title: Text('No hazard reports yet'),
                subtitle: Text('Submitted reports will appear here.'),
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
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
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

  Widget _buildReportCard(HazardReport report) => Card(
    child: ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: report.photoUrl == null || report.photoUrl!.isEmpty
            ? CircleAvatar(
                backgroundColor: _severityColor(
                  report.severity,
                ).withValues(alpha: .12),
                child: Icon(
                  _icon(report.type),
                  color: _severityColor(report.severity),
                ),
              )
            : _imageForReport(report.photoUrl!, width: 56, height: 56),
      ),
      title: Text(
        report.displayType,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${report.location}\n${hazardReportStatusLabel(report.status)} - ${report.severity} severity'
        ' - ${hazardVerificationStateLabel(report.verificationState)}'
        ' - ${report.confidenceScore}/100 confidence'
        '${report.confirmationCount > 0 ? ' - ${report.confirmationCount} confirmations' : ''}',
      ),
      isThreeLine: true,
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context, report),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit report',
          ),
          IconButton(
            onPressed: () async {
              await widget.onDelete(report);
              if (!mounted) return;
              setState(() {
                _reports = _reports
                    .where((item) => item.id != report.id)
                    .toList();
              });
            },
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete report',
          ),
        ],
      ),
    ),
  );

  Widget _imageForReport(String value, {double? width, double? height}) {
    if (value.startsWith('http')) {
      return Image.network(
        value,
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    }
    return Image.file(
      File(value),
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }

  Color _severityColor(String severity) => switch (severity) {
    'Low' => Colors.green,
    'High' => Colors.orange,
    'Critical' => Colors.red,
    _ => AppTheme.blue,
  };

  IconData _icon(HazardType type) => switch (type) {
    HazardType.floodedRoad => Icons.flood_outlined,
    HazardType.cloggedDrainage => Icons.water_damage_outlined,
    HazardType.blockedWaterway => Icons.waves_outlined,
    HazardType.overflowingCanal => Icons.water_outlined,
    HazardType.roadObstruction => Icons.traffic_outlined,
    HazardType.damagedDrainage => Icons.construction_outlined,
    HazardType.other => Icons.report_problem_outlined,
  };
}

class _HazardLocationPickerScreen extends StatefulWidget {
  const _HazardLocationPickerScreen({
    required this.initialPoint,
    required this.initialLabel,
    required this.userCurrentLocation,
  });

  final ml.LatLng initialPoint;
  final String initialLabel;
  final ml.LatLng? userCurrentLocation;

  @override
  State<_HazardLocationPickerScreen> createState() =>
      _HazardLocationPickerScreenState();
}

class _HazardLocationPickerScreenState
    extends State<_HazardLocationPickerScreen> {
  static const _mapStyle = 'https://tiles.openfreemap.org/styles/bright';
  static const _hazardSourceId = 'report-hazard-point';
  static const _hazardLayerId = 'report-hazard-layer';
  static const _userSourceId = 'report-user-point';
  static const _userLayerId = 'report-user-layer';

  ml.MapLibreMapController? _controller;
  late ml.LatLng _point;
  late String _label;
  bool _styleReady = false;

  @override
  void initState() {
    super.initState();
    _point = widget.initialPoint;
    _label = widget.initialLabel;
  }

  Future<void> _installLayers() async {
    final controller = _controller;
    if (controller == null || !_styleReady) return;
    await controller.addGeoJsonSource(_hazardSourceId, _pointGeoJson(_point));
    await controller.addCircleLayer(
      _hazardSourceId,
      _hazardLayerId,
      const ml.CircleLayerProperties(
        circleRadius: 18,
        circleColor: '#DC2626',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 4,
      ),
    );
    final userPoint = widget.userCurrentLocation;
    if (userPoint != null) {
      await controller.addGeoJsonSource(
        _userSourceId,
        _pointGeoJson(userPoint),
      );
      await controller.addCircleLayer(
        _userSourceId,
        _userLayerId,
        const ml.CircleLayerProperties(
          circleRadius: 8,
          circleColor: '#2563EB',
          circleOpacity: .9,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 4,
        ),
        enableInteraction: false,
      );
    }
  }

  Future<void> _setHazardPoint(ml.LatLng point) async {
    setState(() {
      _point = point;
      _label =
          'Pinned location ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    });
    await _controller?.setGeoJsonSource(_hazardSourceId, _pointGeoJson(point));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Adjust Hazard Location')),
    body: Stack(
      children: [
        ml.MapLibreMap(
          initialCameraPosition: ml.CameraPosition(target: _point, zoom: 16),
          styleString: _mapStyle,
          compassEnabled: false,
          rotateGesturesEnabled: false,
          onMapCreated: (controller) => _controller = controller,
          onStyleLoadedCallback: () {
            _styleReady = true;
            _installLayers();
          },
          onMapClick: (_, coordinate) => _setHazardPoint(coordinate),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tap the map to place the hazard pin.',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(_label, style: const TextStyle(color: AppTheme.muted)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _PickedHazardLocation(point: _point, label: _label),
                    ),
                    icon: const Icon(Icons.check),
                    label: const Text('Use This Location'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Map<String, dynamic> _pointGeoJson(ml.LatLng point) => {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [point.longitude, point.latitude],
        },
        'properties': const {},
      },
    ],
  };
}

class _PickedHazardLocation {
  const _PickedHazardLocation({required this.point, required this.label});

  final ml.LatLng point;
  final String label;
}
