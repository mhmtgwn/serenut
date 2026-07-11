// lib/infrastructure/services/release_channel_service.dart
// Serenut OS — Release Channel Settings Service (Sprint 13)

import 'package:shared_preferences/shared_preferences.dart';

class ReleaseChannelService {
  final SharedPreferences _prefs;
  static const String _channelKey = 'client_release_channel';

  ReleaseChannelService(this._prefs);

  /// Gets the currently configured release channel (default: stable)
  String getSelectedChannel() {
    return _prefs.getString(_channelKey) ?? 'stable';
  }

  /// Persists release channel selection
  Future<bool> setSelectedChannel(String channel) async {
    if (!getAvailableChannels().contains(channel)) {
      throw ArgumentError('Invalid release channel: $channel');
    }
    return await _prefs.setString(_channelKey, channel);
  }

  /// List of release channels supported by Serenut platform
  List<String> getAvailableChannels() {
    return ['stable', 'beta', 'rc'];
  }
}
