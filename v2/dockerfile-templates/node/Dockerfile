FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
ENV PORT=3000
ENV HOST=0.0.0.0
EXPOSE 3000
CMD ["sh", "/app/deployforge-entrypoint.sh"]
