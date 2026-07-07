// lib/domain/models/app_version.dart
class AppVersion {
  final int versionCode;
  final String versionName;
  final DateTime releaseDate;
  final int minSupportedVersion;
  final bool forceUpdate;
  final String? changelog;
  final String? downloadUrl;

  AppVersion({
    required this.versionCode,
    required this.versionName,
    required this.releaseDate,
    required this.minSupportedVersion,
    required this.forceUpdate,
    this.changelog,
    this.downloadUrl,
  });

  Map<String, dynamic> toMap() => {
        'versionCode': versionCode,
        'versionName': versionName,
        'releaseDate': releaseDate.toIso8601String(),
        'minSupportedVersion': minSupportedVersion,
        'forceUpdate': forceUpdate,
        'changelog': changelog,
        'downloadUrl': downloadUrl,
      };

  factory AppVersion.fromMap(Map<String, dynamic> map) => AppVersion(
        versionCode: map['versionCode'] as int,
        versionName: map['versionName'] as String,
        releaseDate: DateTime.parse(map['releaseDate'] as String),
        minSupportedVersion: map['minSupportedVersion'] as int,
        forceUpdate: map['forceUpdate'] as bool? ?? false,
        changelog: map['changelog'] as String?,
        downloadUrl: map['downloadUrl'] as String?,
      );
}
