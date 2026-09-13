# 🚀 Ultra-Lightweight Debian XRDP Docker

An optimized, near-zero idle CPU & RAM Debian XFCE desktop accessible via Remote Desktop Protocol (RDP). Ready for local Docker and Cloud platforms like **Railway**.

---

## ⚡ Features
- **Ultra Low Footprint**: Window compositor disabled, low bit-depth (16-bpp) rendering, and stream compression for silky smooth performance over high-latency connections.
- **Root Login**: Direct `root` user access with password `root` (customizable via `ROOT_PASSWORD` env).
- **Railway & Cloud Ready**: Dynamically reads `$PORT` provided by cloud platforms like Railway and binds XRDP automatically.
- **Self-Healing & Auto TLS**: Automatically manages machine IDs, TLS certificates, and cleans stale X11/XRDP locks on container reboot.
- **Normal Debian Workflow**: Full `apt` support, terminal (`xfce4-terminal`), browser (`firefox-esr`), Python 3, curl, wget, and networking tools pre-installed.

---

## 🛠️ Run Locally (Docker)

```bash
# 1. Build the image
docker build -t debian-xrdp .

# 2. Run the container
docker run -d \
  -p 3389:3389 \
  -e ROOT_PASSWORD=root \
  --name debian-xrdp \
  debian-xrdp
```

### Connect:
- **Host / IP**: `localhost` (or your machine's IP)
- **Port**: `3389`
- **Username**: `root`
- **Password**: `root`

---

## 🚂 Deploy on Railway

1. Push this repository to GitHub.
2. In Railway, click **New Project** -> **Deploy from GitHub repo**.
3. Railway will automatically build using the `Dockerfile`.
4. In Railway project settings, add a **TCP Proxy** or **Public Networking** port mapping to port `3389` (or reference Railway's assigned port).
5. (Optional) Set environment variable `ROOT_PASSWORD` in Railway variables to set your own custom root password.

---

## 🔐 Credentials
| Key | Default Value |
|---|---|
| **User** | `root` |
| **Password** | `root` (or set via `ROOT_PASSWORD`) |
| **Port** | `3389` (or set via `PORT`) |

