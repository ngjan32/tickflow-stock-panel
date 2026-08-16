# README (backend)

This README is added to satisfy packaging tools that expect the project's readme to be inside the backend package directory.

For the full project README and usage instructions, see the repository root README.md.

Quick start (backend development)

1. Create `.env` from `.env.example` and edit as needed:

   cp .env.example .env

2. Install Python dependencies (recommended: use a venv):

   python -m venv .venv
   source .venv/bin/activate
   pip install -U pip
   pip install -r requirements.txt  # or use `uv sync` if you use uv

3. Run the backend locally (development):

   uv run --reload --app-path backend/app  # or follow project dev instructions

If you plan to build Docker images, the top-level README contains the Docker instructions.
