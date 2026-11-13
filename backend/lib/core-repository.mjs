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
          'licenseUrl', dp.license_file_key,
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

  const getOrder = async ({ uid, orderId }) => {
    const actor = await account(uid);
    if (!actor || actor.accountStatus !== 'active') throw new ApiError(403, 'account_unavailable');
    const result = await pool.query(`
      select ${orderFields()} from efata.orders o
      where o.id=$1 and ($2='admin' or o.customer_id=$3 or o.driver_id=$3)
    `, [orderId, actor.role, actor.id]);
    if (!result.rowCount) throw new ApiError(404, 'order_not_found');
    return result.rows[0];
  };

  const bootstrapAccount = async ({ identity, role }) => {
    if (!identity.email) throw new ApiError(400, 'identity_email_required');
    const client = await pool.connect();
    try {
      await client.query('begin');
      let existing = identity.supabaseAuthId
        ? await client.query(
          'select id,firebase_uid,role,account_status from efata.accounts where supabase_auth_id=$1 for update',
          [identity.supabaseAuthId],
        )
        : await client.query(
          'select id,firebase_uid,role from efata.accounts where firebase_uid=$1 for update',
          [identity.uid],
        );
      if (identity.supabaseAuthId && existing.rowCount) {
        const current = existing.rows[0];
        if (current.account_status !== 'active') throw new ApiError(403, 'account_unavailable');
        if (role && role !== current.role) throw new ApiError(409, 'account_role_locked');
        await client.query('commit');
        return account(current.firebase_uid);
      }
      if (!existing.rowCount) {
        existing = await client.query(
          'select id,firebase_uid,role from efata.accounts where lower(email)=lower($1) for update',
          [identity.email],
        );
      }
      let accountId;
      let accountRole;
      if (existing.rowCount) {
        if (identity.supabaseAuthId) throw new ApiError(409, 'account_identity_conflict');
        const current = existing.rows[0];
        if (current.firebase_uid && current.firebase_uid !== identity.uid) {
          throw new ApiError(409, 'account_identity_conflict');
        }
        if (role && current.role !== role) throw new ApiError(409, 'account_role_locked');
        accountId = current.id;
        accountRole = current.role;
        await client.query(`
          update efata.accounts set firebase_uid=$2,
            email=coalesce(email,$3),
            display_name=case when nullif(display_name,'') is null then $4 else display_name end,
            photo_url=coalesce(photo_url,$5),
            email_verified=email_verified or $6
          where id=$1
        `, [accountId, identity.uid, identity.email, identity.displayName,
          identity.photoUrl, identity.emailVerified]);
      } else {
        if (!role) throw new ApiError(409, 'account_role_required');
        const inserted = await client.query(`
          insert into efata.accounts
            (firebase_uid,email,role,display_name,photo_url,email_verified,supabase_auth_id)
          values ($1,$2,$3,$4,$5,$6,$7) returning id,role
        `, [identity.uid, identity.email, role, identity.displayName,
          identity.photoUrl, identity.emailVerified, identity.supabaseAuthId ?? null]);
        accountId = inserted.rows[0].id;
        accountRole = inserted.rows[0].role;
      }
      if (identity.provider) {
        await client.query(`
          insert into efata.auth_identities
            (account_id,provider,provider_subject,email,last_seen_at)
          values ($1,$2,$3,$4,now())
          on conflict (provider,provider_subject) do update
          set account_id=excluded.account_id,email=excluded.email,last_seen_at=now()
        `, [accountId, identity.provider, identity.uid, identity.email]);
      }
      if (accountRole === 'customer') {
        await client.query(
          'insert into efata.customer_profiles (account_id) values ($1) on conflict do nothing',
          [accountId],
        );
      } else if (accountRole === 'driver') {
        await client.query(
          'insert into efata.driver_profiles (account_id) values ($1) on conflict do nothing',
          [accountId],
        );
      }
      await client.query('commit');
      return account(identity.uid);
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }
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

  const requireAdmin = async (uid, client = pool) => {
    const actor = await account(uid, client);
    if (!actor || actor.role !== 'admin' || actor.accountStatus !== 'active') {
      throw new ApiError(403, 'admin_access_required');
    }
    return actor;
  };

  const listAdminResource = async ({ uid, resource, page = 1, limit = 100 }) => {
    await requireAdmin(uid);
    const offset = (page - 1) * limit;
    let result;
    if (resource === 'drivers') {
      result = await pool.query(`
        select a.id,a.firebase_uid as "legacyId",a.display_name as name,a.email,a.phone,
          a.photo_url as "photoUrl",a.profile_completed as "profileCompleted",
          a.account_status as "accountStatus",dp.vehicle_type as "vehicleType",
          dp.plate_number as "plateNumber",dp.license_file_key as "licenseFileKey",
          case when dp.license_file_key like 'https://res.cloudinary.com/dk21bi5fg/image/upload/%'
            then dp.license_file_key end as "licenseUrl",
          dp.verification_status as "verificationStatus",dp.verification_notes as "verificationNotes",
          dp.is_online as "isOnline",dp.total_earnings as "totalEarnings",
          a.created_at as "createdAt",a.updated_at as "updatedAt"
        from efata.accounts a join efata.driver_profiles dp on dp.account_id=a.id
        order by a.created_at desc,a.id desc limit $1 offset $2
      `, [limit + 1, offset]);
    } else if (resource === 'users') {
      result = await pool.query(`
        select a.id,a.firebase_uid as "legacyId",a.display_name as name,a.email,a.phone,
          a.photo_url as "photoUrl",a.role,a.profile_completed as "profileCompleted",
          a.account_status as "accountStatus",(a.account_status='disabled') as "isSuspended",
          a.email_verified as "emailVerified",a.created_at as "createdAt",a.updated_at as "updatedAt"
        from efata.accounts a order by a.created_at desc,a.id desc limit $1 offset $2
      `, [limit + 1, offset]);
    } else if (resource === 'orders') {
      result = await pool.query(`
        select ${orderFields()},ca.display_name as "customerName",ca.firebase_uid as "customerId",
          da.display_name as "driverName",da.firebase_uid as "driverId",
          o.needs_admin_review as "needsAdminReview",
          o.payment_review_required as "paymentReviewRequired",
          o.dispute_status as "disputeStatus",o.dispute_note as "disputeNote",
          o.dispute_updated_at as "disputeUpdatedAt"
        from efata.orders o
        join efata.accounts ca on ca.id=o.customer_id
        left join efata.accounts da on da.id=o.driver_id
        order by o.created_at desc,o.id desc limit $1 offset $2
      `, [limit + 1, offset]);
    } else if (resource === 'payouts') {
      result = await pool.query(`
        select p.id,p.firebase_payout_id as "legacyId",p.driver_id as "driverAccountId",
          a.firebase_uid as "driverId",a.display_name as "driverName",p.amount,p.status,
          p.bank_reference as "bankReference",p.requested_at as "createdAt",
          p.processed_at as "processedAt",p.metadata
        from efata.payouts p join efata.accounts a on a.id=p.driver_id
        order by p.requested_at desc,p.id desc limit $1 offset $2
      `, [limit + 1, offset]);
    } else if (resource === 'logs') {
      result = await pool.query(`
        select l.id,l.action,l.target_type as "targetType",l.target_id as "targetId",
          l.metadata,l.created_at as "createdAt",a.display_name as "adminName",a.email as "adminEmail"
        from efata.admin_logs l join efata.accounts a on a.id=l.admin_id
        order by l.created_at desc,l.id desc limit $1 offset $2
      `, [limit + 1, offset]);
    } else {
      throw new ApiError(400, 'invalid_resource');
    }
    return {
      resource,
      rows: result.rows.slice(0, limit),
      nextPage: result.rows.length > limit ? page + 1 : null,
    };
  };

  const performAdminAction = async ({ uid, action, targetId, status, note, suspended }) => {
    const client = await pool.connect();
    try {
      await client.query('begin');
      const actor = await requireAdmin(uid, client);
      let targetType;
      let result;
      let metadata;
      if (action === 'driver-status') {
        const allowed = new Set(['pending', 'incomplete', 'approved', 'rejected', 'suspended']);
        if (!allowed.has(status)) throw new ApiError(400, 'invalid_driver_status');
        result = await client.query(`
          update efata.driver_profiles set verification_status=$2,
            verification_notes=nullif($3,''),is_online=case when $2='approved' then is_online else false end
          where account_id=$1 returning account_id as id,verification_status as status
        `, [targetId, status, note.slice(0, 1000)]);
        if (status === 'approved') {
          await client.query('update efata.accounts set profile_completed=true where id=$1', [targetId]);
        }
        targetType = 'driver';
        metadata = { status, note: note.slice(0, 1000) || null };
      } else if (action === 'user-status') {
        if (typeof suspended !== 'boolean') throw new ApiError(400, 'invalid_user_status');
        if (targetId === actor.id) throw new ApiError(409, 'cannot_suspend_self');
        const target = await client.query('select role from efata.accounts where id=$1 for update', [targetId]);
        if (target.rows[0]?.role === 'admin') throw new ApiError(409, 'cannot_suspend_admin');
        result = await client.query(`
          update efata.accounts set account_status=$2 where id=$1
          returning id,account_status as status
        `, [targetId, suspended ? 'disabled' : 'active']);
        targetType = 'account';
        metadata = { suspended };
      } else if (action === 'order-dispute') {
        if (!['open', 'resolved'].includes(status)) throw new ApiError(400, 'invalid_dispute_status');
        if (note.length > 1000) throw new ApiError(400, 'dispute_note_too_long');
        result = await client.query(`
          update efata.orders set dispute_status=$2,dispute_note=nullif($3,''),
            dispute_updated_at=now(),needs_admin_review=($2='open'),
            payment_review_required=($2='open') where id=$1
          returning id,dispute_status as status
        `, [targetId, status, note]);
        targetType = 'order';
        metadata = { status, note: note || null };
      } else if (action === 'payout-status') {
        const allowed = new Set(['pending', 'ready', 'review', 'approved', 'held', 'processing', 'paid', 'rejected']);
        if (!allowed.has(status)) throw new ApiError(400, 'invalid_payout_status');
        result = await client.query(`
          update efata.payouts set status=$2,
            processed_at=case when $2 in ('paid','rejected') then now() else processed_at end
          where id=$1 returning id,status
        `, [targetId, status]);
        targetType = 'payout';
        metadata = { status };
      } else {
        throw new ApiError(400, 'invalid_action');
      }
      if (!result.rowCount) throw new ApiError(404, 'target_not_found');
      await client.query(`
        insert into efata.admin_logs (admin_id,action,target_type,target_id,metadata)
        values ($1,$2,$3,$4,$5::jsonb)
      `, [actor.id, action, targetType, targetId, JSON.stringify(metadata)]);
      await client.query('commit');
      return result.rows[0];
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }
  };

  return {
    getMe: account, bootstrapAccount, listOrders, getOrder, createOrder, transitionOrder,
    listMessages, sendMessage, markMessagesRead,
    setDriverAvailability, updateDriverLocation, getDriverLocation,
    listAdminResource, performAdminAction,
    async updateProfile(uid, data) {
      const client = await pool.connect();
      try {
        await client.query('begin');
        await client.query('select id from efata.accounts where firebase_uid=$1 for update', [uid]);
        const actor = await account(uid, client);
        if (!actor || actor.accountStatus !== 'active' || !['customer','driver'].includes(actor.role)) {
          throw new ApiError(403, 'account_unavailable');
        }
        const { name, phone, address, vehicleType, plateNumber, licenseUrl, photoUrl } =
          Object.fromEntries(Object.entries(data).map(([key, value]) => [key, value.trim()]));
        if (actor.role === 'customer') {
          if (vehicleType || plateNumber || licenseUrl) throw new ApiError(400, 'invalid_profile');
          if (address) await client.query('update efata.customer_profiles set default_pickup_address=$2 where account_id=$1', [actor.id, address]);
        } else {
          if (address) throw new ApiError(400, 'invalid_profile');
          await client.query(`
            update efata.driver_profiles set vehicle_type=coalesce($2,vehicle_type),
              plate_number=coalesce($3,plate_number), license_file_key=coalesce($4,license_file_key),
              verification_status=case when verification_status='approved' and
                (($2 is not null and vehicle_type is distinct from $2) or
                 ($3 is not null and plate_number is distinct from $3) or
                 ($4 is not null and license_file_key is distinct from $4))
                then 'pending' else verification_status end,
              is_online=case when ($2 is not null and vehicle_type is distinct from $2) or
                 ($3 is not null and plate_number is distinct from $3) or
                 ($4 is not null and license_file_key is distinct from $4)
                then false else is_online end
            where account_id=$1
          `, [actor.id, vehicleType, plateNumber, licenseUrl]);
        }
        const complete = Boolean((name ?? actor.displayName) && (phone ?? actor.phone) &&
          (actor.role === 'customer' ? (address ?? actor.customerProfile?.defaultPickupAddress) :
            (vehicleType ?? actor.driverProfile?.vehicleType) &&
            (plateNumber ?? actor.driverProfile?.plateNumber) &&
            (licenseUrl ?? actor.driverProfile?.licenseUrl)));
        await client.query(`update efata.accounts set display_name=coalesce($2,display_name),
          phone=coalesce($3,phone), photo_url=coalesce($4,photo_url), profile_completed=$5 where id=$1`,
        [actor.id, name, phone, photoUrl, complete]);
        const updated = await account(uid, client);
        await client.query('commit');
        return updated;
      } catch (error) {
        await client.query('rollback');
        throw error;
      } finally {
        client.release();
      }
    },
    async findSupabaseIdentity(id) {
      const result = await pool.query(`
        select firebase_uid as uid, email, display_name as "displayName",
          photo_url as "photoUrl", email_verified as "emailVerified"
        from efata.accounts where supabase_auth_id=$1 and account_status='active'
      `, [id]);
      return result.rows[0] ?? null;
    },
    close: () => pool.end(),
  };
}
