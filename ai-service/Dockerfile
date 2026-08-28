FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-ara \
    poppler-utils \
    libpango-1.0-0 \
    libpangoft2-1.0-0 \
    fonts-noto-core \
    swi-prolog-core \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

ARG INSTALL_CUDA=0
RUN if [ "$INSTALL_CUDA" = "1" ]; then \
        pip install --no-cache-dir nvidia-cublas-cu12 nvidia-cudnn-cu12; \
    fi

COPY ai-service/ ./

EXPOSE 8001

CMD ["uvicorn", "chatbot.main:app", "--host", "0.0.0.0", "--port", "8001"]
