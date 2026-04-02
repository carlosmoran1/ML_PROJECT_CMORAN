FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PORT=8080 \
    HF_HOME=/opt/hf-cache \
    HUGGINGFACE_HUB_CACHE=/opt/hf-cache \
    TRANSFORMERS_CACHE=/opt/hf-cache

ARG HF_TOKEN

COPY src/autogluon_chronos_ii/requirements.txt /app/requirements.txt

RUN mkdir -p /opt/hf-cache && \
    pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /app/requirements.txt

COPY src/common /app/src/common
COPY src/autogluon_chronos_ii /app/src/autogluon_chronos_ii

CMD ["functions-framework", "--source=/app/src/autogluon_chronos_ii/main.py", "--target=autogluon_predict", "--signature-type=http", "--host=0.0.0.0", "--port=8080"]
