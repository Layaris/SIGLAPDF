/// Versione e build, passate in fase di build con --dart-define (vedi workflow di pubblicazione).
class AppInfo {
  static const name = 'Sigla';
  static const version = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
  static const build = String.fromEnvironment('APP_BUILD', defaultValue: 'sviluppo');
  static const releasesUrl = 'https://github.com/Layaris/DMReleases/tree/main/sigla';
}
