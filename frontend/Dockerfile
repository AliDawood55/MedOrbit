# MedOrbit frontend — static files only, no build step (no frontend/package.json,
# every page is a plain .html with <script src="../src/js/..."> tags).
# nginx replaces the dev-time `python -m http.server 8080 -d frontend`.
FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf

# Whole tree in one shot — .dockerignore is the only thing that should ever
# decide what's excluded. Don't replace this with individual COPY lines for
# specific files/folders; a single odd file shouldn't be able to silently
# break unrelated parts of the build.
COPY . /usr/share/nginx/html

EXPOSE 8080
