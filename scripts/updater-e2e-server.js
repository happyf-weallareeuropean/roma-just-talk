#!/usr/bin/env node

const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const { once } = require("node:events");

const root = path.resolve(process.argv[2] || ".");
const requestedPort = Number(process.argv[3] || 0);
const routes = new Map([
  ["/appcast.xml", { file: "appcast.xml", type: "application/xml", delay: 0 }],
  ["/roma.just.talk.app.zip", {
    file: "roma.just.talk.app.zip",
    type: "application/zip",
    delay: 30,
  }],
]);

const server = http.createServer(async (request, response) => {
  const pathname = new URL(request.url, "http://127.0.0.1").pathname;
  const route = routes.get(pathname);
  console.log(`${request.method} ${pathname}`);

  if (!route || !["GET", "HEAD"].includes(request.method)) {
    response.writeHead(404).end();
    return;
  }

  const filePath = path.join(root, route.file);
  try {
    const stat = await fs.promises.stat(filePath);
    response.writeHead(200, {
      "Content-Type": route.type,
      "Content-Length": stat.size,
      "Cache-Control": "no-store",
    });
    if (request.method === "HEAD") {
      response.end();
      return;
    }

    const stream = fs.createReadStream(filePath, { highWaterMark: 256 * 1024 });
    for await (const chunk of stream) {
      if (!response.write(chunk)) {
        await once(response, "drain");
      }
      if (route.delay > 0) {
        await new Promise((resolve) => setTimeout(resolve, route.delay));
      }
    }
    response.end();
  } catch (error) {
    if (!response.headersSent) {
      response.writeHead(500);
    }
    response.end();
    console.error(error.message);
  }
});

server.listen(requestedPort, "127.0.0.1", () => {
  const address = server.address();
  console.log(`READY ${address.port}`);
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
