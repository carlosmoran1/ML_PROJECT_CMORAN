FROM python:3.11-slim

WORKDIR /app

COPY src/pipelines/sarimax/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY src /app/src

ENV PYTHONPATH=/app

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "src.pipelines.sarimax.main:app"]