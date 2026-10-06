# Migration Runbook — Event custom registration form (Flutter consumer app)

Deploy **after** backend + EMS migrations and storefront releases. No database migration in this repo.

Registration forms apply to **general admission (non–seat-selection) events** only — free or paid checkout.

**v1 payment scope:** Stripe (`create-payment-intent`) and free register only. Paytrail and Nabil are **out of scope** for this release (existing paths unchanged).

## Pre-conditions

- Backend deployed with `registrationAnswers` on free register and Stripe `create-payment-intent`
- Events can expose `otherInfo.registrationForm` in event detail API
- `file_picker` dependency resolved (`flutter pub get`)

## What changed

- `lib/utils/registration_form.dart` — schema, validation, GA-only guard
- `lib/widgets/registration_form_fields.dart` — dynamic fields + file upload UI
- `lib/services/registration_upload_service.dart` — multipart upload / delete
- Free registration modal on event detail (GA events only)
- GA paid checkout collects answers before payment; passed to Stripe `create-payment-intent`
- Seated events: no custom fields; free seated flow unchanged (seat picker first)

## Step 1 — Build

```bash
cd finnep_eventapp_client
flutter pub get
flutter analyze
flutter build apk   # or ios / appbundle as usual
```

## Step 2 — Smoke test matrix

| Scenario | Expected |
|----------|----------|
| GA free event with form | Modal shows custom fields; register succeeds; answers on ticket |
| GA paid event with form | Checkout shows fields; payment includes `registrationAnswers` |
| Seated free event | Seat flow only; no registration form |
| Seated paid event | Seat checkout; no registration fields |
| Required field empty | Client validation blocks submit |
| File field | Upload → register/checkout attaches file metadata on ticket |

## Rollback

Redeploy previous app build. Events without a registration form behave as before (email-only).

## Related

- Backend: `finnep-eventapp-backend/docs/MIGRATION_RUNBOOK_FREE_EVENT_REGISTRATION_FORM.md`
- Storefront: `finnep-eventapp/docs/MIGRATION_RUNBOOK_FREE_EVENT_REGISTRATION_FORM.md`
- EMS: `event-merchant-service/docs/MIGRATION_RUNBOOK_FREE_EVENT_REGISTRATION_FORM.md`
