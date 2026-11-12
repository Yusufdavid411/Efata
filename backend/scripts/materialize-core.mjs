import { createHash } from 'node:crypto';
import pg from 'pg';
import { decodeFirestoreDocument } from '../lib/firestore-wire.mjs';

const projectRef = 'fwjxmutbsiokeevgvbat';
const shouldApply = process.argv.includes('--apply');

function dbConfig() {
  const url = new URL(process.env.EFATA_DB_POOLER_URL ?? '');
  if (url.username !== `postgres.${projectRef}` || !url.hostname.endsWith('.pooler.supabase.com')) {
    throw new Error('The connection does not target the EFATA Supabase project');
  }
  if (!process.env.EFATA_DB_PASSWORD) throw new Error('Missing EFATA database password');
  return {
    host: url.hostname, port: Number(url.port || 6543), user: url.username,
    database: 'postgres', password: process.env.EFATA_DB_PASSWORD,
    ssl: { rejectUnauthorized: true }, connectionTimeoutMillis: 15_000,
  };
}

function cleanText(value) {
  if (value == null) return null;
  const result = String(value).trim();
  return result || null;
}

function cleanNumber(value) {
  if (value == null || value === '') return null;
  const result = Number(value);
  return Number.isFinite(result) ? result : null;
}

function cleanInteger(value) {
  const result = cleanNumber(value);
  return result == null ? 0 : Math.max(0, Math.trunc(result));
}

function cleanTimestamp(value, fallback = null) {
  if (value == null || value === '') return fallback;
  const raw = String(value);
  const date = typeof value === 'number' || /^\d{10,13}$/.test(raw)
    ? new Date(Number(value) < 1e12 ? Number(value) * 1000 : Number(value))
    : new Date(value);
  return Number.isNaN(date.valueOf()) ? fallback : date.toISOString();
}

function cleanEmail(value) {
  const result = cleanText(value)?.toLowerCase();
  return result?.includes('@') ? result : null;
}

export function normalizeRole(value, fallback = 'customer') {
  const role = cleanText(value)?.toLowerCase();
  return ['customer', 'driver', 'admin'].includes(role) ? role : fallback;
}

export function normalizeOrderStatus(value) {
  const status = cleanText(value)?.replaceAll('_', '').toLowerCase();
  if (status === 'accepted') return 'accepted';
  if (status === 'intransit') return 'inTransit';
  if (status === 'completed' || status === 'delivered') return 'completed';
  if (['rejected', 'cancelled', 'canceled'].includes(status)) return 'canceled';
  return 'pending';
}

export function normalizeVerificationStatus(value) {
  const status = cleanText(value)?.toLowerCase();
  return ['approved', 'rejected', 'suspended'].includes(status) ? status : 'pending';
}

function adminUid(address) {
  const digest = createHash('sha256').update(address).digest('hex').slice(0, 24);
  return `legacy-admin-email:${digest}`;
}

function mergeAccount(account, source, sourceName, fallbackRole) {
  if (cleanText(source.role)) account.role = normalizeRole(source.role, account.role);
  else if (sourceName === 'drivers' && account.role !== 'admin') account.role = 'driver';
  else account.role ??= fallbackRole;
  account.email ??= cleanEmail(source.email);
  account.displayName ??= cleanText(source.fullName ?? source.name ?? source.displayName);
  account.phone ??= cleanText(source.phone ?? source.phoneNumber);
  account.photoUrl ??= cleanText(source.photoUrl);
  account.emailVerified ||= source.emailVerified === true || source.emailVerifiedByCode === true;
  account.profileCompleted ||= source.profileCompleted === true;
  if (source.disabled === true || source.isSuspended === true) account.accountStatus = 'disabled';
  account.createdAt ??= cleanTimestamp(source.createdAt ?? source._firestoreCreateTime);
  account.updatedAt = cleanTimestamp(source.updatedAt ?? source._firestoreUpdateTime, account.updatedAt);
  account.legacyData[sourceName] = source;
}

function roleRank(role) {
  return { customer: 1, driver: 2, admin: 3 }[role] ?? 0;
}

function consolidateEmailDuplicates(accounts, aliases) {
  const groups = new Map();
  for (const account of accounts.values()) {
    if (!account.email) continue;
    if (!groups.has(account.email)) groups.set(account.email, []);
    groups.get(account.email).push(account);
  }
  let merged = 0;
  for (const group of groups.values()) {
    if (group.length < 2) continue;
    const authBacked = group.filter((account) => account.authBacked);
    if (authBacked.length > 1) throw new Error('Duplicate Firebase identities share an email');
    const winner = authBacked[0] ?? [...group].sort((a, b) =>
      Number(b.profileCompleted) - Number(a.profileCompleted) || roleRank(b.role) - roleRank(a.role))[0];
    for (const loser of group) {
      if (loser === winner) continue;
      if (roleRank(loser.role) > roleRank(winner.role)) winner.role = loser.role;
      winner.displayName ??= loser.displayName;
      winner.phone ??= loser.phone;
      winner.photoUrl ??= loser.photoUrl;
      winner.emailVerified ||= loser.emailVerified;
      winner.profileCompleted ||= loser.profileCompleted;
      if (loser.accountStatus === 'disabled') winner.accountStatus = 'disabled';
      winner.createdAt ??= loser.createdAt;
      winner.updatedAt = winner.updatedAt ?? loser.updatedAt;
      Object.assign(winner.legacyData, loser.legacyData);
      winner.providers.push(...loser.providers);
      for (const [alias, target] of aliases) {
        if (target === loser.uid) aliases.set(alias, winner.uid);
      }
      aliases.set(loser.uid, winner.uid);
      accounts.delete(loser.uid);
      merged++;
    }
  }
  return merged;
}

function createModel(rows, authRows) {
  const documents = rows.map((row) => ({
    path: row.document_path,
    parts: row.document_path.split('/'),
    id: row.document_path.split('/')[1],
    data: decodeFirestoreDocument(row.document),
  }));
  const collection = (name, depth) => documents.filter(
    (doc) => doc.parts[0] === name && doc.parts.length === depth,
  );
  const users = collection('users', 2);
  const drivers = collection('drivers', 2);
  const customers = collection('customers', 2);
  const orders = collection('orders', 2);
  const messages = collection('orders', 4);
  const payouts = collection('payouts', 2);
  const adminLogs = collection('adminLogs', 2);
  const accounts = new Map();
  const aliases = new Map();
  const ensure = (uid, role = 'customer') => {
    const key = cleanText(uid);
    if (!key) return null;
    if (!accounts.has(key)) accounts.set(key, {
      uid: key, role, email: null, displayName: null, phone: null, photoUrl: null,
      emailVerified: false, profileCompleted: false, accountStatus: 'active',
      createdAt: null, updatedAt: null, legacyData: {}, providers: [],
      authBacked: false,
    });
    return accounts.get(key);
  };
  const canonical = (value) => aliases.get(cleanText(value)) ?? cleanText(value);

  for (const row of authRows) {
    const account = ensure(row.firebase_uid);
    account.authBacked = true;
    mergeAccount(account, row.account_metadata, 'firebaseAuth', account.role);
    account.providers = row.account_metadata.providerUserInfo ?? [];
    aliases.set(row.firebase_uid, row.firebase_uid);
  }
  for (const doc of [...users, ...drivers, ...customers]) {
    const fallbackRole = doc.parts[0] === 'drivers' ? 'driver' : 'customer';
    const uid = cleanText(doc.data.uid ?? doc.data.driverId ?? doc.data.customerId ?? doc.id);
    aliases.set(doc.id, uid);
    for (const alias of [doc.data.uid, doc.data.driverId, doc.data.customerId]) {
      if (cleanText(alias)) aliases.set(cleanText(alias), uid);
    }
    mergeAccount(ensure(uid, fallbackRole), doc.data, doc.parts[0], fallbackRole);
  }
  for (const doc of orders) {
    ensure(canonical(doc.data.customerId) ?? `legacy-customer:${doc.id}`);
    if (cleanText(doc.data.driverId)) ensure(canonical(doc.data.driverId), 'driver');
    if (cleanText(doc.data.lastMessageSenderId)) ensure(canonical(doc.data.lastMessageSenderId));
  }
  for (const doc of messages) {
    if (cleanText(doc.data.senderId)) ensure(
      canonical(doc.data.senderId), normalizeRole(doc.data.senderRole),
    );
  }
  for (const doc of adminLogs) {
    const address = cleanEmail(doc.data.adminEmail);
    if (!address) continue;
    const existing = [...accounts.values()].find((account) => account.email === address);
    const account = existing ?? ensure(adminUid(address), 'admin');
    account.role = 'admin';
    account.email ??= address;
  }
  const mergedDuplicateAccounts = consolidateEmailDuplicates(accounts, aliases);
  return {
    accounts, aliases, canonical, customers, drivers, orders, messages, payouts,
    adminLogs, mergedDuplicateAccounts,
  };
}

async function saveAccount(client, account) {
  return (await client.query(`
    insert into efata.accounts
      (firebase_uid,email,role,display_name,phone,photo_url,email_verified,
       profile_completed,account_status,created_at,updated_at,legacy_data)
    values ($1,$2,$3,$4,$5,$6,$7,$8,$9,coalesce($10,now()),coalesce($11,now()),$12)
    on conflict (firebase_uid) do update set
      email=coalesce(efata.accounts.email,excluded.email),
      display_name=coalesce(efata.accounts.display_name,excluded.display_name),
      phone=coalesce(efata.accounts.phone,excluded.phone),
      photo_url=coalesce(efata.accounts.photo_url,excluded.photo_url),
      email_verified=efata.accounts.email_verified or excluded.email_verified,
      profile_completed=efata.accounts.profile_completed or excluded.profile_completed,
      account_status=excluded.account_status,
      legacy_data=efata.accounts.legacy_data || excluded.legacy_data
    returning id
  `, [account.uid, account.email, account.role, account.displayName, account.phone,
    account.photoUrl, account.emailVerified, account.profileCompleted, account.accountStatus,
    account.createdAt, account.updatedAt, account.legacyData])).rows[0].id;
}

async function saveIdentities(client, model, ids) {
  for (const account of model.accounts.values()) {
    const accountId = ids.get(account.uid);
    await client.query(`
      insert into efata.auth_identities (account_id,provider,provider_subject,email,last_seen_at)
      values ($1,'firebase',$2,$3,$4)
      on conflict (provider,provider_subject) do update set
        account_id=excluded.account_id,email=coalesce(excluded.email,efata.auth_identities.email)
    `, [accountId, account.uid, account.email, account.updatedAt]);
    for (const provider of account.providers) {
      const subject = cleanText(provider.rawId ?? provider.federatedId);
      const name = cleanText(provider.providerId);
      if (!subject || !name) continue;
      await client.query(`
        insert into efata.auth_identities (account_id,provider,provider_subject,email)
        values ($1,$2,$3,$4)
        on conflict (provider,provider_subject) do update set account_id=excluded.account_id
      `, [accountId, name, subject, cleanEmail(provider.email)]);
    }
  }
}

async function saveProfiles(client, model, ids) {
  for (const doc of model.customers) {
    const uid = model.canonical(doc.data.customerId ?? doc.id);
    await client.query(`
      insert into efata.customer_profiles (account_id,default_pickup_address,updated_at)
      values ($1,$2,coalesce($3,now()))
      on conflict (account_id) do update set
        default_pickup_address=coalesce(excluded.default_pickup_address,efata.customer_profiles.default_pickup_address),
        updated_at=excluded.updated_at
    `, [ids.get(uid), cleanText(doc.data.address), cleanTimestamp(doc.data.updatedAt)]);
  }
  for (const doc of model.drivers) {
    const uid = model.canonical(doc.data.uid ?? doc.data.driverId ?? doc.id);
    await client.query(`
      insert into efata.driver_profiles
        (account_id,vehicle_type,plate_number,license_file_key,verification_status,
         is_online,current_lat,current_lng,location_updated_at,updated_at)
      values ($1,$2,$3,$4,$5,$6,$7,$8,$9,coalesce($10,now()))
      on conflict (account_id) do update set
        vehicle_type=coalesce(excluded.vehicle_type,efata.driver_profiles.vehicle_type),
        plate_number=coalesce(excluded.plate_number,efata.driver_profiles.plate_number),
        license_file_key=coalesce(excluded.license_file_key,efata.driver_profiles.license_file_key),
        verification_status=excluded.verification_status,is_online=excluded.is_online,
        current_lat=excluded.current_lat,current_lng=excluded.current_lng,
        location_updated_at=excluded.location_updated_at,updated_at=excluded.updated_at
    `, [ids.get(uid), cleanText(doc.data.vehicleType), cleanText(doc.data.plateNumber),
      cleanText(doc.data.licenseUrl), normalizeVerificationStatus(doc.data.verificationStatus),
      doc.data.isOnline === true || doc.data.isAvailable === true,
      cleanNumber(doc.data.driverLat), cleanNumber(doc.data.driverLng),
      cleanTimestamp(doc.data.lastLocationUpdate), cleanTimestamp(doc.data.updatedAt)]);
  }
}

function reconcileActiveOrders(orders, canonical) {
  const activeByDriver = new Map();
  const reconciled = new Set();
  const sorted = [...orders].sort((a, b) =>
    (cleanTimestamp(b.data.updatedAt ?? b.data.createdAt) ?? '').localeCompare(
      cleanTimestamp(a.data.updatedAt ?? a.data.createdAt) ?? ''));
  for (const doc of sorted) {
    const status = normalizeOrderStatus(doc.data.status);
    const driver = cleanText(doc.data.driverId) && canonical(doc.data.driverId);
    if (!driver || !['accepted', 'inTransit'].includes(status)) continue;
    if (activeByDriver.has(driver)) reconciled.add(doc.id);
    else activeByDriver.set(driver, doc.id);
  }
  return reconciled;
}

async function saveOrders(client, model, ids) {
  const reconciled = reconcileActiveOrders(model.orders, model.canonical);
  const orderIds = new Map();
  for (const doc of model.orders) {
    const customer = model.canonical(doc.data.customerId) ?? `legacy-customer:${doc.id}`;
    const driver = cleanText(doc.data.driverId) && model.canonical(doc.data.driverId);
    const originalStatus = normalizeOrderStatus(doc.data.status);
    const status = reconciled.has(doc.id) ? 'canceled' : originalStatus;
    const completedAt = cleanTimestamp(doc.data.completedAt);
    const chatClosedAt = cleanTimestamp(doc.data.chatClosedAt, status === 'completed'
      ? completedAt ?? cleanTimestamp(doc.data.updatedAt ?? doc.data._firestoreUpdateTime) : null);
    const sender = cleanText(doc.data.lastMessageSenderId) && model.canonical(doc.data.lastMessageSenderId);
    const distanceKm = cleanNumber(doc.data.distanceKm);
    const row = await client.query(`
      insert into efata.orders
        (firebase_order_id,customer_id,driver_id,status,pickup_label,pickup_lat,pickup_lng,
         dropoff_label,dropoff_lat,dropoff_lng,item_description,vehicle_type,scheduled_for,
         distance_meters,amount,payment_method,payment_status,accepted_at,started_at,
         completed_at,canceled_at,chat_closed_at,unread_for_customer,unread_for_driver,
         last_message,last_message_at,last_message_sender_id,notification_status,
         needs_admin_review,created_at,updated_at,legacy_data)
      values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,
        $20,$21,$22,$23,$24,$25,$26,$27,$28,$29,coalesce($30,now()),coalesce($31,now()),$32)
      on conflict (firebase_order_id) do update set legacy_data=excluded.legacy_data
      returning id
    `, [doc.id, ids.get(customer), driver ? ids.get(driver) : null, status,
      cleanText(doc.data.pickup) ?? 'Unknown pickup', cleanNumber(doc.data.pickupLat),
      cleanNumber(doc.data.pickupLng), cleanText(doc.data.dropoff) ?? 'Unknown drop-off',
      cleanNumber(doc.data.dropoffLat), cleanNumber(doc.data.dropoffLng),
      cleanText(doc.data.item), cleanText(doc.data.vehicleType),
      cleanTimestamp(doc.data.scheduledPickupAt),
      distanceKm == null ? null : Math.round(distanceKm * 1000), cleanNumber(doc.data.price),
      cleanText(doc.data.paymentMethod), cleanText(doc.data.paymentStatus) ?? 'pending',
      cleanTimestamp(doc.data.acceptedAt), cleanTimestamp(doc.data.startedAt), completedAt,
      status === 'canceled' ? cleanTimestamp(doc.data.updatedAt ?? doc.data._firestoreUpdateTime) : null,
      chatClosedAt, status === 'completed' ? 0 : cleanInteger(doc.data.unreadForCustomer),
      status === 'completed' ? 0 : cleanInteger(doc.data.unreadForDriver),
      cleanText(doc.data.lastMessage), cleanTimestamp(doc.data.lastMessageAt),
      sender ? ids.get(sender) : null, cleanText(doc.data.notificationStatus),
      doc.data.needsAdminReview === true || doc.data.paymentReviewRequired === true,
      cleanTimestamp(doc.data.createdAt ?? doc.data._firestoreCreateTime),
      cleanTimestamp(doc.data.updatedAt ?? doc.data._firestoreUpdateTime),
      { ...doc.data, _materialization: { originalStatus, reconciledStaleActive: reconciled.has(doc.id) } }]);
    orderIds.set(doc.id, row.rows[0].id);
  }
  return { orderIds, reconciled };
}

async function saveMessages(client, model, ids, orderIds) {
  let saved = 0;
  for (const doc of model.messages) {
    const orderId = orderIds.get(doc.parts[1]);
    const sender = cleanText(doc.data.senderId) && model.canonical(doc.data.senderId);
    if (!orderId || !sender || !ids.has(sender) || !cleanText(doc.data.text)) continue;
    await client.query(`
      insert into efata.order_messages
        (firebase_message_id,order_id,sender_id,sender_role,body,created_at)
      values ($1,$2,$3,$4,$5,coalesce($6,now()))
      on conflict (order_id,firebase_message_id) do nothing
    `, [doc.parts[3], orderId, ids.get(sender), normalizeRole(doc.data.senderRole),
      cleanText(doc.data.text), cleanTimestamp(doc.data.createdAt ?? doc.data._firestoreCreateTime)]);
    saved++;
  }
  return saved;
}

async function saveAdminLogs(client, model, ids) {
  const fallback = [...model.accounts.values()].find((account) => account.role === 'admin');
  let saved = 0;
  for (const doc of model.adminLogs) {
    const address = cleanEmail(doc.data.adminEmail);
    const account = [...model.accounts.values()].find((item) => item.email === address) ?? fallback;
    if (!account) continue;
    await client.query(`
      insert into efata.admin_logs
        (firebase_log_id,admin_id,action,target_id,metadata,created_at)
      values ($1,$2,$3,$4,$5,coalesce($6,now()))
      on conflict do nothing
    `, [doc.id, ids.get(account.uid), cleanText(doc.data.action) ?? 'legacy_action',
      cleanText(doc.data.targetId), { changes: doc.data.changes, adminEmail: address },
      cleanTimestamp(doc.data.createdAt ?? doc.data._firestoreCreateTime)]);
    saved++;
  }
  return saved;
}

async function materialize(client, snapshotId, model) {
  const ids = new Map();
  for (const account of model.accounts.values()) ids.set(account.uid, await saveAccount(client, account));
  await saveIdentities(client, model, ids);
  await saveProfiles(client, model, ids);
  const { orderIds, reconciled } = await saveOrders(client, model, ids);
  const messages = await saveMessages(client, model, ids, orderIds);
  const adminLogs = await saveAdminLogs(client, model, ids);
  const report = {
    accounts: model.accounts.size, customers: model.customers.length,
    drivers: model.drivers.length, orders: model.orders.length, messages,
    skippedMessages: model.messages.length - messages,
    payoutsArchivedOnly: model.payouts.length, adminLogs,
    reconciledStaleActiveOrders: reconciled.size,
  };
  await client.query(`
    insert into efata.migration_runs (snapshot_id,report) values ($1,$2)
    on conflict (snapshot_id) do update set report=excluded.report
  `, [snapshotId, report]);
  return report;
}

async function main() {
  const client = new pg.Client(dbConfig());
  await client.connect();
  try {
    const snapshot = await client.query(
      'select id from efata_migration.snapshots order by imported_at desc limit 1',
    );
    if (!snapshot.rowCount) throw new Error('No Firebase archive snapshot found');
    const snapshotId = snapshot.rows[0].id;
    const documents = await client.query(
      'select document_path,document from efata_migration.firestore_documents where snapshot_id=$1',
      [snapshotId],
    );
    const auth = await client.query(
      'select firebase_uid,account_metadata from efata_migration.firebase_accounts where snapshot_id=$1',
      [snapshotId],
    );
    const existing = await client.query(
      'select count(*)::integer count from efata.migration_runs where snapshot_id=$1',
      [snapshotId],
    );
    if (existing.rows[0].count) throw new Error(`Snapshot ${snapshotId} was already materialized`);
    const model = createModel(documents.rows, auth.rows);
    const emailCounts = new Map();
    for (const account of model.accounts.values()) {
      if (account.email) emailCounts.set(account.email, (emailCounts.get(account.email) ?? 0) + 1);
    }
    const duplicateEmails = [...emailCounts.values()].filter((count) => count > 1).length;
    const plan = {
      snapshot: snapshotId, accounts: model.accounts.size,
      customerProfiles: model.customers.length, driverProfiles: model.drivers.length,
      orders: model.orders.length, messages: model.messages.length,
      payoutsArchivedOnly: model.payouts.length, adminLogs: model.adminLogs.length,
      duplicateEmails,
      mergedDuplicateAccounts: model.mergedDuplicateAccounts,
    };
    if (duplicateEmails) throw new Error(
      `Refusing to materialize ${duplicateEmails} duplicated account email(s)`,
    );
    if (!shouldApply) {
      console.log(JSON.stringify({ mode: 'dry-run', ...plan }, null, 2));
      return;
    }
    await client.query('begin');
    try {
      const report = await materialize(client, snapshotId, model);
      await client.query('commit');
      console.log(JSON.stringify({ mode: 'applied', snapshot: snapshotId, ...report }, null, 2));
    } catch (error) {
      await client.query('rollback');
      throw error;
    }
  } finally {
    await client.end();
  }
}

if (process.argv[1]?.endsWith('materialize-core.mjs')) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
