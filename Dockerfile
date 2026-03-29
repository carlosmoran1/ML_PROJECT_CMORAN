FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV PORT=8080

COPY src /app/src
COPY src/pipelines/etl_market_data/requirements.txt /app/requirements.txt

RUN python -m pip install --no-cache-dir --upgrade pip && \
    python -m pip install --no-cache-dir -r /app/requirements.txt && \
    python -m pip show functions-framework

CMD exec python -m functions_framework \
  --target=etl_commodities \
  --source=/app/src/pipelines/etl_market_data/main.py \
  --port=$PORT