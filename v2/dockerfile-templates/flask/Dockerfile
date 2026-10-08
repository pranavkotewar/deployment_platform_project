FROM python:3.12-slim
WORKDIR /app
COPY . /app
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi \
    && pip install --no-cache-dir gunicorn
EXPOSE 5000
CMD ["sh", "-c", "if [ -f app.py ]; then gunicorn -b 0.0.0.0:5000 app:app; else gunicorn -b 0.0.0.0:5000 main:app; fi"]

