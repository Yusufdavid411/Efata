import pg from 'pg';

export function createPreviewOrderReader({ url, ca, snapshotId }) {
  const parsed = new URL(url);
  if (parsed.search || parsed.hash || !['postgres:', 'postgresql:'].includes(parsed.protocol)) {
    throw new Error('Preview database URL must not override TLS options');
  }
  const pool = new pg.Pool({
    connectionString: url,
    max: 2,
    connectionTimeoutMillis: 4000,
    idleTimeoutMillis: 5000,
    statement_timeout: 4000,
    ssl: { rejectUnauthorized: true, ...(ca && { ca }) },
  });
  pool.on('error', () => {});
  const read = async ({ uid, scope, page, limit }) => {
    const snapshot = await pool.query(
      'select read_time from efata_preview.snapshot_info where id = $1', [snapshotId],
    );
    if (snapshot.rowCount !== 1) throw new Error('Preview snapshot is unavailable');
    const { rows } = await pool.query(
      `select order_id as id, status, pickup, dropoff, vehicle_type as "vehicleType",
              created_at as "createdAt"
       from efata_preview.order_summaries
       where snapshot_id = $1 and (
         $3 = 'admin' or ($3 = 'customer' and customer_id = $2)
         or ($3 = 'driver' and driver_id = $2)
       )
       order by created_at desc, order_id desc
       limit $4 offset $5`,
      [snapshotId, uid, scope, limit + 1, (page - 1) * limit],
    );
    return {
      asOf: snapshot.rows[0].read_time,
      orders: rows.slice(0, limit),
      nextPage: rows.length > limit ? page + 1 : null,
    };
  };
  read.close = () => pool.end();
  return read;
}
