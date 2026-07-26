# MedOrbit ai-service — Python 3.12
#
# Pinned to 3.12, NOT 3.13+: asyncpg and pydantic (via pydantic-core) don't
# publish prebuilt wheels for 3.13+ at the versions pinned in requirements.txt,
# which would force a from-source build (and likely fail without a Rust
# toolchain for pydantic-core).
#
# Build context is the PROJECT ROOT (see docker-compose.yml's
# `build.context: .` for this service) because requirements.txt lives at the
# repo root, not inside ai-service/ — this Dockerfile's COPY paths assume that.
FROM python:3.12-slim

# System deps:
#   tesseract-ocr + tesseract-ocr-ara — OCR for scanned reports (pytesseract),
#     Arabic language pack required since summaries are bilingual.
#   poppler-utils — pdf2image's backend for rendering PDF pages to images
#     before OCR (used by chatbot/medical/document_extractor.py's OCR
#     fallback path; note pdf2image itself is not currently pinned in
#     requirements.txt — see DOCKER.md).
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-ara \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Whole ai-service/ subtree in one shot — .dockerignore (root-level; this
# build's context is the repo root) is the only thing that should ever decide
# what's excluded. Don't replace this with individual COPY lines for specific
# files/folders; a single odd file shouldn't be able to silently break
# unrelated parts of the build.
COPY ai-service/ ./

EXPOSE 8001

CMD ["uvicorn", "chatbot.main:app", "--host", "0.0.0.0", "--port", "8001"]
