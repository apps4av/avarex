# OpenFlightMaps compliance checklist

OpenFlightMaps (OFM) data in AvareX is optional, source-labelled, and complementary. It must not be represented as certified or as a primary navigation source.

Release requirements:

- Display “© open flightmaps association” whenever an OFM map layer is visible.
- Show the complementary-data disclaimer before users install OFM products.
- Mark OFM search results and details with their OFM source, region, and cycle.
- Include instructions to report known data errors to open flightmaps association.
- Keep OFM region data independently installable and removable without changing FAA `main.db`.
- Before distributing prebuilt OFM data, obtain human/legal confirmation of the current OFMA General Users License and packaging requirements.

Current application text is centralized in `lib/ofm/ofm_constants.dart`.
