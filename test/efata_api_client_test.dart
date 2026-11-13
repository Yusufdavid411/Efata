import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logistics_app/core/services/efata_api_client.dart';

void main() {
  test(
    'getMe sends the current identity token and decodes the account',
    () async {
      late http.Request captured;
      final client = EfataApiClient(
        apiOrigin: 'https://api.efata.io',
        tokenProvider: ({required refresh}) async => 'token-one',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'account': {
                'uid': 'EFATA-1',
                'email': 'driver@efata.io',
                'role': 'driver',
                'displayName': 'David',
                'accountStatus': 'active',
                'emailVerified': true,
                'profileCompleted': true,
              },
            }),
            200,
          );
        }),
      );

      final account = await client.getMe();

      expect(captured.url.toString(), 'https://api.efata.io/api/me');
      expect(captured.headers['authorization'], 'Bearer token-one');
      expect(account.displayName, 'David');
      expect(account.role, 'driver');
    },
  );

  test(
    'a 401 refreshes the EFATA token once and retries the request',
    () async {
      final refreshes = <bool>[];
      var calls = 0;
      final client = EfataApiClient(
        tokenProvider: ({required refresh}) async {
          refreshes.add(refresh);
          return refresh ? 'fresh-token' : 'old-token';
        },
        httpClient: MockClient((request) async {
          calls++;
          if (calls == 1) {
            return http.Response('{"error":"session_invalid"}', 401);
          }
          expect(request.headers['authorization'], 'Bearer fresh-token');
          return http.Response('{"orders":[],"nextPage":null}', 200);
        }),
      );

      final page = await client.listOrders();

      expect(page.orders, isEmpty);
      expect(refreshes, [false, true]);
      expect(calls, 2);
    },
  );

  test('bootstrap sends only the selected application role', () async {
    late http.Request captured;
    final client = EfataApiClient(
      tokenProvider: ({required refresh}) async => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'account': {
              'uid': 'new-user',
              'email': 'new@efata.io',
              'role': 'customer',
              'displayName': 'New User',
              'accountStatus': 'active',
              'emailVerified': true,
              'profileCompleted': false,
            },
          }),
          200,
        );
      }),
    );

    final account = await client.bootstrapAccount(role: 'customer');

    expect(captured.url.path, '/api/account-bootstrap');
    expect(jsonDecode(captured.body), {'role': 'customer'});
    expect(account.role, 'customer');
  });

  test('order responses accept PostgreSQL numeric strings', () async {
    final client = EfataApiClient(
      tokenProvider: ({required refresh}) async => 'token',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'orders': [
              {
                'id': '5eed799d-793d-41de-9220-cf27928864a7',
                'status': 'pending',
                'pickup': 'Lagos',
                'pickupLat': '6.455',
                'pickupLng': '3.384',
                'dropoff': 'Abuja',
                'dropoffLat': '9.077',
                'dropoffLng': '7.398',
                'item': 'Documents',
                'vehicleType': 'Van',
                'paymentMethod': 'Transfer',
                'amount': '12500.50',
                'distanceMeters': '760000',
                'durationSeconds': '34200',
                'unreadForCustomer': 0,
                'unreadForDriver': 1,
              },
            ],
            'nextPage': null,
          }),
          200,
        ),
      ),
    );

    final order = (await client.listOrders()).orders.single;

    expect(order.amount, 12500.5);
    expect(order.pickupLat, 6.455);
    expect(order.distanceMeters, 760000);
    expect(order.unreadForDriver, 1);
  });

  test('structured API errors retain their status and code', () async {
    final client = EfataApiClient(
      tokenProvider: ({required refresh}) async => 'token',
      httpClient: MockClient(
        (request) async => http.Response('{"error":"chat_closed"}', 409),
      ),
    );

    expect(
      () => client.sendMessage('5eed799d-793d-41de-9220-cf27928864a7', 'Hello'),
      throwsA(
        isA<EfataApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.code, 'code', 'chat_closed'),
      ),
    );
  });

  test('listAllOrders follows bounded order pages', () async {
    final requestedPages = <String?>[];
    final client = EfataApiClient(
      tokenProvider: ({required refresh}) async => 'token',
      httpClient: MockClient((request) async {
        requestedPages.add(request.url.queryParameters['page']);
        final page = int.parse(request.url.queryParameters['page']!);
        return http.Response(
          jsonEncode({
            'orders': [
              {
                'id': 'order-$page',
                'status': 'completed',
                'pickup': 'Pickup',
                'dropoff': 'Drop-off',
                'item': 'Parcel',
                'vehicleType': 'Van',
                'paymentMethod': 'Transfer',
                'amount': 1000,
              },
            ],
            'nextPage': page == 1 ? 2 : null,
          }),
          200,
        );
      }),
    );

    final orders = await client.listAllOrders();

    expect(requestedPages, ['1', '2']);
    expect(orders.map((order) => order.id), ['order-1', 'order-2']);
  });
}
