# ─────────────────────────────────────────────
# Stage 1: Build Angular
# ─────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

# Copy dependency manifests first (layer cache optimization)
COPY package.json package-lock.json ./
RUN npm ci --prefer-offline

# Copy source and build
COPY . .
RUN npm run build -- --configuration production

# ─────────────────────────────────────────────
# Stage 2: Serve with Nginx + health endpoint
# ─────────────────────────────────────────────
FROM nginx:1.25-alpine

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom nginx config for container-level serving
COPY nginx-app.conf /etc/nginx/conf.d/app.conf

# Copy Angular build output
COPY --from=builder /app/dist/blue-green-app/browser /usr/share/nginx/html

# Create the /health endpoint as a static file served by nginx
# This is production-safe: no Node.js runtime needed in final image
RUN mkdir -p /usr/share/nginx/html/health && \
    echo '{"status":"OK","healthy":true}' > /usr/share/nginx/html/health/index.json

# Copy env.json placeholder (Jenkins will update the real one via volume or copy)
RUN mkdir -p /usr/share/nginx/html/assets
COPY src/assets/env.json /usr/share/nginx/html/assets/env.json

# Add logging: write nginx access/error logs to stdout/stderr
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80

# Docker-native health check (used by Docker itself, not Jenkins)
HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
