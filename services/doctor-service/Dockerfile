FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY src ./src
EXPOSE 3003
CMD ["sh", "-c", "node src/db/migrate.js && node src/index.js"]
