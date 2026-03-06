import pg from 'pg';

const { Client } = pg;

const adminUrl = process.env.PG_ADMIN_URL ?? 'postgresql://postgres:postgres@localhost:5432/postgres';
const dbName = process.env.PG_DB_NAME ?? 'fresh_mandi';

async function run() {
  const client = new Client({ connectionString: adminUrl });
  await client.connect();
  const exists = await client.query('SELECT 1 FROM pg_database WHERE datname = $1', [dbName]);
  if (!exists.rowCount) {
    await client.query(`CREATE DATABASE ${dbName}`);
    console.log(`Database created: ${dbName}`);
  } else {
    console.log(`Database already exists: ${dbName}`);
  }
  await client.end();
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
