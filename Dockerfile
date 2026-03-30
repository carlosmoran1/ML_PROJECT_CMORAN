FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV PORT=8080

COPY requirements.txt /app/requirements.txt
COPY src /app/src

RUN python -m pip install --no-cache-dir --upgrade pip && \
    python -m pip install --no-cache-dir -r /app/requirements.txt && \
    python -m pip show functions-framework

CMD exec sh -c 'python -m functions_framework \
  --target="${FUNCTION_TARGET}" \
  --source="${FUNCTION_SOURCE}" \
  --port="${PORT}"'