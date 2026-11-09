const firestore = 'https://firestore.googleapis.com/v1';
const identity = 'https://identitytoolkit.googleapis.com/v1';
const storage = 'https://storage.googleapis.com/storage/v1';
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const encodePath = (path) => path.split('/').map(encodeURIComponent).join('/');

export async function request(url, { token, body, label, quotaProject, fetcher = fetch } = {}) {
  for (let attempt = 0; ; attempt++) {
    let response;
    try {
      response = await fetcher(url, {
        method: body === undefined ? 'GET' : 'POST',
        headers: {
          ...(token && { Authorization: 'Bearer ' + token }),
          ...(quotaProject && { 'x-goog-user-project': quotaProject }),
          ...(body !== undefined && { 'Content-Type': 'application/json' }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        redirect: 'error',
        signal: AbortSignal.timeout(45_000),
      });
    } catch {
      if (attempt >= 3) throw new Error(label + ': network request failed');
    }
    if (response?.ok) return response;
    if (response) {
      await response.body?.cancel();
      if (attempt >= 3 || (response.status !== 429 && response.status < 500)) {
        throw new Error(label + ': HTTP ' + response.status);
      }
    }
    await pause(500 * 2 ** attempt);
  }
}

export async function* paginate(loadPage, items) {
  let pageToken;
  const seen = new Set();
  do {
    const page = await loadPage(pageToken);
    yield* page[items] ?? [];
    pageToken = page.nextPageToken;
    if (pageToken && seen.has(pageToken)) throw new Error('Repeated pagination token');
    seen.add(pageToken);
  } while (pageToken);
}

function urlWith(base, params) {
  const url = new URL(base);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) url.searchParams.set(key, value);
  }
  return url;
}

export function firebaseSource({ project, token, fetcher = fetch }) {
  const call = (url, label, body, quotaProject) =>
    request(url, { token, label, body, quotaProject, fetcher });
  const json = async (...args) => (await call(...args)).json();

  return {
    async databases() {
      return (await json(firestore + '/projects/' + project + '/databases', 'Firestore databases')).databases ?? [];
    },
    async *documents(database, readTime) {
      const root = firestore + '/' + encodePath(database) + '/documents';
      const queue = [''];
      for (let i = 0; i < queue.length; i++) {
        const parent = root + (queue[i] ? '/' + encodePath(queue[i]) : '');
        const collections = paginate(
          (pageToken) => json(parent + ':listCollectionIds', 'Firestore collections', {
            pageToken, pageSize: 100, readTime,
          }),
          'collectionIds',
        );
        for await (const id of collections) {
          const documents = paginate(
            (pageToken) => json(urlWith(parent + '/' + encodeURIComponent(id), {
              pageToken, pageSize: 100, showMissing: true, readTime,
            }), 'Firestore documents'),
            'documents',
          );
          const prefix = database + '/documents/';
          for await (const document of documents) {
            if (!document.name?.startsWith(prefix)) throw new Error('Invalid Firestore document name');
            const path = document.name.slice(prefix.length);
            queue.push(path);
            if (document.createTime || document.updateTime || document.fields) yield { path, document };
          }
        }
      }
    },
    accounts() {
      return paginate(
        (nextPageToken) => json(urlWith(identity + '/projects/' + project + '/accounts:batchGet', {
          nextPageToken, maxResults: 1000,
        }), 'Firebase Auth accounts', undefined, project),
        'users',
      );
    },
    buckets() {
      return paginate(
        (pageToken) => json(urlWith(storage + '/b', { project, pageToken }), 'Google Storage buckets'),
        'items',
      );
    },
    objects(bucket) {
      return paginate(
        (pageToken) => json(urlWith(storage + '/b/' + encodeURIComponent(bucket) + '/o', {
          pageToken, versions: true,
        }), 'Google Storage objects'),
        'items',
      );
    },
    object(object) {
      return call(urlWith(storage + '/b/' + encodeURIComponent(object.bucket) + '/o/' +
        encodeURIComponent(object.name), { alt: 'media', generation: object.generation }), 'Google Storage download');
    },
  };
}

export function cloudinaryReferences(value, refs = new Set()) {
  if (typeof value === 'string' && value.startsWith('https://res.cloudinary.com/dk21bi5fg/')) {
    const url = new URL(value);
    if (/^\/(?:dk21bi5fg)\/(?:image|video|raw)\/upload\//.test(url.pathname)) refs.add(url.href);
  } else if (value && typeof value === 'object') {
    for (const child of Object.values(value)) cloudinaryReferences(child, refs);
  }
  return refs;
}
