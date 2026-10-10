import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

const validator = new URL('./validate-build-env.mjs', import.meta.url);
const base = {
  ...process.env,
  VITE_SUPABASE_URL: 'https://ci-placeholder.supabase.co',
  VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_ci_placeholder',
};

function check(name, overrides, expectedStatus) {
  const env = { ...base, ...overrides };
  const result = spawnSync(process.execPath, [validator.pathname], {
    env,
    encoding: 'utf8',
  });
  assert.equal(
    result.status,
    expectedStatus,
    `${name}: expected exit ${expectedStatus}, got ${result.status}.\n${result.stdout}\n${result.stderr}`
  );
}

check('valid publishable key', {}, 0);
check('missing URL', { VITE_SUPABASE_URL: '' }, 1);
check('missing key', { VITE_SUPABASE_PUBLISHABLE_KEY: '' }, 1);
check('secret-format key', { VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_secret_test' }, 1);

const jwt = (payload) => {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode(payload)}.signature`;
};
check('legacy service-role JWT', {
  VITE_SUPABASE_PUBLISHABLE_KEY: jwt({ role: 'service_role' }),
}, 1);
check('legacy anon JWT remains allowed', {
  VITE_SUPABASE_PUBLISHABLE_KEY: jwt({ role: 'anon' }),
}, 0);

console.log('Build environment validation tests passed (6 cases).');
