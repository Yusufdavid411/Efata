import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/services/efata_api_client.dart';

Future<void> showParcelPhoto(BuildContext context, String orderId) {
  final photo = EfataApiClient.instance.getParcelPhoto(orderId);
  return showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Parcel photo'),
      content: FutureBuilder<String?>(
        future: photo,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 56,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) return const Text('Could not load the photo.');
          final data = snapshot.data;
          if (data == null) return const Text('No photo was attached.');
          return Image.memory(
            base64Decode(data),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Text('Could not display the photo.'),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
