import 'package:flutter/material.dart';

import '../models/hazard_report.dart';
import '../services/hazard_report_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import 'evacuation_centers_screen.dart';

class CommunityReportsScreen extends StatefulWidget {
  const CommunityReportsScreen({super.key});

  @override
  State<CommunityReportsScreen> createState() => _CommunityReportsScreenState();
}

class _CommunityReportsScreenState extends State<CommunityReportsScreen> {
  final _reportService = HazardReportService();
  final _searchController = TextEditingController();

  List<HazardReport> _reports = const [];
  HazardType? _typeFilter;
  String? _severityFilter;
  HazardReportStatus? _statusFilter;
  String? _error;
  bool _isLoading = true;

  List<HazardReport> get _filteredReports {
    final query = _searchController.text.trim().toLowerCase();
    final reports = _reports.where((report) {
      if (!report.isActive) return false;
      if (_typeFilter != null && report.type != _typeFilter) return false;
      if (_severityFilter != null && report.severity != _severityFilter) {
        return false;
      }
      if (_statusFilter != null && report.status != _statusFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return report.displayType.toLowerCase().contains(query) ||
          report.location.toLowerCase().contains(query) ||
          report.description.toLowerCase().contains(query);
    }).toList();
    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return reports;
  }

  @override
  void initState() {
    super.initState();
    _loadReports();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final reports = await _reportService.getReports(
        includeCommunityReports: true,
      );
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Community reports are temporarily unavailable.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Recent Community Reports'),
      actions: [
        IconButton(
          onPressed: _isLoading ? null : _loadReports,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh reports',
        ),
      ],
    ),
    bottomNavigationBar: const AppBottomNav(index: 0),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Search reports',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        _filters(),
        const SizedBox(height: 12),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: AppTheme.blue),
              title: Text(_error!),
              subtitle: const Text('Please try again later.'),
            ),
          )
        else if (_filteredReports.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.map_outlined, color: AppTheme.blue),
              title: Text('No matching reports'),
              subtitle: Text('Try clearing search or filters.'),
            ),
          )
        else
          ..._filteredReports.map(_reportCard),
      ],
    ),
  );

  Widget _filters() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<HazardType?>(
              initialValue: _typeFilter,
              decoration: const InputDecoration(labelText: 'Hazard Type'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All types')),
                ...HazardType.values.map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(hazardTypeLabel(type)),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _typeFilter = value),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _severityFilter,
              decoration: const InputDecoration(labelText: 'Severity'),
              items: const [
                DropdownMenuItem(value: null, child: Text('All severities')),
                DropdownMenuItem(value: 'Low', child: Text('Low')),
                DropdownMenuItem(value: 'Moderate', child: Text('Moderate')),
                DropdownMenuItem(value: 'High', child: Text('High')),
                DropdownMenuItem(value: 'Critical', child: Text('Critical')),
              ],
              onChanged: (value) => setState(() => _severityFilter = value),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<HazardReportStatus?>(
        initialValue: _statusFilter,
        decoration: const InputDecoration(labelText: 'Status'),
        items: [
          const DropdownMenuItem(
            value: null,
            child: Text('All visible status'),
          ),
          ..._visibleStatuses.map(
            (status) => DropdownMenuItem(
              value: status,
              child: Text(hazardReportStatusLabel(status)),
            ),
          ),
        ],
        onChanged: (value) => setState(() => _statusFilter = value),
      ),
    ],
  );

  Widget _reportCard(HazardReport report) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: _hazardColor(report.type).withValues(alpha: .12),
        child: Icon(_hazardIcon(report.type), color: _hazardColor(report.type)),
      ),
      title: Text(
        report.displayType,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${_shortLocation(report.location)}\n'
        '${_formatReportTime(report.createdAt)} - ${report.severity}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: IconButton(
        onPressed: () => _openReportOnMap(report),
        icon: const Icon(Icons.map_outlined, color: AppTheme.deepBlue),
        tooltip: 'View on Map',
      ),
      onTap: () => _openReportOnMap(report),
    ),
  );

  void _openReportOnMap(HazardReport report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EvacuationCentersScreen(focusReportId: report.id),
      ),
    );
  }

  String _shortLocation(String location) {
    final parts = location
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'Pinned location';
    return parts.join(', ');
  }

  String _formatReportTime(DateTime createdAt) {
    final difference = DateTime.now().difference(createdAt);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} hr ago';
    final hour = createdAt.hour % 12 == 0 ? 12 : createdAt.hour % 12;
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = createdAt.hour >= 12 ? 'PM' : 'AM';
    return '${createdAt.month}/${createdAt.day}/${createdAt.year}, $hour:$minute $period';
  }

  IconData _hazardIcon(HazardType type) => switch (type) {
    HazardType.floodedRoad => Icons.water_damage_outlined,
    HazardType.cloggedDrainage => Icons.water_drop_outlined,
    HazardType.blockedWaterway => Icons.waves_outlined,
    HazardType.overflowingCanal => Icons.flood_outlined,
    HazardType.roadObstruction => Icons.traffic_outlined,
    HazardType.damagedDrainage => Icons.construction_outlined,
    HazardType.other => Icons.warning_amber_outlined,
  };

  Color _hazardColor(HazardType type) => switch (type) {
    HazardType.floodedRoad || HazardType.overflowingCanal => AppTheme.blue,
    HazardType.cloggedDrainage ||
    HazardType.blockedWaterway ||
    HazardType.damagedDrainage => const Color(0xFFF97316),
    HazardType.roadObstruction || HazardType.other => const Color(0xFFDC2626),
  };

  static const _visibleStatuses = [
    HazardReportStatus.pending,
    HazardReportStatus.highConfidence,
    HazardReportStatus.verified,
    HazardReportStatus.suspicious,
  ];
}
