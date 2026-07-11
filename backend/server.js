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