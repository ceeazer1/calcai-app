# App Store submission draft

Draft only. Fill REQUIRED fields and resolve RELEASE_READINESS.md before upload.

| Field | Draft |
| --- | --- |
| Name | CalcAI |
| Subtitle | Set up your CalcAI device |
| Language / category | English (U.S.) / Utilities — confirm |
| Bundle ID | com.calcai.calcaiApp |
| Marketing URL | https://calcai.cc |
| Privacy URL | https://calcai.cc/privacy — correct API-key disclosure first |
| Support URL | REQUIRED: verified public support/help page |
| Support email | info@calcai.cc — confirm inbox is monitored |
| Copyright | REQUIRED: rights holder and year |
| Price / territories | REQUIRED: owner decision |
| Keywords | calculator,device,setup,wifi,bluetooth,notes,history |

## Promotional text

Set up your CalcAI device, manage its Wi-Fi networks, and keep your notes,
history, and device settings together.

## Description

CalcAI is the companion app for your CalcAI-enabled calculator.

Pair your device over Bluetooth and connect it to Wi-Fi. Add or update saved
networks, manage your device's AI settings, write notes, and view past questions,
answers, and photos associated with your account.

- Guided device pairing and Wi-Fi setup
- Saved-network and phone-hotspot settings
- Notes and conversation history
- Calculator photo viewing, saving, and sharing
- AI model and response preferences
- Account management and in-app account deletion

A compatible CalcAI device and a CalcAI account are required for device features.
Internet access is required for cloud features. AI responses may be inaccurate;
check important results. Use CalcAI only where permitted.

Before publishing, describe precisely any separately purchased hardware, paid AI
service, limits, or provider-account requirements. The app has Free/Pro labels and
customer API-key settings; no StoreKit purchasing flow was found. Confirm the
business model against the rules for the selected storefronts. Do not invent a
subscription or assume external purchasing is automatically allowed.

## Review notes — complete before sending

CalcAI is a companion app for a physical CalcAI-enabled calculator. Bluetooth
pairing and Wi-Fi management require that accessory. Cloud features use the
account linked to the device.

REQUIRED review account/password: enter a dedicated account securely in App Store
Connect. Do not commit credentials.

REQUIRED hardware/access arrangements: provide compatible CalcAI hardware and
instructions so reviewers can exercise pairing and Wi-Fi.

1. Sign in using the review account. On AI sharing, review the provider/content
   disclosure and choose Allow AI sharing or Continue without AI. The latter
   keeps setup available while AI remains disabled. Verify the deployed flow
   before using these instructions for review.
2. Turn on the supplied calculator and enable its pairing mode. Tap Scan and
   enter the code displayed by that device. There is no fixed demo code.
3. Choose Wi-Fi, enter a password if needed, and connect. Home page opens the
   dashboard after pairing.
4. Open Edit network from Home to manage saved networks and hotspot settings.
5. Review Notes, History, and Settings. Account deletion is in Settings; provide
   another disposable account if deleting the review account would interrupt
   the primary review setup.

REQUIRED review contact: name, reachable email, phone.

REQUIRED business-model explanation: what hardware includes, what costs extra,
and how any paid service is accessed.

The removed previews are not a shipping demo mode. A recorded walkthrough can
supplement reviewer access but does not validate actual connectivity.

## Privacy worksheet

Confirm against the deployed backend, logging/retention jobs and SDKs. The app's
privacy manifest does not complete App Store Connect's questionnaire.

| Data | Purpose observed/expected | Linked to account? |
| --- | --- | --- |
| Email | Authentication/recovery | Yes |
| User/account ID | Authorization and ownership | Yes |
| CalcAI device ID | Pairing and device content/configuration | Yes |
| Other user content | Notes, prompts, responses, custom instructions | Yes |
| Photos/videos category | Calculator images used for AI and history | Yes |
| Product interaction | Stored usage counts/request history | Yes |
| Name, diagnostics, IP/location, other categories | Verify actual SDK/backend collection and storage | Confirm |

No advertising/tracking SDK was identified; confirm all provider uses before
answering tracking questions. Provisioning sends Wi-Fi passwords to the calculator
over Bluetooth, not to the cloud. Customer AI API keys do reach CalcAI's backend
and need accurate disclosure and protection.

## Screenshots and remaining fields

Capture the final native build with an authorized test account: setup, code
entry, selected Wi-Fi, Home, network editing, Notes/History. Do not show real
customer data or the removed preview phone frame. Because iPad is enabled,
prepare its screenshots too. Use the sizes App Store Connect requests:
[Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
No App Store screenshots were certified by this audit.

Complete the current age-rating questionnaire based on actual AI content and
controls, content rights, export compliance, availability, pricing, and any
territory-specific business information. Do not choose a Kids category or fixed
age rating without that assessment.
