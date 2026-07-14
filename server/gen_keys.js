const { generateKeyPairSync } = require('crypto');
const fs = require('fs');

const { privateKey, publicKey } = generateKeyPairSync('rsa', { 
  modulusLength: 2048, 
  publicKeyEncoding: { type: 'spki', format: 'pem' }, 
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' } 
}); 

let env = fs.readFileSync('.env.test', 'utf8'); 
env = env.replace(/RSA_PRIVATE_KEY=.*/, 'RSA_PRIVATE_KEY="' + privateKey.replace(/\n/g, '\\n') + '"'); 
env = env.replace(/RSA_PUBLIC_KEY=.*/, 'RSA_PUBLIC_KEY="' + publicKey.replace(/\n/g, '\\n') + '"'); 

fs.writeFileSync('.env.test', env);
console.log('Keys generated successfully.');
