class EfataBackendConfig {
  const EfataBackendConfig._();

  static const apiOrigin = String.fromEnvironment(
    'EFATA_API_ORIGIN',
    defaultValue: 'https://api.efata.io',
  );

  static const useNewBackend = bool.fromEnvironment(
    'EFATA_USE_NEW_BACKEND',
    defaultValue: false,
  );
}
