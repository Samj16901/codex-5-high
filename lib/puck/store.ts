import fs from 'fs';
import path from 'path';

/**
 * Directory where editor data is persisted.  You can override this by setting
 * the `PUCK_DATA_DIR` environment variable.  When running on Vercel or other
 * serverless platforms you should swap this for a remote store or database.
 */
const dataDir = process.env.PUCK_DATA_DIR ?? path.join(process.cwd(), 'data', 'puck');

/** Ensure that the data directory exists before reading or writing. */
function ensureDir() {
  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true });
  }
}

/**
 * Load the JSON document for a given identifier.  Returns `null` if no file
 * exists.  Parsing errors will throw.
 */
export function loadData(id: string): any | null {
  ensureDir();
  const file = path.join(dataDir, `${id}.json`);
  if (!fs.existsSync(file)) return null;
  const raw = fs.readFileSync(file, 'utf8');
  try {
    return JSON.parse(raw);
  } catch (err) {
    console.warn(`Failed to parse data for ${id}:`, err);
    return null;
  }
}

/**
 * Persist a JSON document for a given identifier.  Overwrites existing files.
 */
export function saveData(id: string, data: any): void {
  ensureDir();
  const file = path.join(dataDir, `${id}.json`);
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
}