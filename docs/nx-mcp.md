# Integrating the Nx MCP server (Model Context Protocol)

This document explains how to enable the Nx MCP server integration for AI assistants and local tooling, and provides lightweight checks and CI templates to make adoption reproducible for developers.

Why enable Nx MCP?
- Gives AI tooling and IDE integrations (Nx Console) a richer view of your workspace.
- Lets language servers and helper agents query project graph, tasks, and run commands more safely.

Quick summary (recommended path)
1. Install the *Nx Console* extension in your editor (VS Code or JetBrains plugin).
2. Install `nx` CLI locally when working with Nx projects (not required for this repo unless you add Nx).
3. If you decide to add Nx to the repository, the editor's Nx Console will automatically register the MCP server.

This repository is not currently an Nx workspace. The files below provide a safe, low-friction way to prepare and validate an environment so an operator can enable Nx MCP later.

Local preparation (developer)
- Install VS Code Nx Console: search for "Nx Console" in the Extensions view.
- Ensure you can run `npx nx --version` (optional, only necessary if you add Nx to the repo).
- Use the helper script `scripts/nx/check_nx_mcp.sh` to validate environment readiness.

CI integration
- We include a small GitHub Actions template `.github/workflows/nx-mcp-check.yml` that can be enabled to help CI validate the developer environment for Nx MCP.

When to actually run an MCP server
- The Nx MCP server is provided by Nx Console and is typically run by the editor/extension.
- If you later convert this repo to an Nx monorepo (adding `nx.json` and workspace config), the editor will expose the MCP server automatically.

Next steps if you want me to continue
- I can scaffold a minimal Nx workspace (`nx init`) and add `nx.json` and basic project entries so the MCP server becomes useful immediately. This will add dev dependencies and change the repo structure; tell me if you want that.

---
Files added by this integration:
- `scripts/nx/check_nx_mcp.sh` - local environment check for Nx and guidance
- `.github/workflows/nx-mcp-check.yml` - optional CI template to validate Nx MCP readiness



## Helper script

- `scripts/nx/init_nx.sh` - interactive helper that runs `npx nx init --preserve-existing-files`. Run this locally to convert the repo to a full Nx workspace; review changes and install node dependencies after running.
