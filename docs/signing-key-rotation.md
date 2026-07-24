# Signing key rotation

The previously embedded RSA key is revoked. Never reuse it.

1. Generate separate RSA-3072 key pairs for license and release signing.
2. Store private keys only in the deployment secret manager.
3. Configure the server license signer with `RSA_PRIVATE_KEY`.
4. Configure release publishing with its dedicated private-key secret.
5. Build clients with the decimal public moduli:

```text
--dart-define=LICENSE_RSA_MODULUS=<license-public-modulus>
--dart-define=RELEASE_RSA_MODULUS=<release-public-modulus>
```

Clients deliberately fail closed when either public modulus is absent. Existing
licenses and releases signed with the revoked key must be reissued.

Removing the key from the current tree does not remove it from Git history.
Rewrite the repository history or rotate access to the repository before the
next production release.
