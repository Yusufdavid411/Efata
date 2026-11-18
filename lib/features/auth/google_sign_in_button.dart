import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/services/account_access_service.dart';
import '../../core/services/app_notification_banner_service.dart';
import '../../core/services/efata_api_client.dart';
import '../../core/services/efata_session.dart';

class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({
    super.key,
    this.role,
    this.enabled = true,
    this.onBusyChanged,
  });
  final String? role;
  final bool enabled;
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  static Future<void>? _initialization;
  bool _busy = false;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    widget.onBusyChanged?.call(true);
    try {
      const clientId = String.fromEnvironment('GOOGLE_SIGN_IN_WEB_CLIENT_ID');
      if (clientId.isEmpty) {
        throw const EfataApiException('google_not_configured', statusCode: 503);
      }
      _initialization ??= GoogleSignIn.instance.initialize(
        serverClientId: clientId,
      );
      await _initialization;
      // Clear the SDK's selection so every explicit tap can choose an account.
      await GoogleSignIn.instance.signOut();
      final google = await GoogleSignIn.instance.authenticate();
      final token = google.authentication.idToken;
      if (token == null) {
        throw StateError('Google did not return an identity token');
      }
      await EfataSession.instance.signInWithGoogleToken(token);
      try {
        await _openAccount();
      } on EfataApiException catch (error) {
        if (error.code != 'account_role_required') rethrow;
        if (!mounted) return;
        final role =
            widget.role ??
            await showModalBottomSheet<String>(
              context: context,
              showDragHandle: true,
              builder: (sheet) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Choose your account',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: const Text('Passenger'),
                      subtitle: const Text('Send and track goods'),
                      onTap: () => Navigator.pop(sheet, 'customer'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.local_shipping_outlined),
                      title: const Text('Driver'),
                      subtitle: const Text('Accept delivery jobs'),
                      onTap: () => Navigator.pop(sheet, 'driver'),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
        if (role == null || !mounted) {
          EfataSession.instance.clear();
          return;
        }
        await _openAccount(role: role);
      }
    } on GoogleSignInException catch (error) {
      EfataSession.instance.clear();
      if (error.code != GoogleSignInExceptionCode.canceled) {
        AppNotificationBannerService.error(
          'Google sign-in could not finish. Check your connection and try again.',
          title: 'Google sign-in unavailable',
        );
      }
    } on EfataApiException catch (error) {
      EfataSession.instance.clear();
      AppNotificationBannerService.error(
        error.code == 'google_not_configured'
            ? 'Google sign-in configuration is not available. Please use email for now.'
            : error.code == 'account_unavailable'
            ? 'This account is unavailable. Contact support.'
            : 'Google sign-in could not finish. Please try again.',
        title: 'Google sign-in unavailable',
      );
    } catch (_) {
      EfataSession.instance.clear();
      AppNotificationBannerService.error(
        'Please check your connection and try again.',
        title: 'Google sign-in unavailable',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  Future<void> _openAccount({String? role}) async {
    final account = await EfataApiClient.instance.bootstrapAccount(role: role);
    final access = AccountAccess.fromApi(account);
    if (access.isBlocked || !['customer', 'driver'].contains(access.role)) {
      throw const EfataApiException('account_unavailable', statusCode: 403);
    }
    EfataSession.instance.accountUid = account.uid;
    if (mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(access.landingRoute, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 54,
    child: OutlinedButton.icon(
      onPressed: _busy || !widget.enabled ? null : _signIn,
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Image.asset('assets/auth/google-logo.png', width: 20, height: 20),
      label: Text(_busy ? 'Connecting...' : 'Continue with Google'),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF142520),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
