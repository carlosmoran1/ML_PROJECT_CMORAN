FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV PORT=8080

ENV HF_HOME=/opt/hf-cache
ENV HUGGINGFACE_HUB_CACHE=/opt/hf-cache
ENV TRANSFORMERS_CACHE=/opt/hf-cache

COPY requirements.txt /app/requirements.txt
COPY src /app/src

ARG HF_TOKEN

RUN mkdir -p /opt/hf-cache && \
    python -m pip install --no-cache-dir --upgrade pip && \
    python -m pip install --no-cache-dir -r /app/requirements.txt && \
    python -m pip show functions-framework && \
    test -n "$HF_TOKEN" && \
    HF_TOKEN="$HF_TOKEN" python -c "import os; from huggingface_hub import login; login(token=os.environ['HF_TOKEN'], add_to_git_credential=False); from chronos import Chronos2Pipeline; Chronos2Pipeline.from_pretrained('autogluon/chronos-2'); print('Chronos2 precacheado correctamente')"

CMD exec sh -c 'python -m functions_framework \
  --target="${FUNCTION_TARGET}" \
  --source="${FUNCTION_SOURCE}" \
  --port="${PORT}"'