import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/dataset_loader_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unmount keeps a cleared catalog disabled after restart', () async {
    SharedPreferences.setMockInitialValues({
      'active_dataset_version': 'vps-catalog-v1',
    });
    final preferences = await SharedPreferences.getInstance();
    final loader = DatasetLoaderService(preferences);

    expect(loader.activeVersion, 'vps-catalog-v1');

    await loader.unmountActiveVersion();

    expect(loader.activeDb, isNull);
    expect(loader.activeVersion, 'None');
    expect(preferences.getString('active_dataset_version'), 'None');
    expect(DatasetLoaderService(preferences).activeVersion, 'None');
  });
}
