# CalcAI Link review access

Apple lists a demo video or hardware as options when features require special
hardware. A video is not a guarantee of acceptance or a replacement for reviewer
login access. Reference: https://developer.apple.com/app-store/review/

## Film a short real-device walkthrough

Use another phone/camera so the reviewer can see the iPhone and calculator
together. Use the final candidate and firmware 1.3.1. Avoid filming passwords,
private API keys, personal photos or customer activity. Roughly 2–3 minutes:

1. Show CalcAI Link on the iPhone and the CalcAI calculator beside it. Sign in to
   a dedicated sample account; obscure the password.
2. Open Bluetooth setup on the calculator. Scan, enter the displayed pairing
   code and show the calculator responding.
3. Choose Wi-Fi, connect, and show the calculator leaving Wi-Fi mode.
4. Press Home page after Device paired. Show the AI-sharing explanation and
   allow sharing on this sample account.
5. Submit a simple math question/photo on the calculator. Show its answer and
   the matching activity in the app. Open a sample note and AI preferences.
6. Open Edit network, demonstrate the inline network details, then close the
   Bluetooth portal. Show the closed portal on the calculator. Finish with
   Settings, the Welcome expiry, AI sharing control and Delete Account option.

Attach the video or an accessible viewing link in App Review Information.
Do not substitute browser mockups for footage of the accessory working. A
separate disposable-account deletion test remains part of release validation;
do not delete the reviewer account while Apple is reviewing it.

## Reviewer account

Create a dedicated normal account with no customer data and a stable email and
password sign-in. Enter the credentials directly in App Store Connect's review
fields, not in this repository or public notes. Keep it active through review.
Explain which features require the calculator and what can be tested without it.
No hidden reviewer bypass or hard-coded production pairing code is provided.
