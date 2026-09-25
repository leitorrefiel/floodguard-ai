import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

class DataSourceLink extends StatelessWidget {
  const DataSourceLink.openMeteo({super.key})
    : label = 'Weather data by Open-Meteo.com',
      url = 'https://open-meteo.com/';

  const DataSourceLink.rainViewer({super.key})
    : label = 'Weather radar by RainViewer',
      url = 'https://www.rainviewer.com/';

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => Link(
    uri: Uri.parse(url),
    target: LinkTarget.blank,
    builder: (context, followLink) => TextButton.icon(
      onPressed: followLink,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft,
        textStyle: const TextStyle(fontSize: 11),
      ),
      icon: const Icon(Icons.open_in_new, size: 14),
      label: Text(label),
    ),
  );
}
