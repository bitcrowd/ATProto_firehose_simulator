const { Database } = require("@atproto/bsky");

const main = async () => {
  const dbUrl = process.env.BSKY_DB_POSTGRES_URL;
  const dbSchema = process.env.BSKY_DB_POSTGRES_SCHEMA || "bsky";

  if (!dbUrl) {
    console.error("BSKY_DB_POSTGRES_URL is required");
    process.exit(1);
  }

  const db = new Database({ url: dbUrl, schema: dbSchema });

  await db.migrateToLatestOrThrow();
  await db.close();
};

main().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
