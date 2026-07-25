const fs = require('fs');

const targetFile = '/app/dist/modules/realtime/realtime.ws.js';
let code = fs.readFileSync(targetFile, 'utf8');

if (!code.includes('isAlive = true;')) {
  code = code.replace(
    "ws.on('message', async (data) => {",
    "ws.on('message', async (data) => { isAlive = true;"
  );
  fs.writeFileSync(targetFile, code);
  console.log('Successfully patched realtime.ws.js with isAlive = true!');
} else {
  console.log('Already patched!');
}
