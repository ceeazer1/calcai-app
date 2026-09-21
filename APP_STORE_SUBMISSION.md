# CalcAI Link — submission draft

Prepared September 21, 2026. Core copy below is saved in App Store Connect; this is not a submission or approval. Resolve [RELEASE_READINESS.md](RELEASE_READINESS.md) before sending.

| Field | Value |
| --- | --- |
| Store name | CalcAI Link (existing name retained) |
| Subtitle | Set up your CalcAI device |
| Language / category | English (U.S.) / Utilities |
| Apple ID / Bundle ID | 6780132992 / com.calcai.calcaiApp |
| Support | https://calcai.cc/help |
| Marketing | https://calcai.cc |
| Privacy | https://calcai.cc/privacy — update live API-key disclosure before release |
| Copyright | 2026 CALCAI LLC (matches the public website; confirm rights before declaration) |
| Keywords | calculator,device,setup,wifi,bluetooth,notes,history |
| Release | Manual |
| Download price / territory | Free ($0.00) / United States only; saved September 21 |

## Promotional text

Pair your CalcAI calculator, manage Wi-Fi, and keep your notes, activity and AI settings together.

## Description

CalcAI Link is the companion app for your CalcAI enabled calculator.

DEVICE SETUP
Pair your calculator over Bluetooth using the code shown on its screen, then connect it to Wi-Fi. Manage saved networks and phone-hotspot settings from the app.

YOUR AI SETTINGS
Choose your AI model and response preferences, add custom instructions, and see your remaining AI allowance and reset time. Available models and usage limits depend on your plan. You can optionally add your own supported AI-provider API key in Settings; the provider’s billing and limits apply.

Your first calculator link starts a 30-day welcome allowance with a higher daily AI limit. After 30 days, your account continues on Free. No payment is required and there is no automatic charge. Paid Pro is not offered in this release.

NOTES AND ACTIVITY
Write notes for your calculator and review past questions, answers and photos. Save or share calculator photos using the iPhone or iPad share controls.

YOUR CHOICE
Before AI sharing is enabled, the app explains what content is shared with the selected AI provider and asks for your permission. You can change this choice in Settings. With AI sharing off, AI answers and photo solving are unavailable; pairing and Wi-Fi management remain available.

A compatible CalcAI device and a CalcAI account are required for device features. Internet access is required for cloud features. AI responses may be inaccurate; check important results. Use CalcAI only where permitted.

## Review notes saved

CalcAI Link is a companion app for a physical CalcAI-enabled calculator. Bluetooth pairing and Wi-Fi management require that accessory.

Setup flow:
1. Sign in, open Bluetooth setup on the calculator, and tap Scan in the app.
2. Enter the six-digit code displayed by that calculator. There is no fixed demo code in the shipping app.
3. Select a Wi-Fi network and connect. Device paired appears next.
4. Press Home page. If no AI-sharing choice has been saved, a popup appears over the blurred Home screen. Allow AI sharing enables AI requests. Continue with AI off explains the consequence before saving that choice. Pairing and Wi-Fi still work with AI off.
5. On Home, open Edit network to manage networks and phone-hotspot settings. Leaving that screen offers to keep the Bluetooth portal open or close it.
6. Notes, activity history and AI preferences are available in the main app. Settings includes AI sharing controls, personal provider keys, Privacy Policy, support and account deletion.

Personal provider API keys are optional. They are sent to CalcAI’s backend over HTTPS for storage and use with the selected provider. Provider charges and limits apply.

Launch business model: free download, United States only. The first verified calculator link starts a 30-day welcome allowance using the finite Pro daily AI limit; the account returns to Free afterward. No payment authorization, automatic renewal, in-app purchase or external Pro checkout is offered in this version. Personal provider keys remain optional. Paid Pro sales will be added separately in a future release.

## Add after the owner resolves these details

- Welcome allowance deployed September 21 as API version `b98d3953-8a3f-45c7-a582-3ff37b0f8327`; expiry/relinking covered by backend tests. Confirm the new Settings date presentation in the next native candidate. Do not describe this as an Apple subscription trial.
- Dedicated review account/password (App Store Connect only, never Git), contact name/phone/email, hardware-access arrangements and any useful review video.
- Actual screenshot set and native archive selection, privacy questionnaire, age rating, rights and business declarations.

## Privacy worksheet

| Category | Observed purpose / linkage |
| --- | --- |
| Email Address | Account sign-in and recovery; account-linked |
| User ID | Authentication/ownership; account-linked |
| Device ID | Calculator ownership and settings/content; account-linked |
| Other User Content | Prompts, answers, notes and custom instructions; account-linked |
| Photos or Videos | Calculator images for solving/history; account-linked |
| Product Interaction | Usage allowance and request history; account-linked |
| Name | Displayed/stored locally by the app; verify provider/SDK collection before final answer |
| Other categories | Reconcile actual provider credentials, diagnostics/logging and SDK collection; do not assume the list above is exhaustive |

No advertising/tracking SDK was identified in app source. Verify actual third-party uses before making the tracking declaration. Wi-Fi credentials go to the calculator over Bluetooth. Personal AI keys go to CalcAI's backend and then the selected provider. Provider retention and any legacy deletion gaps remain separate verification items.
