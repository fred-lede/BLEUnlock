# Telegram Photo Location Design

## Goal

Optionally attach the Mac's location at the time of an intrusion snapshot to
the Telegram notification. A successful notification includes coordinates and
a map link in the photo caption, followed by a Telegram native location
message. Location failures must never prevent the security photo or fallback
text notification from being sent.

## Scope

- Use the Mac's Core Location result, not the monitored Bluetooth device's
  location.
- Apply location only to Telegram notifications that take a photo, including
  the Telegram test notification when photo capture is enabled.
- Add an opt-in **Attach Mac Location** Telegram menu item. It defaults to off
  for both existing and new installations.
- Do not continuously track location, reverse-geocode an address, embed a map
  image into the photo, or add an iPhone companion component.

## User Experience and Privacy

The Telegram submenu places **Attach Mac Location** below the existing
**Take Photo on Manual Unlock** item. The location option is available only
when photo capture is enabled. Enabling it requests macOS location permission
at the point of user intent; leaving it disabled never starts Core Location.

The app includes localized macOS location-purpose text in every currently
supported localization, including Traditional Chinese. A denied or restricted
permission remains a recoverable condition: BLEUnlock sends the photo with a
localized “location unavailable” note instead of repeatedly prompting or
blocking the alert.

Coordinates exist only in memory until they are placed in the Telegram
request. BLEUnlock does not persist them to UserDefaults, Keychain, files, or
ordinary error logs. Error messages must not expose coordinates, Bot Token, or
Chat ID.

## Architecture

### Location boundary

Introduce a `MacLocationProviding` protocol with a one-shot asynchronous
request and cancellation. Its production implementation owns a
`CLLocationManager`, creates and drives it on the main run loop, handles
authorization changes, calls `requestLocation()`, and completes exactly once.
The request uses an internal five-second timeout and stops Core Location after
success, failure, denial, restriction, timeout, or cancellation.

The provider returns a small app-owned `TelegramLocation` value containing:

- latitude and longitude;
- horizontal accuracy in metres;
- Core Location's measurement timestamp.

The boundary rejects coordinates outside valid ranges, negative horizontal
accuracy, and results more than 60 seconds from the intrusion snapshot time.
It does not expose `CLLocation` outside the location adapter.

### Notification orchestration

When an enabled `.intruded` event requires a photo and location attachment,
`TelegramNotificationService` records the event timestamp and immediately
starts photo capture and the one-shot location request in parallel. Photo
capture is never delayed, preserving the scene at the moment of the event.

A small coordination object owns the two asynchronous results and finalizes
once both are available or the location request times out. It guarantees a
single send path even if timeout and Core Location callbacks race. The normal
photo-caption send waits at most five seconds for location.

On valid location:

1. Format the existing event message with snapshot time, latitude, longitude,
   horizontal accuracy, and an HTTPS Apple Maps link.
2. Send the photo with that caption using the existing `sendPhoto` path.
3. After photo success, call Telegram Bot API `sendLocation` with the same
   latitude and longitude so Telegram renders its native map.
4. Clean up the temporary photo using the existing behavior.

On missing location, send the photo with the original event message plus a
localized “location unavailable” line. On camera failure, retain the current
plain-text fallback and do not send a location message. On native-location
message failure, keep the already-sent photo and report the Telegram failure
locally; do not resend the photo.

### Telegram transport

Extend `TelegramSending` with `sendLocation`. `TelegramNotifier` implements it
as a form-encoded request to the Telegram Bot API `sendLocation` endpoint with
`chat_id`, `latitude`, and `longitude`. It reuses the existing HTTP transport,
response decoding, credential redaction, timeout, and error mapping.

### Settings and localization

`TelegramSettings` stores a Boolean `attachMacLocation` preference whose
missing-key default is `false`. `TelegramMenuController` reflects and updates
the preference, disables the item when photo capture is off, and initiates the
permission request only when the user enables it. Disabling the setting
prevents future location requests; an already-dispatched notification
completes normally.

Add localized strings for:

- the menu item;
- the photo-caption labels for snapshot time, coordinates, accuracy, map, and
  location unavailable;
- local location and Telegram map-delivery failures;
- the macOS location usage description.

## Failure Semantics

- Location services disabled, permission denied/restricted, invalid/stale
  data, Core Location error, or five-second timeout: send the photo without a
  map and mark location unavailable.
- Camera failure: report the camera error and use the existing text fallback;
  do not send coordinates or a native map.
- Photo upload failure: report the existing Telegram error, remove the
  temporary photo, and do not call `sendLocation`.
- Native map failure after photo success: report the error locally; the photo
  remains the authoritative notification.
- Multiple or late Core Location callbacks: ignore them after the coordinator
  has completed.

## Testing

Unit tests cover:

- the setting's default-off behavior, persistence, and menu check/enabled
  states;
- no Core Location request when the option or photo capture is disabled;
- authorization success, denial, restriction, Core Location error, timeout,
  cancellation, and exactly-once completion;
- acceptance of a fresh valid location and rejection of stale coordinates,
  out-of-range coordinates, or negative horizontal accuracy;
- immediate parallel start of photo and location work;
- coordination races and the five-second upper bound;
- caption time, coordinate, accuracy, map-link, and unavailable formatting;
- photo-before-native-map ordering and matching coordinates;
- camera, photo-upload, native-map, and temporary-file cleanup failures;
- `sendLocation` request method, endpoint, form fields, response decoding, and
  credential redaction;
- presence and completeness of all localized strings and location-purpose
  descriptions.

Final verification uses a fixed-location, production-signed BLEUnlock build on
real macOS hardware. It confirms the one-time location authorization dialog,
photo caption, map link, Telegram native map, denied-permission fallback, and
that disabling the option causes no location request.

## API References

- [Apple: CLLocationManager](https://developer.apple.com/documentation/corelocation/cllocationmanager)
- [Apple: Requesting authorization to use location services](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)
- [Telegram Bot API: sendLocation](https://core.telegram.org/bots/api#sendlocation)
