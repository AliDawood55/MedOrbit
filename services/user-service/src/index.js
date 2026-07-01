import { createApp } from "./app.js";

const port = process.env.PORT || 3002;
createApp().listen(port, () => {
  console.log(`user-service listening on ${port}`);
});
