# ==========================================
# 阶段 1: 编译前端静态页面 (Node.js)
# ==========================================
FROM node:18-alpine AS frontend-builder
WORKDIR /app
COPY . .
RUN yarn install && yarn build

# ==========================================
# 阶段 2: 编译后端服务 (Rust 补齐 C 依赖)
# ==========================================
FROM rust:1.75-bookworm AS backend-builder
WORKDIR /app

# 安装 Rust 编译 Diesel PostgreSQL 所需的底层库
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY . .

# 编译后端
RUN cargo build --release --package server

# ==========================================
# 阶段 3: 运行镜像 (Nginx 托管前端并反代后端)
# ==========================================
FROM nginx:alpine
WORKDIR /app

# 安装运行时依赖库 (libpq 用于运行时连接 postgres)
RUN apk add --no-cache libgcc libstdc++ ca-certificates libpq

# 复制编译好的后端二进制文件
COPY --from=backend-builder /app/target/release/server /app/nesbox-server

# 复制前端编译出的静态资源
COPY --from=frontend-builder /app/packages/webapp/dist /usr/share/nginx/html

# 写入合一的 Nginx 配置
RUN echo 'server {' > /etc/nginx/conf.d/default.conf && \
    echo '    listen 80;' >> /etc/nginx/conf.d/default.conf && \
    echo '    location /graphql {' >> /etc/nginx/conf.d/default.conf && \
    echo '        proxy_pass http://127.0.0.1:8080;' >> /etc/nginx/conf.d/default.conf && \
    echo '        proxy_http_version 1.1;' >> /etc/nginx/conf.d/default.conf && \
    echo '        proxy_set_header Upgrade $http_upgrade;' >> /etc/nginx/conf.d/default.conf && \
    echo '        proxy_set_header Connection "upgrade";' >> /etc/nginx/conf.d/default.conf && \
    echo '    }' >> /etc/nginx/conf.d/default.conf && \
    echo '    location / {' >> /etc/nginx/conf.d/default.conf && \
    echo '        root /usr/share/nginx/html;' >> /etc/nginx/conf.d/default.conf && \
    echo '        try_files $uri $uri/ /index.html;' >> /etc/nginx/conf.d/default.conf && \
    echo '    }' >> /etc/nginx/conf.d/default.conf && \
    echo '}' >> /etc/nginx/conf.d/default.conf

# 启动脚本
RUN echo '#!/bin/sh' > /app/entrypoint.sh && \
    echo '/app/nesbox-server &' >> /app/entrypoint.sh && \
    echo 'nginx -g "daemon off;"' >> /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/app/entrypoint.sh"]
