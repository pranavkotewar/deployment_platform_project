FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir gunicorn flask
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY . /app
ENV PORT=5000
EXPOSE 5000
CMD ["sh", "/app/deployforge-entrypoint.sh"]
