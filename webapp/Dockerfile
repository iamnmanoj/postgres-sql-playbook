FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
ARG HTTP_PROXY HTTPS_PROXY NO_PROXY
RUN npm ci --omit=dev --no-audit --no-fund
COPY server.js ./
COPY lib ./lib
COPY public ./public
ENV NODE_ENV=production PORT=3000 HOST=0.0.0.0 PLAYBOOK_DIR=/playbook \
    PGHOST=db PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=shopsphere
EXPOSE 3000
USER node
CMD ["node", "server.js"]
