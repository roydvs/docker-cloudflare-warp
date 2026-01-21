# Cloudflare WARP Docker Container

[![Build Status](https://img.shields.io/github/actions/workflow/status/roydvs/docker-cloudflare-warp/docker-publish.yaml?logo=github)](https://github.com/roydvs/docker-cloudflare-warp/actions/workflows/docker-publish.yaml)
[![GHCR](https://img.shields.io/badge/ghcr.io-roydvs%2Fdocker--cloudflare--warp-blue?logo=github)](https://github.com/roydvs/docker-cloudflare-warp/pkgs/container/docker-cloudflare-warp)
[![License](https://img.shields.io/github/license/roydvs/docker-cloudflare-warp)](LICENSE)

A containerized Cloudflare WARP client supporting both standard authentication and Zero Trust organizational management. This image installs the official Cloudflare WARP client directly from the official repository and provides an easy way to containerize your network traffic.

## Features

- **Two Operating Modes**
  - Proxy Mode (default): Exposes SOCKS5 proxy for selective routing
  - WARP Mode: Routes all traffic through WARP tunnel
  
- **Multiple Authentication Methods**
  - Standard WARP (free or licensed)
  - Cloudflare Zero Trust ([organizational MDM](https://developers.cloudflare.com/cloudflare-one/tutorials/warp-on-headless-linux/))
  - Configuration persistence across restarts

- **Flexible Protocol Support**
  - MASQUE (default)
  - WireGuard

## Quick Start

### Proxy Mode (Recommended)

```bash
docker run --rm -d -p 40000:40000 ghcr.io/roydvs/docker-cloudflare-warp:latest
```

or you can use `docker compose`:

```bash
docker compose -f compose-example.yaml up -d cf-warp-proxy
```

### WARP Mode (Full Tunnel)

```bash
docker run --rm -d -e WARP_MODE=warp ghcr.io/roydvs/docker-cloudflare-warp:latest
```

or you can use `docker compose`:

```bash
docker compose -f compose-example.yaml up -d cf-warp
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WARP_MODE` | `proxy` | `proxy` or `warp` |
| `WARP_PROXY_PORT` | `40000` | SOCKS5 proxy listening port |
| `WARP_PROTOCOL` | `masque` | `masque` or `wireguard` |
| `WARP_LICENSE` | - | Optional WARP Plus license key |
| `WARP_ORG` | - | Zero Trust organization name |
| `WARP_CLIENT_ID` | - | Zero Trust client ID |
| `WARP_CLIENT_SECRET` | - | Zero Trust client secret |

### Authentication Priority

1. **Existing Config** - Uses saved configuration from previous sessions
2. **Zero Trust** - Requires all three: `WARP_ORG`, `WARP_CLIENT_ID`, `WARP_CLIENT_SECRET`
3. **Standard WARP** - Falls back to free registration or provided license

## Usage Examples

### Docker Compose

It is recommended to use `docker compose` for easier management. Refer to the [compose-example.yaml](compose-example.yaml) file in this repository. It demonstrates:

- Proxy mode setup with SOCKS5 proxy
- WARP tunnel mode configuration
- Volume mounts for configuration persistence
- Environment variable configurations
- Health checks and container networking

You can use it as a reference to build your own Docker Compose setup or run it directly with the Quick Start commands above.

### Docker CLI

Run the container with the default settings (Proxy Mode):

```bash
docker run --rm -d \
  -p 40000:40000 \
  -e WARP_MODE=proxy \
  ghcr.io/roydvs/docker-cloudflare-warp:latest
```

### Build from Source

If you wish to build the image locally:

```bash
git clone https://github.com/roydvs/docker-cloudflare-warp.git
cd docker-cloudflare-warp
docker build -t cloudflare-warp-local .
```

## System Requirements

**For Proxy Mode:**
- Docker runtime
- Network connectivity

**For WARP Mode:**
- Docker with `--cap-add=NET_ADMIN`
- Access to `/dev/net/tun` device
- Linux host (macOS/Windows Docker Desktop has limited support for device mapping)

## Troubleshooting

### View Logs
```bash
docker compose logs cf-warp
```

### Check WARP Status
```bash
docker compose exec cf-warp warp-cli --accept-tos status
```

### Test Proxy Connection
```bash
docker compose exec cf-warp curl -x socks5h://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace

curl -x socks5h://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace | grep warp
```

### Verify WARP Connection
```bash
curl -s https://www.cloudflare.com/cdn-cgi/trace | grep warp
```

## Notes

- Configuration is persisted in the volume mount `/var/lib/cloudflare-warp`.
- Private IP ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) are typically excluded from WARP to maintain local connectivity.
- Health checks validate connectivity every 30 seconds.
- The container starts `dbus` daemon automatically for WARP client communication.

## Disclaimer

- **Unofficial**: This project is an unofficial community effort and is **not** affiliated with, sponsored by, or endorsed by **Cloudflare, Inc.**
- **Proprietary Software**: The Cloudflare WARP client binary installed during the build process is the property of **Cloudflare, Inc**. By using this image, you agree to [Cloudflare's Terms of Service](https://www.cloudflare.com/application/terms/).
- **Use at Your Own Risk**: The author is not responsible for any consequences resulting from the use or misuse of this software. Users are responsible for complying with all applicable laws and terms.

For official Cloudflare WARP information, visit: [https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/)

## Credits

* [**Cloudflare WARP**](https://pkg.cloudflareclient.com/) (Proprietary Software)
* [**Ubuntu Docker Image**](https://hub.docker.com/_/ubuntu) (Base Image)

## License

This project is licensed under the [MIT License](LICENSE).