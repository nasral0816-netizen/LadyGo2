# LadyGo map providers (6.7.8.4)

- OpenFreeMap: default MapLibre basemap.
- Geoapify: primary address autocomplete and driving routing when GEOAPIFY_API_KEY is configured.
- Photon: fallback address search.
- Nominatim and Android Geocoder: additional address fallbacks.
- OSRM public routers: fallback driving routes.
- Protomaps: optional self-hosted MapLibre style/PMTiles. Set PROTOMAPS_STYLE_URL to a reachable MapLibre style JSON that references a hosted PMTiles archive. Protomaps is not a geocoder or routing API.

## GitHub Actions secrets
Repository Settings -> Secrets and variables -> Actions:
- GEOAPIFY_API_KEY: Geoapify project API key. If absent, Photon and existing fallbacks remain active.
- PROTOMAPS_STYLE_URL: optional URL to a hosted MapLibre style JSON backed by PMTiles. If absent, OpenFreeMap remains the basemap.

Keys are injected at build time and must not be committed to source code.

Public Photon, Nominatim, and OSRM endpoints have usage policies, rate limits, and no uptime guarantee. For production traffic, use an appropriate provider plan or self-hosted infrastructure.


Build note: Geoapify is enabled when the repository secret is present. Protomaps remains optional and is not enabled until a hosted style URL is supplied.
