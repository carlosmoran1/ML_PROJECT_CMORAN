FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080
ENV PYTHONPATH=/app

COPY src/sarimax/requirements.txt /app/requirements.txt

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /app/requirements.txt

COPY src/common /app/src/common
COPY src/sarimax /app/src/sarimax

CMD ["functions-framework", "--source=/app/src/sarimax/main.py", "--target=sarimax_predict", "--signature-type=http", "--host=0.0.0.0", "--port=8080"]
