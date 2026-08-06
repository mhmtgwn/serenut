# Company logo file migration

Company logos are stored outside PostgreSQL. The VPS keeps three immutable files
for each uploaded logo:

- `original.*`: validated original upload
- `display.webp`: optimized application image
- `print.png`: high-contrast monochrome thermal-print image

## Required production configuration

Set these values in `server/.env.production`:

```env
PUBLIC_BASE_URL=https://api.example.com
COMPANY_LOGOS_DIR=/var/lib/serenut/company-logos
```

The production Compose file persists the directory in `server/company-logos` on
the host. Include that directory in VPS backups.

## Safe rollout

1. Deploy the server before publishing the Flutter client.
2. Run the migration in dry-run mode:

   ```bash
   npm run migrate:company-logos
   ```

3. Review the generated manifest under `server/logs` and spot-check the
   generated `display.webp` and `print.png` files.
4. Apply the database switch:

   ```bash
   npm run migrate:company-logos -- --apply
   ```

The database value is changed only after all three files are generated. Failed
images retain their original Base64 value and are listed in the command output.
Every run writes a manifest containing the old and new values for rollback.

## Rollback

Use the latest applied manifest to restore each `previous` value to the matching
company's `logo_url`. Do not remove the generated files until the rollback window
has expired.
