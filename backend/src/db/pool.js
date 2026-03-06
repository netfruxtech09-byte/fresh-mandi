import pg from 'pg';
import { env } from '../config/env.js';

const { Pool } = pg;

const isLocal = env.databaseUrl.includes('localhost') || env.databaseUrl.includes('127.0.0.1');

export const pool = new Pool({
  connectionString: env.databaseUrl,
  ssl: isLocal ? false : { rejectUnauthorized: false },
});
