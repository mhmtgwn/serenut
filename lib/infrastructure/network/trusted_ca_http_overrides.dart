import 'dart:io';
import 'dart:typed_data';

/// Adds Serenut's public certificate authority to the platform trust store.
///
/// Some older Windows installations do not contain ISRG Root X1 and reject
/// the current Let's Encrypt chain before any API request is sent. This keeps
/// normal hostname, expiry and chain validation enabled; it does not accept
/// arbitrary or self-signed certificates.
class TrustedCaHttpOverrides extends HttpOverrides {
  TrustedCaHttpOverrides(Uint8List trustedCertificateBytes)
      : _context = SecurityContext(withTrustedRoots: true) {
    _context.setTrustedCertificatesBytes(trustedCertificateBytes);
  }

  final SecurityContext _context;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(_context);
  }
}
