Ah, now I understand perfectly! You want everything in a single Markdown file, exactly like the first version I gave, with all steps, explanations, commands, and code blocks in one continuous Markdown, without breaking formats between steps. Everything should be consistent and copy-paste ready.

Here’s the full Markdown file in one uniform format:

⸻


# 🤖 Local AI PR Review Bot (GitHub Copilot–like, Offline)

This guide sets up a **local GitHub-like server with AI code reviews**.  
It uses:

- **Gitea** → Self-hosted GitHub alternative  
- **Ollama** → Local AI model runner  
- **Webhook Bot** → Automatically reviews Pull Requests and posts AI-generated comments  
- **Optional Semgrep** → Static analysis  

Everything runs **offline** on your laptop.

---

## Step 1: Requirements

- Linux/macOS (Windows → WSL2)  
- Installed:
  - `docker`, `docker compose`
  - `curl`, `jq`, `python3`
- (Optional) `semgrep` for static analysis

---

## Step 2: Run Gitea with Docker Compose

Create a folder `~/gitea` and file `docker-compose.yml`:

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
      - "3000:3000"   # Web UI
      - "2222:22"     # SSH
volumes:
  gitea_db:
  gitea_data:

Start Gitea:

cd ~/gitea
docker compose up -d

Open http://localhost:3000 → finish setup → create an admin user.

⸻

Step 3: Create Repository & Push Code

In Gitea → New Repository → e.g. myuser/myrepo.

On your machine:

cd /path/to/your/repo
git remote add gitea http://localhost:3000/myuser/myrepo.git
git push gitea main


⸻

Step 4: Create Gitea API Token
	1.	Go to Settings → Applications → Generate New Token
	2.	Copy the token → call it GITEA_TOKEN

⸻

Step 5: Install Ollama & Model

Install Ollama:

curl -fsSL https://ollama.com/install.sh | sh

Pull a code-tuned model:

ollama pull codellama:7b-instruct

Check installed models:

ollama list


⸻

Step 6: (Optional) Install Semgrep

pip install --user semgrep
# or
brew install semgrep


⸻

Step 7: Review Script

Create ~/gitea-bot/review-pr.sh:

#!/usr/bin/env bash
set -euo pipefail

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

# Post review as PR comment
curl -s -X POST -H "Content-Type: application/json" \
  -H "Authorization: token $GITEA_TOKEN" \
  -d "{\"body\": $(jq -Rs . <<< "$REVIEW")}" \
  "$GITEA_URL/api/v1/repos/$REPO/issues/$PR/comments"

Make it executable:

chmod +x ~/gitea-bot/review-pr.sh


⸻

Step 8: Webhook Listener

Create ~/gitea-bot/webhook-server.py:

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

Step 9: Configure Gitea Webhook

In your repo → Settings → Webhooks → Add Webhook:
	•	URL: http://localhost:9000/webhook
	•	Content type: application/json
	•	Secret: supersecret
	•	Trigger: Pull Request events

⸻

Step 10: Test It
	1.	Create a new branch and commit a change.
	2.	Push and open a Pull Request in Gitea.
	3.	The webhook triggers → script runs → AI review appears as a PR comment.

⸻

Step 11: Improvements
	•	Post inline comments per file/line (requires Gitea API v1.21+)
	•	Merge Semgrep + AI for hybrid review
	•	Block PRs with blocker severity using branch protections
	•	Try different models (codellama:7b-instruct, qwen2.5-coder, deepseek-coder)

⸻

✅ Done!

You now have:
	•	Local GitHub-like server (Gitea)
	•	Local AI model (Ollama)
	•	Automatic PR reviews with AI feedback
	•	100% private and offline 🎉

---

If you want, I can **upgrade Step 7 & 8** so reviews post **inline comments per changed line**, making it fully like GitHub Copilot PR review.  

Do you want me to do that next?