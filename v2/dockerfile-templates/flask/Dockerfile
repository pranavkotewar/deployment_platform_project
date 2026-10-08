FROM python:3.12-slim
WORKDIR /app
COPY . /app
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi \
    && pip install --no-cache-dir gunicorn flask
ENV PORT=5000
EXPOSE 5000
CMD ["sh", "/app/deployforge-entrypoint.sh"]
