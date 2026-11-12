function decodeNumber(value) {
  if (value === 'NaN') return Number.NaN;
  if (value === 'Infinity') return Number.POSITIVE_INFINITY;
  if (value === '-Infinity') return Number.NEGATIVE_INFINITY;
  return Number(value);
}

export function decodeFirestoreValue(value) {
  if (!value || typeof value !== 'object') return null;
  if (Object.hasOwn(value, 'nullValue')) return null;
  if (Object.hasOwn(value, 'stringValue')) return value.stringValue;
  if (Object.hasOwn(value, 'booleanValue')) return value.booleanValue;
  if (Object.hasOwn(value, 'integerValue')) return Number(value.integerValue);
  if (Object.hasOwn(value, 'doubleValue')) return decodeNumber(value.doubleValue);
  if (Object.hasOwn(value, 'timestampValue')) return value.timestampValue;
  if (Object.hasOwn(value, 'referenceValue')) return value.referenceValue;
  if (Object.hasOwn(value, 'bytesValue')) return value.bytesValue;
  if (Object.hasOwn(value, 'geoPointValue')) {
    return {
      latitude: Number(value.geoPointValue.latitude),
      longitude: Number(value.geoPointValue.longitude),
    };
  }
  if (Object.hasOwn(value, 'arrayValue')) {
    return (value.arrayValue.values ?? []).map(decodeFirestoreValue);
  }
  if (Object.hasOwn(value, 'mapValue')) {
    return decodeFirestoreFields(value.mapValue.fields ?? {});
  }
  throw new Error(`Unsupported Firestore value: ${Object.keys(value).join(',')}`);
}

export function decodeFirestoreFields(fields = {}) {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, decodeFirestoreValue(value)]),
  );
}

export function decodeFirestoreDocument(document) {
  return {
    ...decodeFirestoreFields(document?.fields ?? {}),
    _firestoreCreateTime: document?.createTime ?? null,
    _firestoreUpdateTime: document?.updateTime ?? null,
  };
}
