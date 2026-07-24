import crypto from 'crypto';

function loadPrivateKey(): crypto.KeyObject | null {
  const envKey = process.env.RSA_PRIVATE_KEY;
  if (!envKey) {
    console.error('🚨 RSA_PRIVATE_KEY environment variable is not set. RSA signing features are disabled.');
    return null;
  }

  try {
    if (envKey.startsWith('{')) {
      // Load from JWK format
      return crypto.createPrivateKey({
        key: JSON.parse(envKey),
        format: 'jwk'
      });
    } else {
      // Load from PEM format
      const formattedKey = envKey.replace(/\\n/g, '\n');
      return crypto.createPrivateKey({
        key: formattedKey,
        format: 'pem'
      });
    }
  } catch (err: any) {
    console.error('❌ Failed to load RSA_PRIVATE_KEY from environment variables. RSA signing features are disabled until the key is fixed:', err);
    return null;
  }
}

export const privateKey = loadPrivateKey();

export function signPayload(payload: string): string {
  if (!privateKey) {
    throw new Error('RSA_PRIVATE_KEY is not configured; cannot sign payload.');
  }
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(payload);
  signer.end();
  return signer.sign(privateKey, 'base64');
}

// ── SYMMETRIC ENCRYPTION (AES-256-GCM) ─────────────────────────────────────────

// We derive a static 32-byte AES key from the RSA Private Key or an environment variable.
let aesKey: Buffer;
try {
  // Try to use a dedicated APP_SECRET if available
  if (process.env.APP_SECRET) {
    aesKey = crypto.createHash('sha256').update(process.env.APP_SECRET).digest();
  } else if (process.env.RSA_PRIVATE_KEY) {
    // Fallback: derive AES key from the RSA private key string
    aesKey = crypto.createHash('sha256').update(process.env.RSA_PRIVATE_KEY).digest();
  } else {
    console.error('🚨 [SECURITY WARNING] No secure encryption key provided in environment (APP_SECRET or RSA_PRIVATE_KEY).');
    console.error('⚠️ Falling back to an insecure default key. THIS IS DANGEROUS IN PRODUCTION!');
    aesKey = crypto.createHash('sha256').update('shaman_pos_insecure_default_key_DO_NOT_USE').digest();
  }
} catch (e) {
  console.error('[FATAL/WARNING] Failed to initialize AES encryption key. Falling back to insecure key.', e);
  aesKey = crypto.createHash('sha256').update('shaman_pos_insecure_default_key_DO_NOT_USE').digest();
}

export function encryptSecret(text: string): string {
  if (!text) return text;
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', aesKey, iv);
  
  let encrypted = cipher.update(text, 'utf8', 'base64');
  encrypted += cipher.final('base64');
  const authTag = cipher.getAuthTag().toString('base64');
  
  // Format: iv:authTag:encrypted
  return `${iv.toString('base64')}:${authTag}:${encrypted}`;
}

export function decryptSecret(encryptedData: string): string {
  if (!encryptedData) return encryptedData;
  if (!encryptedData.includes(':')) return encryptedData; // Not encrypted or old format
  
  try {
    const parts = encryptedData.split(':');
    if (parts.length !== 3) return encryptedData;
    
    const iv = Buffer.from(parts[0], 'base64');
    const authTag = Buffer.from(parts[1], 'base64');
    const encrypted = parts[2];
    
    const decipher = crypto.createDecipheriv('aes-256-gcm', aesKey, iv);
    decipher.setAuthTag(authTag);
    
    let decrypted = decipher.update(encrypted, 'base64', 'utf8');
    decrypted += decipher.final('utf8');
    
    return decrypted;
  } catch (err) {
    console.error('Failed to decrypt secret:', err);
    return ''; // Return empty string on failure to prevent leaking malformed data
  }
}
