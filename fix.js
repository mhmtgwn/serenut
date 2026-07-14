const fs = require('fs');
const crypto = require('crypto');
const { privateKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048,
  privateKeyEncoding: { type: 'pkcs1', format: 'pem' },
});
const envPath = '/var/www/serenut/server/.env.production';
let env = fs.readFileSync(envPath, 'utf8');
env = env.replace(/^RSA_PRIVATE_KEY=.*$/m, '');
env = env.replace(/^-----BEGIN RSA PRIVATE KEY-----[\s\S]*?-----END RSA PRIVATE KEY-----/m, '');
env = env.split('\n').filter(line => !line.match(/^[a-zA-Z0-9\/+=]*$/) && !line.includes('PRIVATE KEY')).join('\n');
env += '\nRSA_PRIVATE_KEY="' + privateKey.replace(/\n/g, '\\n') + '"\n';
fs.writeFileSync(envPath, env);
console.log('Key generated and added to .env.production');
