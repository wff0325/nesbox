# ==========================================
# 阶段 1: 编译前端静态页面 (Node.js)
# ==========================================
FROM node:18-alpine AS frontend-builder
WORKDIR /app
COPY . .
RUN yarn install && yarn build

# ==========================================
# 阶段 2: 编译后端服务 (Rust)
# ==========================================
FROM rust:1.70 AS backend-builder
WORKDIR /app
COPY . .
# 编译后端服务端程序
RUN cargo build --release --bin server

# ==========================================
# 阶段 3: 最终运行镜像 (Nginx + 后端合体)
# ==========================================
FROM nginx:alpine
WORKDIR /app

# 安装必要的依赖库
RUN apk add --no-cache libgcc libstdc++ ca-certificates

# 1. 复制编译好的后端可执行文件
COPY --from=backend-builder /app/target/release/server /app/nesbox-server

# 2. 复制编译好的前端网页文件到 Nginx 目录
COPY --from=frontend-builder /app/packages/webapp/dist /usr/share/nginx/html

# 3. 写入 Nginx 配置文件（同时处理前端网页 + 后端接口反代）
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

# 4. 创建启动脚本：同时启动后端与 Nginx
RUN echo '#!/bin/sh' > /app/entrypoint.sh && \
    echo '/app/nesbox-server &' >> /app/entrypoint.sh && \
    echo 'nginx -g "daemon off;"' >> /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/app/entrypoint.sh"]
