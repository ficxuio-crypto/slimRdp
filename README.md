# 🚀 Ultra-Lightweight Debian XRDP Docker

An optimized, near-zero idle CPU & RAM Debian XFCE desktop accessible via Remote Desktop Protocol (RDP). Built perfectly for local Docker and Cloud platforms like **Railway**.

---

## ⚡ Features
- **Ultra Low Footprint**: Uses XFCE4 and Xorg XRDP backend for silky smooth performance over high-latency connections.
- **Root Login**: Direct `root` user access with password `root` (customizable via `ROOT_PASSWORD` env).
- **Railway & Cloud Ready**: Dynamically reads `$PORT` provided by cloud platforms like Railway and binds XRDP automatically.
- **Modern RDP Compatibility**: Fully compatible with modern mobile RDP clients (standard high encryption and negotiation enabled).
- **Normal Debian Workflow**: Full `apt` support, terminal (`xfce4-terminal`), browser (`firefox-esr`), curl, wget, and networking tools pre-installed.

---

## 📱 How to Connect (Crucial!)

**❌ DO NOT USE VNC CLIENTS:** 
Apps like *RealVNC Viewer* or *VNC Viewer* will **not work** because this is an RDP server, not a VNC server.

**✅ USE RDP CLIENTS:**
You must use a dedicated Remote Desktop Protocol app, such as:
- **Microsoft Remote Desktop** (RD Client)
- **aRDP** 

### Connecting via Railway
1. **Never use `localhost` or HTTP domains** on your phone to connect to Railway.
2. Go to your Railway service's **Networking** settings.
3. Enable a **TCP Proxy**. 
4. Railway will give you a public TCP proxy domain and port (e.g., `roundhouse.proxy.rlwy.net:12345`).
5. Enter this proxy domain and port into your RDP Client!

---

## 🛠️ Run Locally (Docker)

```bash
# 1. Build the image
docker build -t debian-xrdp .

# 2. Run the container
docker run -d \
  -p 3389:3389 \
  -e ROOT_PASSWORD=my_secure_password \
  --name debian-xrdp \
  debian-xrdp
```

### Local Connection Details:
- **Host / IP**: Your computer's local IP (e.g., `192.168.1.50`)
- **Port**: `3389`
- **Username**: `root`
- **Password**: `my_secure_password`

---

## 🚂 Deploy on Railway

1. Push this repository to GitHub.
2. In Railway, click **New Project** -> **Deploy from GitHub repo**.
3. Railway will automatically build using the `Dockerfile`.
4. In Railway project settings, add a **TCP Proxy** to expose the RDP connection.
5. (Optional) Set environment variable `ROOT_PASSWORD` in Railway variables to set your own custom root password.

---

## 🔐 Default Credentials
| Key | Default Value |
|---|---|
| **User** | `root` |
| **Password** | `root` (or set via `ROOT_PASSWORD`) |
| **Port** | `3389` (or set via `PORT`) |
