FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

COPY src/autogluon_chronos_ii/requirements.txt /app/requirements.txt

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /app/requirements.txt

COPY src /app/src

CMD ["functions-framework", "--source=src/autogluon_chronos_ii/main.py", "--target=autogluon_predict", "--host=0.0.0.0", "--port=8080"]