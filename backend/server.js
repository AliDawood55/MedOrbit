// Root .env is loaded by src/config/database.js and src/config/env.js
// (both resolve it explicitly, independent of require order) — do not add
// another dotenv.config() call here. This file previously had one targeting
// backend/.env (a path that has never existed), which did nothing useful
// and printed a raw DB password to the console — removed.
const app = require("./src/app");

const env = require("./src/config/env");

const logger = require("./src/utils/logger");


const server = app.listen(
  env.app.port,
  () => {

    logger.info(
      "========================================"
    );

    logger.info(
      `${env.app.name} API Server`
    );

    logger.info(
      `Running on port ${env.app.port}`
    );

    logger.info(
      `Environment: ${env.app.environment}`
    );

    logger.info(
      "========================================"
    );

  }
);