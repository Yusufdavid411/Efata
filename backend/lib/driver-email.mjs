export async function sendDriverReviewEmail(to, status) {
  const { EFATA_RESEND_API_KEY: key, EFATA_EMAIL_FROM: from } = process.env;
  if (!key || !from || !to) return;
  const approved = status === 'approved';
  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(3000),
      headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from, to: [to],
        subject: approved ? 'Your EFATA driver account is approved' : 'EFATA received your driver documents',
        text: approved
          ? 'You are now a verified EFATA driver. Open EFATA to go online and receive delivery requests.'
          : 'Your driver documents are awaiting review. Please allow 24 to 48 hours. You can replace documents from your profile while review is pending.',
      }),
    });
    await response.body?.cancel();
    if (!response.ok) console.warn('Driver review email rejected', response.status);
  } catch {
    console.warn('Driver review email request failed');
  }
}
