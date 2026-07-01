import { createApp } from "./app.js";

const port = process.env.PORT || 3003;
createApp().listen(port, () => {
  console.log(`doctor-service listening on ${port}`);
});
