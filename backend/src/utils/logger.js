// src/utils/logger.js

const pino = require("pino");

// pino-pretty is a devDependency — not installed in the production Docker
// image (npm ci --omit=dev). Pretty, colorized logs are a local-dev
// convenience; production logs plain structured JSON instead, which is also
// the more standard/parseable format for container log collectors.
const isProduction = process.env.NODE_ENV === "production";

const logger = pino({
    level: process.env.LOG_LEVEL || "info",

    ...(isProduction
        ? {}
        : {
              transport: {
                  target: "pino-pretty",

                  options: {
                      colorize: true,
                      translateTime: "SYS:standard",
                      ignore: "pid,hostname",
                  },
              },
          }),
});

module.exports = logger;