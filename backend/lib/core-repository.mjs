import pg from 'pg';

export class ApiError extends Error {
  constructor(statusCode, code) {
    super(code);
    this.statusCode = statusCode;
    this.code = code;
  }
}

function orderFields() {
  return `o.id, o.firebase_order_id as "legacyId", o.status,
    o.pickup_label as pickup, o.pickup_lat as "pickupLat", o.pickup_lng as "pickupLng",
    o.dropoff_label as "dropoff", o.dropoff_lat as "dropoffLat", o.dropoff_lng as "dropoffLng",
    o.item_description as item, o.vehicle_type as "vehicleType",
    o.scheduled_for as "scheduledFor", o.distance_meters as "distanceMeters",
    o.duration_seconds as "durationSeconds", o.amount, o.payment_method as "paymentMethod",
    o.payment_status as "paymentStatus", o.unread_for_customer as "unreadForCustomer",
    o.unread_for_driver as "unreadForDriver", o.last_message as "lastMessage",
    o.last_message_at as "lastMessageAt", o.created_at as "createdAt",
    o.updated_at as "updatedAt", o.accepted_at as "acceptedAt",
    o.started_at as "startedAt", o.completed_at as "completedAt"`;
}

export function createCoreRepository({ url, ca }) {
  const parsed = new URL(url);
  if (parsed.search || parsed.hash || !['postgres:', 'postgresql:'].includes(parsed.protocol)) {
    throw new Error('Runtime database URL must not override TLS options');
  }
  const pool = new pg.Pool({
    connectionString: url, max: 4, connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 5000, statement_timeout: 5000,
    ssl: { rejectUnauthorized: true, ...(ca && { ca }) },
  });
  pool.on('error', () => {});

  const account = async (uid, client = pool) => {
    const result = await client.query(`
      select a.id, a.firebase_uid as uid, a.email, a.role,
        a.display_name as "displayName", a.phone, a.photo_url as "photoUrl",
        a.email_verified as "emailVerified", a.profile_completed as "profileCompleted",
        a.account_status as "accountStatus",
        case when cp.account_id is null then null else jsonb_build_object(
          'defaultPickupAddress', cp.default_pickup_address,
          'defaultPickupLat', cp.default_pickup_lat,
          'defaultPickupLng', cp.default_pickup_lng) end as "customerProfile",
        case when dp.account_id is null then null else jsonb_build_object(
          'vehicleType', dp.vehicle_type, 'plateNumber', dp.plate_number,
          'verificationStatus', dp.verification_status, 'isOnline', dp.is_online,
          'currentLat', dp.current_lat, 'currentLng', dp.current_lng,
          'heading', dp.heading, 'locationUpdatedAt', dp.location_updated_at,
          'totalEarnings', dp.total_earnings) end as "driverProfile"
      from efata.accounts a
      left join efata.customer_profiles cp on cp.account_id = a.id
      left join efata.driver_profiles dp on dp.account_id = a.id
      where a.firebase_uid = $1
    `, [uid]);
    return result.rows[0] ?? null;
  };

  const listOrders = async ({ uid, scope = 'mine', page = 1, limit = 25, status }) => {
    const actor = await account(uid);
    if (!actor || actor.accountStatus !== 'active') throw new ApiError(403, 'account_unavailable');
    let condition;
    const values = [actor.id];
    if (scope === 'available' && actor.role === 'driver') {
      if (actor.driverProfile?.verificationStatus !== 'approved') {
        throw new ApiError(403, 'approved_driver_required');
      }
      condition = `o.status = 'pending' and o.driver_id is null`;
    } else if (scope === 'all' && actor.role === 'admin') {
      condition = 'true';
    } else if (scope === 'mine' && actor.role === 'driver') {
      condition = 'o.driver_id = $1';
    } else if (scope === 'mine' && actor.role === 'customer') {
      condition = 'o.customer_id = $1';
    } else if (scope === 'mine' && actor.role === 'admin') {
      condition = 'true';
    } else {
      throw new ApiError(403, 'scope_not_allowed');
    }
    if (status) {
      values.push(status);
      condition += ` and o.status = $${values.length}`;
    }
    values.push(limit + 1, (page - 1) * limit);
    const result = await pool.query(`
      select ${orderFields()}
      from efata.orders o where ${condition}
      order by o.created_at desc, o.id desc
      limit $${values.length - 1} offset $${values.length}
    `, values);
    return { orders: result.rows.slice(0, limit), nextPage: result.rows.length > limit ? page + 1 : null };
  };

  const createOrder = async ({ uid, order }) => {
    const actor = await account(uid);
    if (!actor || actor.role !== 'customer' || actor.accountStatus !== 'active') {
      throw new ApiError(403, 'customer_access_required');
    }
    const result = await pool.query(`
      insert into efata.orders
        (customer_id,pickup_label,pickup_lat,pickup_lng,dropoff_label,dropoff_lat,
         dropoff_lng,item_description,vehicle_type,scheduled_for,amount,payment_method)
      values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
      returning ${orderFields().replaceAll('o.', '')}
    `, [actor.id, order.pickup.label, order.pickup.lat, order.pickup.lng,
      order.dropoff.label, order.dropoff.lat, order.dropoff.lng, order.item,
      order.vehicleType, order.scheduledFor, order.amount, order.paymentMethod]);
    return result.rows[0];
  };

  const transitionOrder = async ({ uid, orderId, action }) => {
    const client = await pool.connect();
    try {
      await client.query('begin');
      const actor = await account(uid, client);
      if (!actor || actor.accountStatus !== 'active') throw new ApiError(403, 'account_unavailable');
      const locked = await client.query('select * from efata.orders where id = $1 for update', [orderId]);
      if (!locked.rowCount) throw new ApiError(404, 'order_not_found');
      const order = locked.rows[0];
      let update;
      if (action === 'accept') {
        if (actor.role !== 'driver' || actor.driverProfile?.verificationStatus !== 'approved' ||
            actor.driverProfile?.isOnline !== true) throw new ApiError(403, 'approved_online_driver_required');
        if (order.status !== 'pending' || order.driver_id) throw new ApiError(409, 'order_unavailable');
        await client.query(
          'select account_id from efata.driver_profiles where account_id=$1 for update',
          [actor.id],
        );
        const active = await client.query(`
          select 1 from efata.orders where driver_id=$1 and status in ('accepted','inTransit') limit 1
        `, [actor.id]);
        if (active.rowCount) throw new ApiError(409, 'current_order_active');
        update = `driver_id=$2,status='accepted',accepted_at=now()`;
      } else if (action === 'start') {
        if (actor.role !== 'driver' || order.driver_id !== actor.id || order.status !== 'accepted') {
          throw new ApiError(409, 'order_cannot_start');
        }
        update = `status='inTransit',started_at=now()`;
      } else if (action === 'complete') {
        if (actor.role !== 'driver' || order.driver_id !== actor.id || order.status !== 'inTransit') {
          throw new ApiError(409, 'order_cannot_complete');
        }
        update = `status='completed',completed_at=now(),chat_closed_at=now(),
          unread_for_customer=0,unread_for_driver=0`;
      } else if (action === 'cancel') {
        const allowed = actor.role === 'admin' ||
          (actor.role === 'customer' && order.customer_id === actor.id && order.status === 'pending');
        if (!allowed) throw new ApiError(409, 'order_cannot_cancel');
        update = `status='canceled',canceled_at=now(),canceled_by=$2,chat_closed_at=now(),
          unread_for_customer=0,unread_for_driver=0`;
      } else {
        throw new ApiError(400, 'invalid_action');
      }
      const params = action === 'accept' ? [orderId, actor.id]
        : action === 'cancel' ? [orderId, actor.uid] : [orderId];
      const result = await client.query(`
        update efata.orders set ${update} where id=$1
        returning ${orderFields().replaceAll('o.', '')}
      `, params);
      await client.query('commit');
      return result.rows[0];
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }
  };

  const listMessages = async ({ uid, orderId, page = 1, limit = 50 }) => {
    const actor = await account(uid);
    if (!actor || actor.accountStatus !== 'active') throw new ApiError(403, 'account_unavailable');
    const access = await pool.query(`
      select 1 from efata.orders
      where id=$1 and ($2='admin' or customer_id=$3 or driver_id=$3)
    `, [orderId, actor.role, actor.id]);
    if (!access.rowCount) throw new ApiError(404, 'order_not_found');
    const rows = await pool.query(`
      select m.id, m.sender_role as "senderRole", m.body,
        m.created_at as "createdAt", a.display_name as "senderName"
      from efata.order_messages m
      join efata.accounts a on a.id=m.sender_id
      where m.order_id=$1 order by m.created_at desc, m.id desc
      limit $2 offset $3
    `, [orderId, limit + 1, (page - 1) * limit]);
    return {
      messages: rows.rows.slice(0, limit).reverse(),
      nextPage: rows.rows.length > limit ? page + 1 : null,
    };
  };

  const sendMessage = async ({ uid, orderId, body }) => {
    const client = await pool.connect();
    try {
      await client.query('begin');
      const actor = await account(uid, client);
      if (!actor || actor.accountStatus !== 'active') throw new ApiError(403, 'account_unavailable');
      const locked = await client.query('select * from efata.orders where id=$1 for update', [orderId]);
      if (!locked.rowCount) throw new ApiError(404, 'order_not_found');
      const order = locked.rows[0];
      if (actor.role !== 'admin' && actor.id !== order.customer_id && actor.id !== order.driver_id) {
        throw new ApiError(404, 'order_not_found');
      }
      if (order.chat_closed_at || ['completed', 'canceled'].includes(order.status)) {
        throw new ApiError(409, 'chat_closed');
      }
      const message = await client.query(`
        insert into efata.order_messages (order_id,sender_id,sender_role,body)
        values ($1,$2,$3,$4)
        returning id,sender_role as "senderRole",body,created_at as "createdAt"
      `, [orderId, actor.id, actor.role, body]);
      const unread = actor.id === order.customer_id
        ? 'unread_for_driver=unread_for_driver+1'
        : actor.id === order.driver_id ? 'unread_for_customer=unread_for_customer+1' : '';
      await client.query(`
        update efata.orders set last_message=$2,last_message_at=now(),last_message_sender_id=$3
          ${unread ? `,${unread}` : ''}
        where id=$1
      `, [orderId, body, actor.id]);
      await client.query('commit');
      return { ...message.rows[0], senderName: actor.displayName };
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }
  };

  const markMessagesRead = async ({ uid, orderId }) => {
    const actor = await account(uid);
    if (!actor || !['customer', 'driver'].includes(actor.role)) {
      throw new ApiError(403, 'account_unavailable');
    }
    const column = actor.role === 'customer' ? 'unread_for_customer' : 'unread_for_driver';
    const participant = actor.role === 'customer' ? 'customer_id' : 'driver_id';
    const result = await pool.query(`
      update efata.orders set ${column}=0 where id=$1 and ${participant}=$2 returning id
    `, [orderId, actor.id]);
    if (!result.rowCount) throw new ApiError(404, 'order_not_found');
  };

  const setDriverAvailability = async ({ uid, online, location }) => {
    const actor = await account(uid);
    if (!actor || actor.role !== 'driver' || actor.accountStatus !== 'active' ||
        actor.driverProfile?.verificationStatus !== 'approved') {
      throw new ApiError(403, 'approved_driver_required');
    }
    if (online && !location) throw new ApiError(400, 'location_required');
    const result = await pool.query(`
      update efata.driver_profiles set is_online=$2,
        current_lat=coalesce($3,current_lat),current_lng=coalesce($4,current_lng),
        heading=coalesce($5,heading),location_updated_at=case when $3 is null then location_updated_at else now() end
      where account_id=$1
      returning is_online as "isOnline",current_lat as lat,current_lng as lng,
        heading,location_updated_at as "updatedAt"
    `, [actor.id, online, location?.lat ?? null, location?.lng ?? null, location?.heading ?? null]);
    return result.rows[0];
  };

  const updateDriverLocation = async ({ uid, location }) => {
    const actor = await account(uid);
    if (!actor || actor.role !== 'driver' || actor.driverProfile?.isOnline !== true) {
      throw new ApiError(409, 'driver_not_online');
    }
    const result = await pool.query(`
      update efata.driver_profiles set current_lat=$2,current_lng=$3,heading=$4,
        location_updated_at=now() where account_id=$1
      returning current_lat as lat,current_lng as lng,heading,location_updated_at as "updatedAt"
    `, [actor.id, location.lat, location.lng, location.heading]);
    return result.rows[0];
  };

  const getDriverLocation = async ({ uid, orderId }) => {
    const actor = await account(uid);
    if (!actor) throw new ApiError(403, 'account_unavailable');
    const result = await pool.query(`
      select dp.current_lat as lat,dp.current_lng as lng,dp.heading,
        dp.location_updated_at as "updatedAt",o.pickup_lat as "pickupLat",
        o.pickup_lng as "pickupLng",o.status
      from efata.orders o
      join efata.driver_profiles dp on dp.account_id=o.driver_id
      where o.id=$1 and ($2='admin' or o.customer_id=$3 or o.driver_id=$3)
    `, [orderId, actor.role, actor.id]);
    if (!result.rowCount) throw new ApiError(404, 'tracking_unavailable');
    return result.rows[0];
  };

  return {
    getMe: account, listOrders, createOrder, transitionOrder,
    listMessages, sendMessage, markMessagesRead,
    setDriverAvailability, updateDriverLocation, getDriverLocation,
    close: () => pool.end(),
  };
}
