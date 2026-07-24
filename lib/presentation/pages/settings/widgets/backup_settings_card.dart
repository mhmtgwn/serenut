part of '../../settings_page.dart';

// Extracted Backup and SMS Settings Card sheets for SettingsPage
extension SettingsBackupSmsSheets on _SettingsPageState {
  void _showSmsSettingsSheet(Settings settings) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => SmsSettingsSheet(settings: settings),
      ),
    );
  }
}
