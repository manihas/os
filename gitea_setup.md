Great — I’ll walk you step‑by‑step from Step 1 to a working local PR review bot that:
	•	runs on your laptop (no cloud),
	•	uses a local LLM (via Ollama) to generate review comments,
	•	is triggered by Gitea webhooks when a Pull Request is opened/updated,
	•	posts the review back to the PR (as a PR comment).

I’ll give runnable docker-compose, Bash and Python code, and exact commands. I’ll also point out optional improvements (Semgrep, inline comments) and version caveats.

⸻

1) tools & assumptions (quick)
	•	OS: Linux or macOS (Windows: use WSL2 and follow Ubuntu steps).
	•	Docker & docker compose installed.
	•	curl, jq, python3 available.
	•	We’ll run Gitea with Docker Compose (easy), Ollama locally for the LLM, and a tiny Flask webhook listener to trigger the review script.

Key docs I used while writing this: Gitea Docker install & webhooks docs, Ollama install docs, Semgrep quickstart, and Gitea API notes.  ￼ ￼ ￼

⸻

2) Start Gitea (fast — Docker Compose)

Create a folder and a docker-compose.yml:

version: "3.8"
services:
  db:
    image: postgres:15
    restart: always
    environment:
      POSTGRES_USER: gitea
      POSTGRES_PASSWORD: gitea_pw
      POSTGRES_DB: gitea
    volumes:
      - gitea_db:/var/lib/postgresql/data

  gitea:
    image: gitea/gitea:latest
    depends_on:
      - db
    restart: always
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - DB_TYPE=postgres
      - DB_HOST=db:5432
      - DB_NAME=gitea
      - DB_USER=gitea
      - DB_PASSWD=gitea_pw
    volumes:
      - gitea_data:/data
    ports:
      - "3000:3000"   # web UI
      - "2222:22"     # (ssh)
volumes:
  gitea_db:
  gitea_data:

Start it:

mkdir ~/gitea && cd ~/gitea
# save docker-compose.yml
docker compose up -d

Open http://localhost:3000 and follow the web setup wizard (create an admin user). Docker Compose approach recommended in Gitea docs.  ￼

⸻

3) Create a repo & push your local code

In the Gitea UI: create a new repository (e.g. myuser/myrepo).

Locally, add Gitea as a remote and push:

cd /path/to/your/local/repo
git remote add gitea http://<your_gitea_host>:3000/myuser/myrepo.git
git push gitea main

(Use ssh if you prefer; Gitea exposes SSH on port 2222 in the compose above.)

⸻

4) Create a Gitea API token for the bot

You will need a personal access token for the bot to post comments.

Option A (web UI):
	•	Login to the account you will use for the bot → Settings → Applications → Generate New Token. Copy the token.

Option B (API):
	•	Gitea supports creating tokens via API POST /api/v1/users/:username/tokens if you prefer automation.  ￼

Save token in a safe place (we’ll reference it as GITEA_TOKEN).

⸻

5) Install Ollama (local LLM runtime)

Install Ollama (runs LLMs locally). One‑line installer:

curl -fsSL https://ollama.com/install.sh | sh

Then pull a code‑tuned model (pick one that fits your RAM). Example:

# example: code‑model (if available on your Ollama install)
ollama pull codellama:7b-instruct
# or smaller: ollama pull codeup:7b  (check ollama list/library for models)

Notes: ollama run <model> "prompt..." or pipe a prompt into ollama run <model> — both are supported. Ollama docs & quickstart here.  ￼ ￼

⸻

6) (Optional but recommended) Install Semgrep for deterministic security checks

# linux / mac
python3 -m pip install --user semgrep
# or with brew
brew install semgrep

Semgrep helps catch security issues and you can feed its findings into the LLM for better results.  ￼

⸻

7) Create the review script (the heart)

Create a directory for the bot and the script:

mkdir -p ~/gitea-bot && cd ~/gitea-bot

Save review-pr.sh (chmod +x):

#!/usr/bin/env bash
set -euo pipefail

# Usage: ./review-pr.sh <owner/repo> <pr_number>
# Env vars:
#   GITEA_URL (e.g. http://localhost:3000)
#   GITEA_TOKEN
#   MODEL (e.g. codellama:7b-instruct)
# Optional:
#   RUN_SEMGREP=1   # set to run semgrep and include findings

REPO="$1"   # owner/repo
PR="$2"     # pr number
GITEA_URL="${GITEA_URL:-http://localhost:3000}"
MODEL="${MODEL:-codellama:7b-instruct}"
TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

# 1) fetch changed files (patches)
echo "Fetching PR files from $GITEA_URL/api/v1/repos/$REPO/pulls/$PR/files ..."
FILES_JSON="$TMPDIR/files.json"
curl -s -H "Authorization: token $GITEA_TOKEN" \
  "$GITEA_URL/api/v1/repos/$REPO/pulls/$PR/files" > "$FILES_JSON"

if [ "$(jq -r 'length' "$FILES_JSON")" = "0" ]; then
  echo "No files found or empty response."
fi

# combine patches (truncate if huge)
DIFF="$TMPDIR/diff.txt"
jq -r '.[].patch // empty' "$FILES_JSON" | sed 's/\r$//' > "$DIFF"
# safe truncation: keep first 120000 chars
MAX=120000
if [ "$(wc -c < "$DIFF")" -gt $MAX ]; then
  head -c $MAX "$DIFF" > "$DIFF.trunc"
  echo -e "\n\n[diff truncated]\n" >> "$DIFF.trunc"
  mv "$DIFF.trunc" "$DIFF"
fi

# 2) (optional) run semgrep and capture top findings
SEMGREP_SUMMARY=""
if [ "${RUN_SEMGREP:-0}" = "1" ] && command -v semgrep >/dev/null 2>&1; then
  echo "Running semgrep scan..."
  semgrep --config=p/ci --json --quiet > "$TMPDIR/semgrep.json" || true
  # Summarize semgrep (simple)
  SEMGREP_SUMMARY="$(jq -r '.results[] | "[" + .check_id + "] " + (.extra.message // "")' "$TMPDIR/semgrep.json" | sed 's/^/- /' | head -n 20 | sed ':a;N;$!ba;s/\n/\\n/g')"
fi

# 3) build prompt
PROMPT=$(cat <<'EOF'
You are a strict senior code reviewer. Review the diff below (unified patch format).
Output **concise GitHub-style comments**. For each issue output:

- FILE: <relative/path> L<line>
  - Type: [Bug|Security|Style|Perf|Docs|Test]
  - Severity: [blocker|major|minor]
  - Summary: one-line
  - Suggestion:
    ```suggestion
    <small code snippet or minimal patch>
    ```

If there are no issues, output: "No issues".

Be specific and reference file paths and line numbers from the diff. Limit to 20 findings.

EOF
)

if [ -s "$DIFF" ]; then
  PROMPT="$PROMPT

--- SEMGREP FINDINGS (if any) ---
$SEMGREP_SUMMARY

--- DIFF START ---
$(sed 's/```/` ` `/g' "$DIFF")
--- DIFF END ---
"
else
  PROMPT="$PROMPT

(No diff available)
"
fi

# 4) call local LLM (Ollama)
echo "Asking local LLM ($MODEL) to review..."
LLM_OUT_FILE="$TMPDIR/review.txt"
# pipe prompt into ollama run
printf "%s\n" "$PROMPT" | ollama run "$MODEL" > "$LLM_OUT_FILE" 2>/dev/null || {
  echo "Ollama call failed (see output)."
  cat "$LLM_OUT_FILE" || true
  exit 1
}

# 5) Post a single summary comment to the PR (issue comments endpoint)
BODY="$(jq -Rs . < "$LLM_OUT_FILE")"

echo "Posting review summary to PR $PR ..."
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: token $GITEA_TOKEN" \
  -d "{\"body\": $BODY}" \
  "$GITEA_URL/api/v1/repos/$REPO/issues/$PR/comments" > "$TMPDIR/post.json"

echo "Done. Posted comment. Response:"
jq -r '.message // "OK"' "$TMPDIR/post.json" || cat "$TMPDIR/post.json"

Notes on the script
	•	It posts the LLM output as a single PR comment (works reliably across Gitea versions). The endpoint used is POST /api/v1/repos/:owner/:repo/issues/:index/comments. (PRs are represented as issues in Gitea.)  ￼ ￼
	•	If you want per-line inline review comments, Gitea newer API does support review endpoints (/pulls/:index/reviews/...) in recent versions — that’s possible but slightly more complex and version-dependent. I can give an add‑on later if you want inline comments. (Check your Gitea version’s API docs.)  ￼

⸻

8) Webhook receiver — trigger the script on PR open/update

Create a small Flask app to receive Gitea webhooks and call review-pr.sh.

Save webhook-server.py:

#!/usr/bin/env python3
# webhook-server.py
from flask import Flask, request, abort
import subprocess, os, hmac, hashlib, json

app = Flask(__name__)
GITEA_SECRET = os.environ.get("GITEA_WEBHOOK_SECRET","")  # set if you configured secret in Gitea
BOT_SCRIPT = os.environ.get("BOT_SCRIPT","/home/youruser/gitea-bot/review-pr.sh")

def verify_sig(req):
    if not GITEA_SECRET:
        return True
    # Gitea may send X-Hub-Signature-256 (sha256=...) or X-Gitea-Signature (hex)
    sig256 = req.headers.get("X-Hub-Signature-256") or req.headers.get("X-Gitea-Signature")
    if not sig256:
        return False
    # unify format
    if sig256.startswith("sha256="):
        sig = sig256.split("=",1)[1]
    else:
        sig = sig256
    computed = hmac.new(GITEA_SECRET.encode(), req.get_data(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(computed, sig)

@app.route("/webhook", methods=["POST"])
def webhook():
    if not verify_sig(request):
        abort(403)
    event = request.headers.get("X-Gitea-Event") or request.headers.get("X-GitHub-Event") or ""
    payload = request.get_json(silent=True) or {}
    # We care about pull_request events (opened, synchronized/updated)
    if event.lower() == "pull_request" or payload.get("pull_request") or payload.get("action") in ["opened","synchronize","updated"]:
        # get repo full name and PR number
        repo = None
        if payload.get("repository") and payload["repository"].get("full_name"):
            repo = payload["repository"]["full_name"]
        # PR number: try 'number' or payload['pull_request']['number'] or 'index'
        prnum = payload.get("number") or (payload.get("pull_request") or {}).get("number") or (payload.get("pull_request") or {}).get("index")
        if repo and prnum:
            # run the script asynchronously (non-blocking)
            subprocess.Popen([BOT_SCRIPT, repo, str(prnum)], env=os.environ)
            return "OK", 202
    return "ignored", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9000)

Install dependencies and run:

python3 -m pip install --user flask
export BOT_SCRIPT=~/gitea-bot/review-pr.sh
export GITEA_TOKEN="your_token"
# optionally set webhook secret you will configure in Gitea
export GITEA_WEBHOOK_SECRET="choose_a_secret"
python3 webhook-server.py

Security note: keep GITEA_TOKEN and GITEA_WEBHOOK_SECRET in a protected systemd service environment or a secrets manager — do not commit them.

Gitea webhooks can be configured to send an authorization header and signature; the webhook server above validates the HMAC-SHA256 signature if you set a secret. See Gitea webhooks docs.  ￼ ￼

⸻

9) Add webhook in Gitea

In the repo → Settings → Webhooks → Add webhook:
	•	Type: Gitea (use JSON payload)
	•	Target URL: http://<your_machine_ip_or_localhost>:9000/webhook
	•	Content type: application/json
	•	Secret: set the same as GITEA_WEBHOOK_SECRET (optional but recommended)
	•	Trigger: select Pull Request events (Created/Updated)

Use “Test Delivery” to test. Gitea’s webhook docs show this flow.  ￼

⸻

10) Try it: create a PR
	1.	Create a branch locally, change a file, push to Gitea remote.
	2.	Open a PR in Gitea (UI).
	3.	Gitea sends the webhook → your webhook-server runs review-pr.sh → the bot posts a PR comment with the LLM review.

If something fails, check logs:
	•	docker compose logs gitea
	•	journalctl or the terminal running webhook-server.py
	•	~/gitea-bot output files (we left temporary files printed).

⸻

11) Improvements & tips
	•	Per-line inline comments: if your Gitea version supports the pull-review endpoints, you can parse the LLM output into individual create-review-comment API calls (/repos/{owner}/{repo}/pulls/{index}/reviews/{review_id}/comments or similar) — check your version’s API.  ￼
	•	Rate / noise control: detect duplicate bot comments and edit instead of creating many comments. Store comment IDs locally and PATCH them.
	•	Enforce blocking severity: the script can POST a status check or create a label to block merges if a “blocker” is present (requires Gitea actions or UI enforcement).
	•	Model selection: on laptops with limited RAM, prefer smaller code-tuned models (7B / q4 quantized). Ollama docs list memory guidance.  ￼
	•	Combine Semgrep + LLM: run Semgrep first, include top findings in the prompt so the LLM explains/triages them (the script already has a RUN_SEMGREP option).

⸻

12) Troubleshooting quick list
	•	ollama run fails: confirm model installed with ollama list and pick a model that fits your RAM.  ￼
	•	Webhook not delivered: check Gitea -> Webhooks -> Recent Deliveries for payload and HTTP response.  ￼
	•	Posting comment returns 4xx/5xx: ensure GITEA_TOKEN has repo/issue scopes and you’re posting to the right endpoint /api/v1/repos/:owner/:repo/issues/:index/comments.  ￼

⸻

Quick recap + next steps

You now have a full, local path:
	1.	Run Gitea (Docker).  ￼
	2.	Install Ollama and pull a model.  ￼ ￼
	3.	Add review-pr.sh + webhook server → have automated PR reviews posted as PR comments. (Script posts a single summary comment; inline comments are possible but more version-dependent.)  ￼ ￼

⸻

If you want, I can (pick one) and I’ll provide it right away:
	•	A ready-made docker-compose for the webhook server + Ollama (so you run everything with docker compose up), or
	•	An updated review-pr.sh that creates per-file inline review comments (I’ll include fallback logic if your Gitea version doesn’t support it), or
	•	A single systemd service unit / startup script to run the webhook server and keep ollama running in the background.

Which of those should I produce next? (I can just output the full files here so you can copy/paste.)