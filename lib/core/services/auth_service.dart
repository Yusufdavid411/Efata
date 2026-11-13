import 'efata_session.dart';

class AuthService {
  Future<void> logout() async => EfataSession.instance.clear();
}
