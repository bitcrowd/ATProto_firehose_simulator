FROM node:20-bookworm-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY dataplane.js ./

ENV NODE_ENV=production
CMD ["node", "dataplane.js"]
