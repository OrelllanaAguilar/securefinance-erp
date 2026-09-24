import crypto from 'node:crypto';

export function randomToken(bytes = 32) {
  return crypto.randomBytes(bytes).toString('base64url');
}

export function tokenDigest(token) {
  return crypto.createHash('sha512').update(token, 'utf8').digest();
}

export function csrfToken(sessionToken, secret) {
  return crypto.createHmac('sha256', secret).update(sessionToken, 'utf8').digest('base64url');
}

export function safeEqualText(left, right) {
  if (typeof left !== 'string' || typeof right !== 'string') return false;
  const leftBuffer = Buffer.from(left, 'utf8');
  const rightBuffer = Buffer.from(right, 'utf8');
  return leftBuffer.length === rightBuffer.length && crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

const passwordSymbols = '!@$%*+-_?';

export function temporaryPassword() {
  let random = '';
  while (random.length < 20) random += randomToken(24).replace(/[^A-Za-z0-9]/g, '');
  random = random.slice(0, 20);
  const characters = `${random}Aa7${passwordSymbols[crypto.randomInt(passwordSymbols.length)]}`.split('');
  for (let index = characters.length - 1; index > 0; index -= 1) {
    const target = crypto.randomInt(index + 1);
    [characters[index], characters[target]] = [characters[target], characters[index]];
  }
  return characters.join('');
}

export function clientIp(request) {
  return request.ip || request.socket?.remoteAddress || null;
}
