Got it ✅
I’ll format the entire step-by-step guide as a Markdown document, so you can drop it straight into a GitHub README or wiki. Everything is copy-paste ready.

⸻


# 🚀 Local AI PR Review Bot (Gitea + Ollama)

This guide shows you how to build a **GitHub Copilot–like PR review bot** that runs **100% locally**:

- 🗂️ **Gitea** = local GitHub-like server  
- 🤖 **Ollama** = local AI model runner (no cloud required)  
- 🔍 **Optional**: Semgrep for static analysis  
- 📝 **Webhook + script** = automatically review PRs and post comments

---

## 1. Requirements

- Linux/macOS (Windows → use WSL2)
- Docker + `docker compose`
- `curl`, `jq`, `python3`
- Optional: `semgrep`

---

## 2. Run Gitea with Docker Compose

Create a folder and `docker-compose.yml`:

```yaml
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
      - "2222:22"     # ssh
volumes:
  gitea_db:
  gitea_data:

Run it:

mkdir ~/gitea && cd ~/gitea
docker compose up -d

Open http://localhost:3000 → complete setup → create an admin user.

⸻

3. Create a Repo & Push Local Code

In Gitea UI → New Repository → e.g. myuser/myrepo.

On your machine:

cd /path/to/your/repo
git remote add gitea http://localhost:3000/myuser/myrepo.git
git push gitea main


⸻

4. Create a Gitea API Token
	•	Go to Settings → Applications → Generate New Token
	•	Copy the token → we’ll call it GITEA_TOKEN

⸻

5. Install Ollama + Model

Install Ollama:

curl -fsSL https://ollama.com/install.sh | sh

Pull a code-tuned model:

ollama pull codellama:7b-instruct

Check available models:

ollama list


⸻

6. (Optional) Install Semgrep

pip install --user semgrep
# or
brew install semgrep


⸻

7. Review Script

Save as ~/gitea-bot/review-pr.sh:

#!/usr/bin/env bash
set -euo pipefail

# Usage: ./review-pr.sh <owner/repo> <pr_number>
# Requires:
#   GITEA_URL   (default: http://localhost:3000)
#   GITEA_TOKEN
#   MODEL       (default: codellama:7b-instruct)

REPO="$1"
PR="$2"
GITEA_URL="${GITEA_URL:-http://localhost:3000}"
MODEL="${MODEL:-codellama:7b-instruct}"
TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

FILES_JSON="$TMPDIR/files.json"
curl -s -H "Authorization: token $GITEA_TOKEN" \
  "$GITEA_URL/api/v1/repos/$REPO/pulls/$PR/files" > "$FILES_JSON"

jq -r '.[].patch // empty' "$FILES_JSON" > "$TMPDIR/diff.txt"
DIFF=$(cat "$TMPDIR/diff.txt")

PROMPT=$(cat <<'EOF'
You are a strict senior code reviewer. Review the diff below and output GitHub-style comments.

Format each finding:
- FILE: <file> L<line>
  - Type: [Bug|Security|Style|Perf|Docs|Test]
  - Severity: [blocker|major|minor]
  - Summary: <one-line>
  - Suggestion:
    ```suggestion
    <minimal fix>
    ```

If no issues: "No issues".
EOF
)

REVIEW=$(printf "%s\n\n--- DIFF START ---\n%s\n--- DIFF END ---\n" "$PROMPT" "$DIFF" | ollama run "$MODEL")

echo "$REVIEW"

# Post review as a PR comment
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: token $GITEA_TOKEN" \
  -d "{\"body\": $(jq -Rs . <<< "$REVIEW")}" \
  "$GITEA_URL/api/v1/repos/$REPO/issues/$PR/comments"

Make it executable:

chmod +x ~/gitea-bot/review-pr.sh


⸻

8. Webhook Listener

Save as ~/gitea-bot/webhook-server.py:

from flask import Flask, request, abort
import subprocess, os, hmac, hashlib

app = Flask(__name__)
SECRET = os.environ.get("GITEA_WEBHOOK_SECRET", "")
BOT_SCRIPT = os.environ.get("BOT_SCRIPT", "/home/youruser/gitea-bot/review-pr.sh")

def verify(req):
    if not SECRET:
        return True
    sig = req.headers.get("X-Gitea-Signature")
    if not sig: return False
    computed = hmac.new(SECRET.encode(), req.get_data(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(computed, sig)

@app.route("/webhook", methods=["POST"])
def webhook():
    if not verify(request):
        abort(403)
    payload = request.get_json(force=True)
    if payload.get("pull_request"):
        repo = payload["repository"]["full_name"]
        pr = payload["pull_request"]["number"]
        subprocess.Popen([BOT_SCRIPT, repo, str(pr)], env=os.environ)
    return "OK", 202

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9000)

Install Flask & run:

pip install flask
export GITEA_TOKEN="your_token"
export BOT_SCRIPT=~/gitea-bot/review-pr.sh
export GITEA_WEBHOOK_SECRET="supersecret"
python3 ~/gitea-bot/webhook-server.py


⸻

9. Configure Gitea Webhook

Repo → Settings → Webhooks → Add Webhook:
	•	URL: http://localhost:9000/webhook
	•	Content type: JSON
	•	Secret: supersecret
	•	Trigger: Pull Request events

⸻

10. Test It
	1.	Create a branch → commit a change → push.
	2.	Open a PR in Gitea.
	3.	Webhook triggers → script runs → AI review appears as a PR comment.

⸻

11. Improvements
	•	Per-line inline comments (requires Gitea API v1.21+)
	•	Combine Semgrep + AI (RUN_SEMGREP=1 ./review-pr.sh)
	•	Block merges on blocker severity via branch protections
	•	Use smaller models (codellama:7b-instruct is a good balance)

⸻

✅ Summary

You now have:
	•	Local GitHub-like repo hosting (Gitea)
	•	Local AI model (Ollama) reviewing PRs
	•	Auto-posted review comments in pull requests

All offline, private, and customizable 🎉

---

Would you like me to **add inline comment support** in that Markdown doc (so reviews appear directly on changed lines, not just as a single PR comment)?