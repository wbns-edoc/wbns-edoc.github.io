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

console.log('Build configuration validated.');
