# LadyGo map providers — verified client implementation

## Current implementation found in src/LadyGoApp.js

- **MapLibre** renders the map using the OpenFreeMap Liberty style.
- **Photon** is used for address suggestions.
- **OSRM public routing** is used for driving route calculation.
- **Expo Location / Android Geocoder** provide device location and reverse geocoding fallbacks.
- Public Photon and OSRM services have usage limits and no production uptime guarantee.

## Not yet confirmed as integrated

- Geoapify is mentioned in older documentation but no Geoapify API call was found in the checked client source.
- Protomaps is an optional configuration idea; no self-hosted style is configured in the checked app.
- A production geocoding/routing provider and its service plan still need to be selected before high-volume launch.

## Configuration

`EXPO_PUBLIC_PROTOMAPS_STYLE_URL` is a future/optional style override. Do not commit provider secrets. Client-side `EXPO_PUBLIC_*` values are visible in the built app and must never contain server credentials.
