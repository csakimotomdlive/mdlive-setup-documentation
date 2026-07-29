# MD Live — Local Setup Documentation

Guides for running MD Live applications in **`mdlive-dev-environment`** (Docker Compose + Make targets). These docs cover first-time setup, demo credentials, console recipes, feature flags, and troubleshooting — not application source code.

All commands assume you are in the **`mdlive-dev-environment`** repository root unless noted otherwise.

---

## Prerequisites

MD Live local dev requires **Docker Compose** and **Make**. Pick your platform below, then clone [mdlive-dev-environment](https://github.com/BreakthroughBehavioralInc/mdlive-dev-environment), copy `.env.template` to `.env`, set `GITHUB_PERSONAL_ACCESS_TOKEN`, and run `make clone-all` if you have not cloned the app repos yet. Continue with [Initial launch](#initial-launch) below.

### macOS — Colima

On macOS, many developers use **[Colima](https://github.com/abiosoft/colima)** instead of Docker Desktop to run Docker Compose for `mdlive-dev-environment`.

Install and start:

```bash
brew install colima docker docker-compose
colima start --cpu 4 --memory 8
```

Verify Docker is working:

```bash
docker compose version
docker ps
```

**Notes:**

- **Docker Desktop** also works if your team uses it. Do not run Colima and Docker Desktop at the same time — stop one before starting the other.
- If `docker` cannot connect, run `colima status` and `colima start` again.

### Windows — WSL2 + Docker Desktop

On Windows, run the stack inside **WSL2** (Ubuntu). Native PowerShell/CMD is not supported for the `make` workflow in these docs.

1. **Enable WSL2** (PowerShell as Administrator):

   ```powershell
   wsl --install
   ```

   Restart if prompted, then open **Ubuntu** from the Start menu and finish Linux user setup.

2. **Install [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/)**
   - Settings → **General** → enable **Use the WSL 2 based engine**
   - Settings → **Resources → WSL Integration** → enable your Ubuntu distro

3. **In the Ubuntu (WSL) terminal**, install tools and verify Docker:

   ```bash
   sudo apt update && sudo apt install -y make git
   docker compose version
   docker ps
   ```

   Clone repos inside your WSL home directory (e.g. `~/GitHub/`), not under `/mnt/c/`, for better file performance.

**Notes:**

- Run all `make` commands from **WSL**, not PowerShell.
- Connect to the company **VPN** before cloning private GitHub repos or running `bundle install`.

### All platforms

- Patient Portal and Grafana both bind host port **3000** — see [PATIENT_PORTAL_SETUP.md — Troubleshooting](./PATIENT_PORTAL_SETUP.md#troubleshooting).

---

## Initial launch

First time on a fresh machine or empty database:

```bash
make stern-init                    # telehealth DB + demo patients/providers
make stern
make stern-elasticsearch-index     # first time only — provider search
```

Then follow the guide for the app you are working on (below). Patient Portal also needs Affiliation Manager init and Survey Monkey activation — see [PATIENT_PORTAL_SETUP.md](./PATIENT_PORTAL_SETUP.md).

| Command | Port | Service |
|---------|------|---------|
| `make stern` | 3001 | Stern (SSO, API, SystemSettings) |
| `make pap` | 3000 | Patient Portal |
| `make prp` | 3004 | Provider Portal |
| `make afm` | 3008 | Affiliation Manager |

---

## Demo credentials

| Account | Username | Password |
|---------|----------|----------|
| Demo patient | `demopatient1` … `demopatient25` | `Mdlive123!` |
| Demo provider | `demoprovider1` … `demoprovider25` | `Mdlive123!` |
| Affiliation Manager admin | `admin@mdlive.com` | `Mdlive123!` |

**Login entry points:**

- **Patient Portal** — http://localhost:3001/landing/surveymonkey/login (not `localhost:3000` directly)
- **Provider Portal** — http://localhost:3004/login

Seeded patients start on affiliation **96** (DTC). Survey Monkey login requires affiliation **185** — see [STERN_SETUP.md](./STERN_SETUP.md#move-demo-users-to-survey-monkey-patient-portal).

---

## Documentation index

### [STERN_SETUP.md](./STERN_SETUP.md)

Central guide for **Stern** — the core Rails API and owner of the `telehealth_development` database.

- `make stern-init`, `make stern`, `make stern-console`, Elasticsearch indexing
- **SystemSettings** — view/change feature flags and URLs in `make stern-console`
- Move demo users to Survey Monkey (96 → 185)
- Hosted PCI env vars (payment step)
- Stern console recipes for appointments, credits, cache clear
- Troubleshooting (SSO, health checks, provider search)

Start here when you need SSO, API behavior, or any `SystemSetting` (e.g. `rx_mgmt_enabled`, `formulary_enabled`, `patient_portal_url`).

---

### [PATIENT_PORTAL_SETUP.md](./PATIENT_PORTAL_SETUP.md)

Run and log into **Patient Portal** (`make pap`, port **3000**).

- Quick start with Stern, Affiliation Manager, Elasticsearch
- **Survey Monkey activation** (required for login) — UI or console
- Create extra test patients
- **Hosted PCI** — `mdlive-dev-environment/.env`, recreate Stern container
- Yarn / Sprockets asset precompile (first-load timeout)
- Troubleshooting (Grafana port conflict, landing pages, redirects, payment 500s)

---

### [PROVIDER_PORTAL_SETUP.md](./PROVIDER_PORTAL_SETUP.md)

Run and log into **Provider Portal** (`make prp`, port **3004**).

- Direct login at `/login` (SSO still via Stern)
- Demo provider types and which to use for each visit type
- **Go on call** — urgent care waiting room
- **Enable Rx Management** (`rx_mgmt_enabled` or per-provider pilot flag)
- Create extra test providers
- Architecture (shared DB, Stern SSO URLs)
- Troubleshooting (invalid credentials, DB host, on-call empty queue)

---

### [SCHEDULING_APPOINTMENTS.md](./SCHEDULING_APPOINTMENTS.md)

Book visits as a demo patient after Patient Portal login.

- SAV wizard flow (scheduled vs on-call urgent care)
- Recommended first test (Therapy — no provider on call)
- Step-by-step UI booking
- **Stern console** — past/completed appointments, free service credits
- Hosted PCI and payment-step troubleshooting
- End-to-end with Provider Portal (accept + complete visit)

**Prerequisite:** [PATIENT_PORTAL_SETUP.md](./PATIENT_PORTAL_SETUP.md)

---

### [create_appointment_with_soap.md](./create_appointment_with_soap.md)

Stern script (`CreateAppointmentWithSoap`) to seed video appointments with SOAP notes for **Provider Portal** testing.

- `--patient-id` required; optional `--provider-id`, `--chief-complaint`, `--icd10`
- Default: completed visit with signed SOAP; `--open-soap` for in-progress / unsigned
- Runnable via `rails runner` or Stern console (`CreateAppointmentWithSoap.run(...)`)

**Prerequisites:** Stern running (`make stern`). Often used with [PROVIDER_PORTAL_SETUP.md](./PROVIDER_PORTAL_SETUP.md).

---

### [surescripts-formulary.md](./surescripts-formulary.md)

**Provider Portal** Surescripts **formulary** — coverage checks and alternatives for prescribed medications.

- Feature gate: `formulary_enabled` SystemSetting
- Surescripts env vars (eligibility 271 + formulary RFS-PMBC, certs)
- Eligibility prerequisite (`hets_transactions`, 72-hour window)
- Manual console steps and pre-flight checklist
- Staging test values and related code pointers

**Prerequisites:** Provider Portal running, Stern healthy. Often used with [PROVIDER_PORTAL_SETUP.md](./PROVIDER_PORTAL_SETUP.md) and [STERN_SETUP.md](./STERN_SETUP.md#systemsettings).

---

## Suggested workflows

### Patient only (login + browse)

```
make stern-init (first time) → make stern → PATIENT_PORTAL_SETUP (Survey Monkey) → make pap
```

### Book a scheduled visit

```
PATIENT_PORTAL_SETUP → SCHEDULING_APPOINTMENTS (Therapy or other scheduled service)
```

### On-call urgent care (patient + provider)

```
PATIENT_PORTAL_SETUP → PROVIDER_PORTAL_SETUP (on call) → SCHEDULING_APPOINTMENTS (on-call flow)
```

### Provider Rx / formulary work

```
PROVIDER_PORTAL_SETUP (rx_mgmt_enabled) → surescripts-formulary
```

### Toggle a feature flag or fix redirect URLs

```
STERN_SETUP → SystemSettings section → make stern-console
```

---

## Related repositories

| Repo | Role |
|------|------|
| [mdlive-dev-environment](https://github.com/BreakthroughBehavioralInc/mdlive-dev-environment) | Docker Compose, Make targets, `.env` |
| [Stern](https://github.com/BreakthroughBehavioralInc/Stern) | Core API, SSO, SystemSettings |
| [Patient-Portal](https://github.com/BreakthroughBehavioralInc/Patient-Portal) | Patient UI |
| [Provider-Portal](https://github.com/BreakthroughBehavioralInc/Provider-Portal) | Provider UI |
| [affiliation_manager](https://github.com/BreakthroughBehavioralInc/affiliation_manager) | Affiliation / landing branding |
