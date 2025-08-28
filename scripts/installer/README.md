Cloudflare Pages bootstrap template

This folder contains a small Cloudflare Pages template and a post-install installer script to help bootstrap new machines quickly.

Files:
- `index.html` — simple Cloudflare Pages page that exposes a public SSH key and one-line bootstrap instruction. Replace the placeholder content with your domain and key.
- `post_install.sh` — idempotent installer script that installs Docker, Helm, kubectl, adds a public SSH key to `authorized_keys`, clones this repo into `/opt/rag`, and runs `scripts/provision/init_proxmox_setup.sh` if present.

Usage:
1. Copy `index.html` to a Cloudflare Pages site. Use the folder structure below to serve both `index.html`, the public key file at `/keys/rag_deploy.pub`, and `post_install.sh` at the site root.

   Example Pages structure:
   - / (index.html)
   - /post_install.sh
   - /keys/rag_deploy.pub

2. Update `index.html` with your Pages domain and replace the placeholder public key text.
3. Upload `post_install.sh` (make it executable) and place your `rag_deploy.pub` public key in `/keys/`.
4. On a new machine run (as root):

   curl -fsSL https://<your-pages-domain>/post_install.sh | sudo PUBLIC_KEY_URL=https://<your-pages-domain>/keys/rag_deploy.pub bash -s --

Security notes:
- Only host public keys and non-sensitive bootstrap code on a public Pages site. Never publish private keys, secrets, or credentials.
- For private artifacts use Bitwarden, an S3 bucket with signed URLs, or your own secure artifact server.

Customization:
- Modify `post_install.sh` to add extra packages, users, or configuration steps. The script is intentionally minimal and idempotent.
