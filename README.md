# codex-5-high

This repository provides a minimal starting point for building a Next.js application with
an embedded drag‑and‑drop editor and Windows/WSL2 deployment scripts.  It includes the
bare essentials needed to extend the project with your own components and logic.

## Overview

* **Next.js skeleton:** A simple app router structure with a dashboard page and an
  `/edit` route that hosts the Puck editor.  The dashboard renders data stored
  by the editor.
* **Puck configuration:** Basic block definitions and a storage adapter for saving
  content to JSON files.  You can add your own components here.
* **WSL2 installer script:** A PowerShell script that provisions Dokploy inside a WSL2
  environment on Windows Server 2022.  It configures Docker, sets up Swarm or
  Compose and exposes ports to the host.
* **Documentation:** A guide explaining how the Windows+WSL2 setup works and how to
  customise it for your environment.

## Getting started

```bash
pnpm install       # or yarn/npm
pnpm dev          # start the Next.js development server
```

Open `http://localhost:3000/dashboard` to view the dashboard and
`http://localhost:3000/edit/dashboard` to edit its content.  The Puck editor
saves JSON files under `data/puck` by default; set the `PUCK_DATA_DIR` environment
variable to customise the storage location.
