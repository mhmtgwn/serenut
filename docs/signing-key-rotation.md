# Signing key rotation

Normal sürüm yayınlama adımları için önce
[`release-update-runbook.md`](release-update-runbook.md) belgesini kullanın.

The previously embedded RSA key is revoked. Never reuse it.

1. Generate separate RSA-3072 key pairs for license and release signing.
2. Store private keys only in the deployment secret manager.
3. Configure the server license signer with `RSA_PRIVATE_KEY`.
4. Configure release publishing with its dedicated private-key secret.
5. Build clients with the license modulus and a comma-separated release
   verification keyring. The first release key is the active signer; remaining
   keys are temporary rotation/grace keys:

```text
--dart-define=LICENSE_RSA_MODULUS=<license-public-modulus>
--dart-define=RELEASE_RSA_MODULI=<active-modulus>,<rotation-modulus>
```

Never replace the active signer and client key in the same release. First ship
a client that trusts both keys, wait for rollout completion, and only then sign
the following release with the new key. Remove the retired key in a later
release after the supported upgrade window closes.

Clients deliberately fail closed when either public modulus is absent. Existing
licenses and releases signed with the revoked key must be reissued.

Removing the key from the current tree does not remove it from Git history.
Rewrite the repository history or rotate access to the repository before the
next production release.
