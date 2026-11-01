# Chat notification delivery

The auth stream is the only owner of chat order listeners. A session counter
rejects callbacks from a previous login, and delivery checks run serially.

Each recipient has a receipt at
`users/{uid}/chatNotificationReceipts/{orderId}` containing `messageTime` and
`deliveredAt`. A Firestore transaction reserves the latest message timestamp
before posting an alert. This prevents a replay on another login or phone.
Existing local SharedPreferences receipts are imported when encountered.
Notification receipts are separate from unread counts: an alert does not mark
the conversation as read.

Messages more than 24 hours old remain in chat history but do not generate
fresh alerts. Closed deliveries cannot alert without a known closure time or
for messages sent after closure. A recent, still-unread message sent before
closure can alert once. Read/stale alerts are removed from the notification
tray when their order snapshot is processed.

If the server receipt cannot be checked (including offline), no alert is
posted. Reserving before display deliberately favors preventing repeats:
a process crash after reservation can lose that alert, but the message remains
in chat. This is not a guarantee of exactly-once OS notification delivery.

Deploy `EFATA ADMIN/firestore.rules` before distributing this client. Receipt
documents are accessible only to their owning user. No Functions, push provider,
or new package is required. Existing chat notifications still rely on the app's
Firestore listeners, so this change does not add terminated-app push delivery.

Regression checks: `flutter test test/chat_notification_delivery_test.dart`.
