// Existing shell variables win. Load the higher-priority file first because
// loadEnvFile only fills variables that are not already in process.env.
for (const filename of ['.env.llm_settings', '.env.local']) {
  try { process.loadEnvFile(filename); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
}
