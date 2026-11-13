class EfataBackendConfig {
  const EfataBackendConfig._();

  static const apiOrigin = String.fromEnvironment(
    'EFATA_API_ORIGIN',
    defaultValue: 'https://api.efata.io',
  );

  static const useNewBackend = true;
}
