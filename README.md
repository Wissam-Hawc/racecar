# Race Car

Monorepo for a connected race-car telemetry system. It has three components:

| Folder | Stack | Description |
| --- | --- | --- |
| [`racecar_firmware/`](racecar_firmware) | PlatformIO / C++ | Embedded firmware running on the on-car microcontroller. Publishes telemetry over MQTT. |
| [`gateway/`](gateway) | Docker Compose | Edge gateway stack: Mosquitto (MQTT broker), Node-RED (flow logic), InfluxDB (time-series storage) and Grafana (dashboards). |
| [`racecar_app/`](racecar_app) | Flutter | Cross-platform app to control the cars and start a race. |

## Architecture

```
racecar_firmware  --MQTT-->  gateway (Mosquitto -> Node-RED -> InfluxDB -> Grafana)
                                  ^
racecar_app  --------------------/   (subscribes to MQTT topics)
```

## Getting started

### Gateway
```bash
cd gateway
docker compose up -d
```
> Runtime data, databases, credentials and tokens are intentionally **not** committed
> (see `.gitignore`). Provide your own secrets when bringing the stack up.

### Firmware
```bash
cd racecar_firmware
pio run            # build
pio run -t upload  # flash
```

### App
```bash
cd racecar_app
flutter pub get
flutter run
```
