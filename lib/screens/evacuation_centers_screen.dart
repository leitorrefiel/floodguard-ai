import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/device_location_service.dart';
import '../services/weather_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';

class EvacuationCentersScreen extends StatefulWidget {
  const EvacuationCentersScreen({super.key});

  @override
  State<EvacuationCentersScreen> createState() =>
      _EvacuationCentersScreenState();
}

class _EvacuationCentersScreenState extends State<EvacuationCentersScreen> {
  static const _geoapifyApiKey = String.fromEnvironment('GEOAPIFY_API_KEY');
  static const _baliwag = LatLng(14.9547, 120.8969);
  static const _facilities = [
    _Facility(
      name: 'Baliwag City Hall Evacuation Center',
      address: 'Baliwag, Bulacan',
      point: LatLng(14.9547, 120.8969),
      type: _FacilityType.evacuation,
      recommended: true,
    ),
    _Facility(
      name: 'Baliwag North Central School',
      address: 'Baliwag, Bulacan',
      point: LatLng(14.9636, 120.8996),
      type: _FacilityType.school,
    ),
    _Facility(
      name: 'Baliwag District Hospital',
      address: 'Baliwag, Bulacan',
      point: LatLng(14.9506, 120.9018),
      type: _FacilityType.hospital,
    ),
    _Facility(
      name: 'Baliwag Fire Station',
      address: 'Baliwag, Bulacan',
      point: LatLng(14.9584, 120.8912),
      type: _FacilityType.fireStation,
    ),
  ];

  final _locationService = DeviceLocationService();
  final _weatherService = WeatherService();
  LatLng _assessmentPoint = _baliwag;
  String _locationLabel = 'Baliwag, Bulacan';
  String _scenario = 'rare';
  WeatherSnapshot? _weather;
  String? _weatherError;
  bool _isRefreshing = false;
  bool _showFloodHazard = true;
  bool _showFacilities = true;

  @override
  void initState() {
    super.initState();
    _restoreSavedLocation();
  }

  Future<void> _restoreSavedLocation() async {
    final location = await _locationService.getSavedLocation();
    if (location != null && mounted) {
      setState(() {
        _assessmentPoint = LatLng(location.latitude, location.longitude);
        _locationLabel = location.label;
      });
    }
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    setState(() {
      _isRefreshing = true;
      _weatherError = null;
    });
    try {
      final weather = await _weatherService.getCurrentWeather(
        latitude: _assessmentPoint.latitude,
        longitude: _assessmentPoint.longitude,
      );
      if (mounted) setState(() => _weather = weather);
    } on WeatherException catch (error) {
      if (mounted) setState(() => _weatherError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _weatherError = 'Check your internet connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _isRefreshing = true);
    try {
      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _assessmentPoint = LatLng(location.latitude, location.longitude);
        _locationLabel = location.label;
      });
      await _loadWeather();
    } on LocationAccessException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _focusFacility(_Facility facility) {
    setState(() {
      _showFacilities = true;
      _assessmentPoint = facility.point;
      _locationLabel = facility.name;
    });
    _loadWeather();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Showing ${facility.name}.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: const AppBottomNav(index: 0),
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: _mapPreview()),
          _topBar(context),
          _mapQuickActions(),
          _bottomPanel(context),
        ],
      ),
    ),
  );

  Widget _mapPreview() => Stack(
    fit: StackFit.expand,
    children: [
      Image.network(
        _staticMapUrl,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Container(
          color: const Color(0xFFEAF2FA),
          alignment: Alignment.center,
          child: const Text('Map preview unavailable'),
        ),
      ),
      if (_showFloodHazard) const _FloodZoneOverlay(),
      const Center(
        child: Icon(Icons.location_pin, color: AppTheme.navy, size: 48),
      ),
      if (_showFacilities) const _FacilityPreviewPins(),
    ],
  );

  String get _staticMapUrl {
    final lng = _assessmentPoint.longitude.toStringAsFixed(6);
    final lat = _assessmentPoint.latitude.toStringAsFixed(6);
    final marker = 'lonlat:$lng,$lat;color:%23103B73;size:medium;type:material';
    final key = _geoapifyApiKey;
    if (key.isEmpty) {
      return 'https://staticmap.openstreetmap.de/staticmap.php?center=$lat,$lng&zoom=15&size=600x600&markers=$lat,$lng,blue-pushpin';
    }
    return 'https://maps.geoapify.com/v1/staticmap'
        '?style=osm-bright'
        '&width=700'
        '&height=700'
        '&format=png'
        '&center=lonlat:$lng,$lat'
        '&zoom=15.2'
        '&marker=$marker'
        '&scaleFactor=2'
        '&apiKey=$key';
  }

  Widget _topBar(BuildContext context) => Positioned(
    top: 12,
    left: 16,
    right: 16,
    child: Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Hazard Map',
            style: TextStyle(
              color: AppTheme.navy,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
        ),
        IconButton.filledTonal(
          onPressed: _isRefreshing ? null : _loadWeather,
          icon: _isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
  );

  Widget _mapQuickActions() => Positioned(
    right: 16,
    top: 88,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _MapActionButton(
          label: 'My location',
          icon: Icons.my_location,
          selected: true,
          onPressed: _isRefreshing ? null : _useMyLocation,
        ),
        const SizedBox(height: 8),
        _MapActionButton(
          label: 'Flood zones',
          icon: Icons.flood_outlined,
          selected: _showFloodHazard,
          onPressed: () => setState(() => _showFloodHazard = !_showFloodHazard),
        ),
        const SizedBox(height: 8),
        _MapActionButton(
          label: 'Facilities',
          icon: Icons.home_work_outlined,
          selected: _showFacilities,
          onPressed: () => setState(() => _showFacilities = !_showFacilities),
        ),
      ],
    ),
  );

  Widget _bottomPanel(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .36,
    minChildSize: .18,
    maxChildSize: .84,
    builder: (context, controller) => DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FBFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          Center(
            child: Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD5DEEC),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _hazardSummaryCard(),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'usual', label: Text('Usual')),
              ButtonSegment(value: 'heavy', label: Text('Heavy')),
              ButtonSegment(value: 'rare', label: Text('Rare')),
            ],
            selected: {_scenario},
            onSelectionChanged: (values) =>
                setState(() => _scenario = values.first),
          ),
          const SizedBox(height: 12),
          const _HazardLegend(),
          const SizedBox(height: 6),
          const Text(
            'Colored rings are demo flood-prone zones. Use the buttons on the map to show or hide layers.',
            style: TextStyle(color: Color(0xFF5B6677), fontSize: 12),
          ),
          const SizedBox(height: 12),
          const _EmergencyHelpCard(),
          const SizedBox(height: 12),
          _weatherCard(),
          const SizedBox(height: 18),
          Text(
            'Critical Facilities',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap a facility to focus the map preview. Verify availability with the LGU before emergency use.',
          ),
          const SizedBox(height: 8),
          ..._facilities.map(
            (facility) =>
                _CenterCard(facility, onTap: () => _focusFacility(facility)),
          ),
        ],
      ),
    ),
  );

  Widget _hazardSummaryCard() {
    final zone = _nearestHazardZone();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: zone.color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: zone.color.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: zone.color.withValues(alpha: .18),
            child: Icon(Icons.flood_outlined, color: zone.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${zone.level} hazard near $_locationLabel',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text('${_scenarioLabel(_scenario)} with nearby facilities.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _scenarioLabel(String scenario) => switch (scenario) {
    'usual' => 'Usual flood scenario',
    'heavy' => 'Heavy flood scenario',
    _ => 'Rare extreme flood scenario',
  };

  Widget _weatherCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE3EAF4)),
    ),
    child: Row(
      children: [
        _isRefreshing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloudy_snowing, color: AppTheme.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live weather',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                _weather != null
                    ? '${_weather!.temperatureCelsius.toStringAsFixed(1)} C, precipitation ${_weather!.precipitationMm.toStringAsFixed(1)} mm'
                    : _weatherError ?? 'Loading current weather...',
              ),
            ],
          ),
        ),
      ],
    ),
  );

  _HazardZone _nearestHazardZone() {
    final distance = const Distance();
    final zones = _hazardZones().toList();
    zones.sort(
      (a, b) => distance(
        _assessmentPoint,
        a.point,
      ).compareTo(distance(_assessmentPoint, b.point)),
    );
    return zones.first;
  }

  List<_HazardZone> _hazardZones() => const [
    _HazardZone(
      level: 'High',
      point: LatLng(14.9526, 120.8912),
      color: Color(0xFFDC2626),
    ),
    _HazardZone(
      level: 'Medium',
      point: LatLng(14.9615, 120.9004),
      color: Color(0xFFF59E0B),
    ),
    _HazardZone(
      level: 'Low',
      point: LatLng(14.9468, 120.9044),
      color: Color(0xFF22C55E),
    ),
  ];
}

class _FloodZoneOverlay extends StatelessWidget {
  const _FloodZoneOverlay();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ZoneRing(size: 188, color: const Color(0xFFDC2626), opacity: .12),
          _ZoneRing(size: 148, color: const Color(0xFFF59E0B), opacity: .16),
          _ZoneRing(size: 108, color: const Color(0xFF22C55E), opacity: .14),
        ],
      ),
    ),
  );
}

class _ZoneRing extends StatelessWidget {
  const _ZoneRing({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: opacity),
      border: Border.all(color: color.withValues(alpha: .75), width: 2),
    ),
  );
}

class _FacilityPreviewPins extends StatelessWidget {
  const _FacilityPreviewPins();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: Stack(
      children: [
        Positioned(left: 42, top: 218, child: _PreviewPin(Icons.home_work)),
        Positioned(right: 76, top: 184, child: _PreviewPin(Icons.school)),
        Positioned(
          left: 88,
          top: 132,
          child: _PreviewPin(Icons.local_hospital),
        ),
        Positioned(
          right: 44,
          top: 250,
          child: _PreviewPin(Icons.local_fire_department),
        ),
      ],
    ),
  );
}

class _PreviewPin extends StatelessWidget {
  const _PreviewPin(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8)],
      border: Border.all(color: AppTheme.blue, width: 2),
    ),
    child: Padding(
      padding: const EdgeInsets.all(7),
      child: Icon(icon, color: AppTheme.blue, size: 18),
    ),
  );
}

class _HazardLegend extends StatelessWidget {
  const _HazardLegend();

  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: 12,
    runSpacing: 6,
    children: [
      _LegendItem(color: Color(0xFF22C55E), label: 'Low risk'),
      _LegendItem(color: Color(0xFFF59E0B), label: 'Medium risk'),
      _LegendItem(color: Color(0xFFDC2626), label: 'High risk'),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppTheme.blue : Colors.white,
    elevation: 3,
    shadowColor: const Color(0x30000000),
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : AppTheme.navy,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.navy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CenterCard extends StatelessWidget {
  const _CenterCard(this.facility, {required this.onTap});

  final _Facility facility;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: facility.recommended
            ? const Color(0xFFE8F8ED)
            : AppTheme.paleBlue,
        child: Icon(
          _icon(facility.type),
          color: facility.recommended ? Colors.green : AppTheme.blue,
        ),
      ),
      title: Text(
        facility.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('${facility.address}\n${_detail(facility)}'),
      isThreeLine: true,
      trailing: const Icon(Icons.map_outlined),
      onTap: onTap,
    ),
  );

  String _detail(_Facility facility) {
    if (facility.recommended) {
      return 'Recommended reference site, verify opening status with the LGU.';
    }
    return 'Reference facility, verify status before emergency use.';
  }

  IconData _icon(_FacilityType type) => switch (type) {
    _FacilityType.evacuation => Icons.home_work_outlined,
    _FacilityType.school => Icons.school_outlined,
    _FacilityType.hospital => Icons.local_hospital_outlined,
    _FacilityType.fireStation => Icons.local_fire_department_outlined,
  };
}

class _EmergencyHelpCard extends StatelessWidget {
  const _EmergencyHelpCard();

  static const _numbers = [
    _EmergencyNumber(
      label: 'National Emergency Hotline',
      number: '911',
      detail: 'Police, fire, rescue, or medical emergency',
    ),
    _EmergencyNumber(
      label: 'Philippine Red Cross',
      number: '143',
      detail: 'Rescue and disaster assistance',
    ),
    _EmergencyNumber(
      label: 'NDRRMC Operations Center',
      number: '0289111406',
      displayNumber: '(02) 8911-1406',
      detail: 'Disaster response coordination',
    ),
  ];

  static Future<void> _call(BuildContext context, String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone dialer is not available.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emergency_outlined, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Emergency Contacts',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap Call to open the phone dialer.',
            style: TextStyle(color: Color(0xFF5B6677)),
          ),
          const SizedBox(height: 8),
          ..._numbers.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFE8E8),
                child: Icon(Icons.phone_in_talk_outlined, color: Colors.red),
              ),
              title: Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('${item.displayNumber}\n${item.detail}'),
              isThreeLine: true,
              trailing: FilledButton(
                onPressed: () => _call(context, item.number),
                child: const Text('Call'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmergencyNumber {
  const _EmergencyNumber({
    required this.label,
    required this.number,
    required this.detail,
    String? displayNumber,
  }) : displayNumber = displayNumber ?? number;

  final String label;
  final String number;
  final String displayNumber;
  final String detail;
}

class _HazardZone {
  const _HazardZone({
    required this.level,
    required this.point,
    required this.color,
  });

  final String level;
  final LatLng point;
  final Color color;
}

class _Facility {
  const _Facility({
    required this.name,
    required this.address,
    required this.point,
    required this.type,
    this.recommended = false,
  });

  final String name;
  final String address;
  final LatLng point;
  final _FacilityType type;
  final bool recommended;
}

enum _FacilityType { evacuation, school, hospital, fireStation }
