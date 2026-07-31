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
#   libpango-1.0-0 + libpangoft2-1.0-0 — WeasyPrint's text-shaping backend
#     (virtual_doctor/pdf_worker.py, consultation PDF reports). WeasyPrint
#     (v53+) no longer needs cairo/gdk-pixbuf — it renders PDFs itself via
#     pydyf — but still links Pango/HarfBuzz/fontconfig/freetype through cffi
#     for correct (including RTL/Arabic) text layout. apt pulls in glib,
#     harfbuzz, fontconfig and freetype transitively, so nothing else is
#     listed explicitly. Unlike the native Windows dev setup (see
#     pdf_worker.py's pin_native_stack()), a single apt install here can't
#     produce the mixed-runtime split that caused heap corruption there —
#     pin_native_stack() is a no-op on Linux for exactly that reason.
#   fonts-noto-core — includes Noto Naskh Arabic; fallback so Pango can still
#     shape Arabic text if report_generator.py's embedded Cairo font is ever
#     unavailable. Debian has no standalone "fonts-noto-naskh-arabic" package;
#     the Arabic weights ship inside this core metapackage.
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-ara \
    poppler-utils \
    libpango-1.0-0 \
    libpangoft2-1.0-0 \
    fonts-noto-core \
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
