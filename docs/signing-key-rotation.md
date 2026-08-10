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

The repository and publisher enforce this sequence:

1. During the bridge phase, keep `requiredUpgradeSignerModulusSha256` pointing
   to the old signer and add the new public modulus to the client keyring.
2. Publish and verify the bridge release while it is still signed by the old
   key. Do not advance the policy based only on a successful CI build.
3. After the supported upgrade population has received the bridge release,
   reorder the client keyring and update the policy fingerprint in a separate
   change. CI verifies that the immediately previous client already trusted the
   selected signer.
4. The VPS publisher derives the public modulus from the actual private key and
   refuses to publish if it does not match the policy fingerprint.

Clients deliberately fail closed when either public modulus is absent. Existing
licenses and releases signed with the revoked key must be reissued.

Removing the key from the current tree does not remove it from Git history.
Rewrite the repository history or rotate access to the repository before the
next production release.
