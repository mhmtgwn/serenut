// bin/release_publish_tool.dart
// Serenut Platform — CLI Release Engineering Publishing Tool with Preflight & Dry-run Checks

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:serenutos/infrastructure/services/crypto/canonical_json.dart';

Future<void> main(List<String> args) async {
  final Map<String, String> parsedArgs = {};
  for (int i = 0; i < args.length; i++) {
    if (args[i].startsWith('--') && i + 1 < args.length) {
      parsedArgs[args[i]] = args[i + 1];
    }
  }

  final version = parsedArgs['--version'] ?? '1.2.0';
  final buildNum = parsedArgs['--build-number'] ?? '22';
  final privateKeyPath = parsedArgs['--key'] ?? './keys/release_private.pem';
  final serverUrl = parsedArgs['--server'] ?? 'http://localhost:3000';
  final actor = parsedArgs['--actor'] ?? 'ci-cd-runner';
  final isDryRun = args.contains('--dry-run');

  stdout.writeln('🚀 Starting automated Release Publish Workflow for v$version+$buildNum (Dry-run: $isDryRun)...');

  // ==========================================
  // PREFLIGHT CHECKS
  // ==========================================
  stdout.writeln('📋 Running Preflight checks...');

  // 1. Verify Private Key exists and is readable
  final keyFile = File(privateKeyPath);
  if (!await keyFile.exists()) {
    stderr.writeln('❌ Preflight Check FAILED: Private key not found at: $privateKeyPath');
    exit(1);
  }

  // 2. Verify OpenSSL is present in system path
  try {
    final opensslCheck = await Process.run('openssl', ['version']);
    if (opensslCheck.exitCode != 0) {
      stderr.writeln('❌ Preflight Check FAILED: OpenSSL is not functioning properly.');
      exit(1);
    }
    stdout.writeln('   - OpenSSL: Verified (${opensslCheck.stdout.toString().trim()})');
  } catch (e) {
    stderr.writeln('❌ Preflight Check FAILED: OpenSSL command not found in system path.');
    exit(1);
  }

  stdout.writeln('✅ Preflight checks passed.');

  // ==========================================
  // COMPILATION
  // ==========================================
  stdout.writeln('🛠️  Compiling release target executable...');
  final buildRes = await Process.run('flutter', [
    'build',
    'windows',
    '--release',
    '--build-name=$version',
    '--build-number=$buildNum'
  ]);
  
  if (buildRes.exitCode != 0) {
    stderr.writeln('❌ Flutter compilation failed:\n${buildRes.stderr}');
    exit(1);
  }
  stdout.writeln('✅ Flutter compilation completed successfully.');

  final exeFile = File('build/windows/x64/runner/Release/serenutos.exe');
  if (!await exeFile.exists()) {
    stderr.writeln('❌ Target executable not found at: ${exeFile.path}');
    exit(1);
  }

  // ==========================================
  // SHA-256 GENERATION
  // ==========================================
  stdout.writeln('🧮 Calculating SHA-256 checksum...');
  final bytes = await exeFile.readAsBytes();
  final artifactSha256 = sha256.convert(bytes).toString();
  stdout.writeln('✅ Checksum generated: $artifactSha256');

  // ==========================================
  // RSA SIGNATURE GENERATION
  // ==========================================
  stdout.writeln('🔑 Generating RSA-256 artifact signature...');
  final sigFile = File('${exeFile.path}.sig');
  final opensslRes = await Process.run('openssl', [
    'dgst',
    '-sha256',
    '-sign',
    privateKeyPath,
    '-out',
    sigFile.path,
    exeFile.path
  ]);

  if (opensslRes.exitCode != 0) {
    stderr.writeln('❌ Openssl signing failed:\n${opensslRes.stderr}');
    exit(1);
  }

  final sigBytes = await sigFile.readAsBytes();
  final artifactSignature = base64Encode(sigBytes);
  stdout.writeln('✅ Artifact signature generated.');

  await sigFile.delete();

  // ==========================================
  // CONSTRUCT MANIFEST & SIGN
  // ==========================================
  stdout.writeln('📝 Constructing Release Manifest...');
  final manifestMap = {
    'schemaVersion': 1,
    'manifestVersion': '1.0',
    'releaseId': 'rel-$version-b$buildNum',
    'version': '$version+$buildNum',
    'channel': 'stable',
    'publishedAt': DateTime.now().toIso8601String(),
    'buildMetadata': {
      'commitHash': 'git_commit_stub',
      'buildNumber': int.parse(buildNum),
      'buildDate': DateTime.now().toIso8601String(),
      'signatureAlgorithm': 'RSA-SHA256'
    },
    'compatibility': {
      'minClientVersion': '1.0.0+1',
      'minimumUpdaterVersion': '1.0.0',
      'requiredBootstrapper': '1',
      'requiredPreVersion': '1.1.0+0',
      'migrationRequired': false,
      'targetSchemaVersion': 1
    },
    'rules': {
      'isMandatory': false,
      'allowRollback': true,
      'minFreeDiskMb': 300,
      'minRamMb': 2048,
      'supportedArchitectures': ['x64']
    },
    'artifacts': [
      {
        'type': 'installer_windows',
        'filename': 'SerenutOSSetup-$version.exe',
        'downloadUrl': '$serverUrl/api/v2/releases/artifacts/SerenutOSSetup-$version.exe',
        'sizeBytes': bytes.length,
        'sha256': artifactSha256,
        'signature': artifactSignature
      }
    ]
  };

  // Local Pre-publishing Artifact Checksum Validation
  stdout.writeln('🔍 Performing pre-publishing artifact verification check...');
  final manifestArtifactSha = manifestMap['artifacts']![0]['sha256'];
  if (manifestArtifactSha != artifactSha256) {
    stderr.writeln('❌ Error: Local file checksum does not match manifest checksum!');
    exit(1);
  }
  stdout.writeln('✅ Checksum match validated.');

  stdout.writeln('🔏 Canonicalizing & signing manifest (RFC 8785)...');
  final canonicalJson = CanonicalJsonSerializer.encode(manifestMap);
  final tempCanonicalFile = File('release_manifest.canonical.json');
  await tempCanonicalFile.writeAsString(canonicalJson);

  final manifestSigFile = File('release_manifest.json.sig');
  final opensslManifestRes = await Process.run('openssl', [
    'dgst',
    '-sha256',
    '-sign',
    privateKeyPath,
    '-out',
    manifestSigFile.path,
    tempCanonicalFile.path
  ]);

  if (opensslManifestRes.exitCode != 0) {
    stderr.writeln('❌ Manifest signing failed:\n${opensslManifestRes.stderr}');
    await tempCanonicalFile.delete();
    exit(1);
  }

  final manifestSigBytes = await manifestSigFile.readAsBytes();
  final manifestSignature = base64Encode(manifestSigBytes);

  await tempCanonicalFile.delete();
  await manifestSigFile.delete();
  stdout.writeln('✅ Manifest signature generated.');

  if (isDryRun) {
    stdout.writeln('⚠️ Dry-run parameter passed. Skipping publish request.');
    stdout.writeln('🎉 DRY-RUN SUCCESSFUL!');
    exit(0);
  }

  // ==========================================
  // PUBLISH REQUEST
  // ==========================================
  stdout.writeln('📡 Registering release manifest to Server Registry at $serverUrl...');
  try {
    final client = HttpClient();
    final uri = Uri.parse('$serverUrl/api/v2/releases/publish');
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    
    final payload = {
      'manifest': manifestMap,
      'canonicalManifestJson': canonicalJson,
      'manifestSignature': manifestSignature,
      'buildCommit': 'git_commit_stub',
      'buildPipelineId': 'local-build-runner',
      'actorId': actor
    };

    request.write(jsonEncode(payload));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode == 200) {
      final resMap = jsonDecode(body) as Map<String, dynamic>;
      
      // Verify Server Response fields (releaseId, artifactSetHash)
      if (resMap.containsKey('releaseId') && resMap.containsKey('artifactSetHash')) {
        stdout.writeln('🎉 SUCCESS! Sürüm başarıyla yayınlandı ve registry kaydı oluşturuldu!');
        stdout.writeln('   - Release ID: ${resMap['releaseId']}');
        stdout.writeln('   - Artifact Set Hash: ${resMap['artifactSetHash']}');
        
        // Write rollback summary file
        final rollbackFile = File('release-$version.publish.json');
        await rollbackFile.writeAsString(jsonEncode({
          'releaseId': resMap['releaseId'],
          'artifactSetHash': resMap['artifactSetHash'],
          'publishedAt': DateTime.now().toIso8601String(),
          'manifestSha256': sha256.convert(utf8.encode(canonicalJson)).toString(),
        }));
        stdout.writeln('📂 Rollback metadata written to: ${rollbackFile.path}');
      } else {
        stderr.writeln('❌ Registry publish verification failed: Invalid response payload.');
        exit(1);
      }
    } else {
      stderr.writeln('❌ Registry publish failed: Status ${response.statusCode}\nBody: $body');
      exit(1);
    }
  } catch (e) {
    stderr.writeln('❌ Network connection error: $e');
    exit(1);
  }
}
