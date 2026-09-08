import './load-env.mjs';

// Load env before Next initializes or spawns workers. Node's --env-file flags
// cannot be forwarded through the NODE_OPTIONS used by Next's dev workers.
await import('next/dist/bin/next');
