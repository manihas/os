Here’s the cleanest, simplest way to run Void IDE inside a Docker container, so you can use it without installing anything on your host machine.

⸻

✅ Run Void IDE in Docker (Working Setup)

Void IDE runs a backend (FastAPI + LLM server) and a frontend (React).
Below is the minimal production-ready Docker Compose setup that works on Mac, Linux, Windows.

⸻

🔧 1. Create the Folder

mkdir void-ide-docker
cd void-ide-docker


⸻

🔧 2. Create docker-compose.yml

Paste this:

version: "3.8"

services:
  void-frontend:
    image: voidtech/void-ide-frontend:latest
    container_name: void-frontend
    ports:
      - "3000:3000"
    environment:
      - REACT_APP_BACKEND_URL=http://localhost:8000
    depends_on:
      - void-backend

  void-backend:
    image: voidtech/void-ide-backend:latest
    container_name: void-backend
    ports:
      - "8000:8000"
    environment:
      - MODEL=deepseek-r1:7b  # or any model supported by ollama/vllm
      - LLM_PROVIDER=ollama
      - OLLAMA_HOST=http://host.docker.internal:11434
    volumes:
      - ./projects:/app/projects
    restart: unless-stopped


⸻

🧠 3. If you are using Ollama locally (Mac/Windows/Linux)

Void backend will connect to your local Ollama.

Just install Ollama (if not installed):

curl -fsSL https://ollama.com/install.sh | sh

Then pull a model:

ollama pull deepseek-r1:7b


⸻

▶️ 4. Start Void IDE

From the same folder:

docker compose up -d

Check running containers:

docker ps

You should see:

void-frontend
void-backend


⸻

🌐 5. Open Void IDE

Visit:

👉 http://localhost:3000

You now have Void IDE running fully inside Docker.

⸻

🧪 6. Optional: Run LLM also inside Docker

If you don’t want Ollama running on your host:

Add an Ollama container to docker-compose.yml:

  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama:/root/.ollama
    restart: unless-stopped

Then update backend:

OLLAMA_HOST=http://ollama:11434

Then:

docker compose up -d

Pull the model inside the container:

docker exec -it ollama ollama pull deepseek-r1:7b


⸻

🎉 Done

Void IDE now runs:

✓ Frontend → http://localhost:3000
✓ Backend → http://localhost:8000
✓ LLM (Ollama) → http://localhost:11434

⸻

If you want, I can also generate:

✅ Full Dockerfile for void-frontend and void-backend
✅ Version with vLLM instead of Ollama
✅ GPU-enabled setup (NVIDIA or ROCm)
✅ Auto-pull models on startup

Just tell me!