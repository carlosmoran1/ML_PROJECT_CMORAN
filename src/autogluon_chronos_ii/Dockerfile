FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV PORT=8080

ENV HF_HOME=/opt/hf-cache
ENV HUGGINGFACE_HUB_CACHE=/opt/hf-cache
ENV TRANSFORMERS_CACHE=/opt/hf-cache

COPY src/autogluon_chronos_ii/requirements.txt /app/requirements.txt
COPY src/common /app/src/common
COPY src/autogluon_chronos_ii /app/src/autogluon_chronos_ii

RUN mkdir -p /opt/hf-cache && \
    python -m pip install --no-cache-dir --upgrade pip && \
    python -m pip install --no-cache-dir -r /app/requirements.txt && \
    python -m pip show functions-framework

CMD ["sh", "-c", "python -m functions_framework --target=autogluon_predict --source=/app/src/autogluon_chronos_ii/main.py --port=${PORT}"]
