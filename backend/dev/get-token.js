// Usage: node dev/get-token.js you@gmail.com Miner1   (prints a Firebase ID token; the web API key is read from the shell or the app's firebase_options.dart)
// Also imported by the smoke tests: importing it must not read process.argv or exit.
import { signInToken } from '../seed/identity.js';

export const getToken = (email, pwd) => signInToken(String(email).trim().toLowerCase(), pwd);

const isCli = process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('dev/get-token.js');
if (isCli) {
  const [, , email, password] = process.argv;
  if (!email || !password) {
    console.error('Usage: node dev/get-token.js <email> <password>');
    process.exit(1);
  }
  getToken(email, password).then((t) => console.log(t)).catch((e) => { console.error(e.message); process.exit(1); });
}
