# MedOrbit backend — Node 18
#
# bullseye-slim (glibc) instead of alpine (musl): package.json depends on the
# native `bcrypt` module, which ships prebuilt binaries for glibc targets but
# often has to compile from source on musl/alpine, requiring extra build
# tooling. Slim avoids that risk while staying reasonably small.
FROM node:20-bullseye-slim

WORKDIR /app

# Root context: root package.json/package-lock.json carry the npm workspace
# definition, backend/package.json is the workspace member being installed.
COPY package.json package-lock.json ./
COPY backend/package.json ./backend/package.json
# -w backend scopes the install to the backend workspace's own dependencies
# (root-only deps like uuid, root devDependencies like cypress/concurrently
# are excluded); --omit=dev additionally drops backend's own devDependencies.
RUN npm ci --omit=dev -w backend

# Whole tree in one shot — .dockerignore is the only thing that should ever
# decide what's excluded. Don't replace this with individual COPY lines for
# specific files/folders; a single odd file (see the errorHandler.js /
# response.js reparse-point incident) shouldn't be able to silently break
# unrelated parts of the build.
COPY backend/ ./backend/

WORKDIR /app/backend

EXPOSE 3001

CMD ["node", "server.js"]
