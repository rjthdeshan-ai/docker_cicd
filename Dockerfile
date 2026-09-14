FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir pytest

COPY app.py test_app.py ./

CMD ["pytest", "-v"]
