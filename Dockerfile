FROM node:20-alpine

WORKDIR /app
ENV NODE_ENV=production PORT=8080

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src
COPY scenario2/backend ./scenario2/backend
COPY scenario2/web ./scenario2/web

USER node
EXPOSE 8080
CMD ["node", "src/server.js"]
