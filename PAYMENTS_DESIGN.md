# EFATA payment design

Design only. Cash stays unchanged. No checkout, balance or top-up is enabled by this document.

## Checkout

After the customer reviews the fare, show a Payment row with the selected method. Tapping it opens a sheet with Cash, Card and EFATA Balance once each method is available. Show the amount in NGN, any fee, and the total before confirmation. If the balance is insufficient, say how much is missing and offer Card or Cash. Do not silently switch payment methods.

For Card, the backend creates a pending payment against the order's server-side quote and opens Flutterwave hosted checkout. EFATA does not collect or store card numbers or CVVs. On return show Pending until the backend verifies the payment. Show Paid, Failed, or Canceled as appropriate, and let customers retry a failed payment without creating a second order. Saved cards are out of scope for the first release.

## Wallet

Place EFATA Balance under Profile > Payments. Show available balance and transaction history with date, amount, status, and reference. For the first release, use EFATA-issued credits only: no customer top-ups, cash-outs, or transfers. Show credits and refunds separately; a card refund should go back through the original payment method rather than becoming a credit without consent. Revisit funded balances after reviewing provider support, reconciliation, and applicable requirements.

## Backend and operations

- Store values as integer kobo. Derive the amount from a server-owned quote, not the phone.
- Verify Flutterwave transaction status, reference, amount, and currency server-side. Verify webhook signatures and make callbacks idempotent; a redirect alone does not establish payment.
- Record wallet changes as ledger entries. Debit the wallet and confirm the order in one transaction so concurrent checkouts cannot spend the same balance.
- Give admin a reference-based view of pending, paid, failed and refunded payments. Keep card secrets and merchant credentials server-side only.
- Use sandbox first. Test success, cancel, timeout, duplicate and out-of-order events, insufficient balance, and refunds before enabling a method for customers.

Reference: https://developer.flutterwave.com/docs/collections-inflow/flutterwave-standard
