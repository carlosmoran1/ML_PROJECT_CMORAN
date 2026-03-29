FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080
ENV PYTHONPATH=/app

COPY src /app/src
COPY src/pipelines/etl_market_data/requirements.txt /app/requirements.txt

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /app/requirements.txt

CMD exec functions-framework \
  --target=etl_commodities \
  --source=/app/src/pipelines/etl_market_data/main.py \
  --port=$PORT