import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:serenutos/infrastructure/services/release_manager_service.dart';
import 'package:serenutos/infrastructure/services/rollback_manager.dart';
import 'package:serenutos/presentation/widgets/update_dialog.dart';
import 'package:serenutos/providers/service_providers.dart';

class _MockPathProvider extends PathProviderPlatform {
  final String tempDir;
  _MockPathProvider(this.tempDir);

  @override
  Future<String?> getTemporaryPath() async => tempDir;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

class FakeReleaseManager extends Fake implements ReleaseManagerService {
  final File downloadedFile;
  bool verifyDownloadCalled = false;
  bool installUpdateCalled = false;

  FakeReleaseManager(this.downloadedFile);

  @override
  Stream<DownloadProgress> downloadUpdate({
    required UpdateInfo updateInfo,
    required String platform,
    String? jwtToken,
    String? deviceId,
    DownloadCancellationToken? cancellationToken,
    http.Client? client,
  }) async* {
    yield const DownloadProgress(bytesDownloaded: 10, totalBytes: 10, percentage: 1.0);
  }

  @override
  Future<File?> getDownloadedFile(String version, String platform) async {
    return downloadedFile;
  }

  @override
  Future<bool> verifyDownload(File file, String expectedHash, String signature) async {
    verifyDownloadCalled = true;
    return true;
  }

  @override
  Future<InstallResult> installUpdate(File file, String platform, {String? expectedSha256}) async {
    installUpdateCalled = true;
    return InstallResult.success;
  }
}

class FakeRollbackManager extends Fake implements RollbackManager {
  @override
  Future<SystemSpecCheckResult> verifyInstallationSpecs() async {
    return SystemSpecCheckResult(
      hasRequiredSpace: true,
      hasRequiredRam: true,
      hasAdminPrivileges: true,
      freeSpaceGb: 10.0,
      issues: const [],
    );
  }

  @override
  Future<bool> backupCurrentVersion({bool Function()? isCancelled}) async {
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('update_dialog_test_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> runUpdateFlow(WidgetTester tester, UpdateInfo updateInfo, FakeReleaseManager fakeReleaseManager) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rollbackManagerProvider.overrideWithValue(FakeRollbackManager()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showUpdateDialog(
                    context: context,
                    updateInfo: updateInfo,
                    releaseManager: fakeReleaseManager,
                    platform: 'android',
                    jwtToken: null,
                    deviceId: null,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Güncelle'));
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }
  }

  testWidgets('fails closed and deletes file when sha256Hash is null', (tester) async {
    final file = File('${tempDir.path}/update.apk');
    file.writeAsStringSync('payload');

    final fakeReleaseManager = FakeReleaseManager(file);

    const updateInfo = UpdateInfo(
      hasUpdate: true,
      isForceUpdate: false,
      latestVersion: '1.5.0+10',
      downloadUrl: 'http://test.com/app.apk',
      sha256Hash: null, // MISSING
      signature: 'valid_signature',
      channel: 'stable',
    );

    await runUpdateFlow(tester, updateInfo, fakeReleaseManager);

    expect(
      find.text('Güncelleme paketinin SHA-256 özeti veya dijital imzası eksik. Güvenlik nedeniyle kurulum reddedildi.'),
      findsOneWidget,
    );
    expect(fakeReleaseManager.verifyDownloadCalled, isFalse);
    expect(fakeReleaseManager.installUpdateCalled, isFalse);
    expect(file.existsSync(), isFalse, reason: 'Insecure downloaded file must be deleted');
  });

  testWidgets('fails closed and deletes file when signature is empty', (tester) async {
    final file = File('${tempDir.path}/update2.apk');
    file.writeAsStringSync('payload2');

    final fakeReleaseManager = FakeReleaseManager(file);

    const updateInfo = UpdateInfo(
      hasUpdate: true,
      isForceUpdate: false,
      latestVersion: '1.5.0+10',
      downloadUrl: 'http://test.com/app.apk',
      sha256Hash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      signature: '', // EMPTY
      channel: 'stable',
    );

    await runUpdateFlow(tester, updateInfo, fakeReleaseManager);

    expect(
      find.text('Güncelleme paketinin SHA-256 özeti veya dijital imzası eksik. Güvenlik nedeniyle kurulum reddedildi.'),
      findsOneWidget,
    );
    expect(fakeReleaseManager.verifyDownloadCalled, isFalse);
    expect(fakeReleaseManager.installUpdateCalled, isFalse);
    expect(file.existsSync(), isFalse, reason: 'Insecure downloaded file must be deleted');
  });
}
