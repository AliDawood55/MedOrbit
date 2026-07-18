// Load root .env BEFORE any requires that read process.env
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

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