const { Database, DataPlaneServer, RepoSubscription } = require("@atproto/bsky");
const { IdResolver, MemoryCache } = require("@atproto/identity");

const main = async () => {
  const dbUrl = process.env.BSKY_DB_POSTGRES_URL;
  const dbSchema = process.env.BSKY_DB_POSTGRES_SCHEMA || "bsky";
  const port = parseInt(process.env.BSKY_DATAPLANE_PORT || "2585", 10);
  const plcUrl = process.env.BSKY_DID_PLC_URL;
  const relayWebsocket = process.env.BSKY_RELAY_WEBSOCKET;

  console.log("Starting DataPlane server...");
  const redactedDbUrl = dbUrl ? dbUrl.replace(/:[^:@]+@/, ":****@") : "(unset)";
  console.log("Database URL:", dbUrl);
  console.log("Schema:", dbSchema);
  console.log("Port:", port);
  console.log("Relay WebSocket:", relayWebsocket);

  const db = new Database({
    url: dbUrl,
    schema: dbSchema,
    poolSize: 20,
  });

  // Run migrations
  console.log("Running database migrations...");
  await db.migrateToLatestOrThrow();
  console.log("Migrations complete");

  const server = await DataPlaneServer.create(db, port, plcUrl);
  console.log("DataPlane server listening on port", port);

  // Repo subscription requires an id resolver.
  const didCache = new MemoryCache();
  const idResolver = new IdResolver({ plcUrl, didCache });
  const sub = new RepoSubscription({
    service: relayWebsocket,
    db,
    idResolver,
  });

  sub.start();
  console.log("Subscribed to firehose at", relayWebsocket);

  const shutdown = async () => {
    console.log("Shutting down DataPlane server...");
    await sub.destroy();
    await server.destroy();
    await db.close();
    process.exit(0);
  };

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
};

main().catch((err) => {
  console.error("DataPlane server failed to start:", err);
  process.exit(1);
});
