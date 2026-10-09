const url = process.env.VITE_SUPABASE_URL;
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!url || !key) {
  console.error(
    'Build configuration error: VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY are required.'
  );
  process.exit(1);
}

let parsed;
try {
  parsed = new URL(url);
} catch {
  console.error('Build configuration error: VITE_SUPABASE_URL must be a valid URL.');
  process.exit(1);
}

if (parsed.protocol !== 'https:' || !parsed.hostname.endsWith('.supabase.co')) {
  console.error(
    'Build configuration error: VITE_SUPABASE_URL must be an HTTPS Supabase project URL.'
  );
  process.exit(1);
}

if (key.startsWith('sb_secret_')) {
  console.error(
    'Build configuration error: VITE_SUPABASE_PUBLISHABLE_KEY must not contain a secret key.'
  );
  process.exit(1);
}

// Older Supabase anon/service-role keys are JWTs; reject JWTs explicitly identifying
// themselves as service_role without rejecting legacy anon JWTs.
const jwtParts = key.split('.');
if (jwtParts.length === 3) {
  try {
    const payload = JSON.parse(
      Buffer.from(jwtParts[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8')
    );
    if (payload.role === 'service_role') {
      console.error(
        'Build configuration error: a service-role key must never be used as a VITE_ client variable.'
      );
      process.exit(1);
    }
  } catch (error) {
    if (error instanceof SyntaxError) {
      console.error('Build configuration error: the supplied JWT key is malformed.');
      process.exit(1);
    }
    throw error;
  }
}

console.log('Build configuration validated.');
