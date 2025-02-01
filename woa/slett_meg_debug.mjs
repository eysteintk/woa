#!/usr/bin/env -S node
import fetch from "node-fetch";
import ws from "ws";
import { WebPubSubClient } from "@azure/web-pubsub-client";
import { setLogLevel, AzureLogger } from "@azure/logger";

globalThis.WebSocket = ws;
setLogLevel("verbose");

AzureLogger.log = (...args) => {
  console.log("[AZURE-LOG]", ...args);
};

try {
  console.log("[HANDSHAKE-TEST] Requesting token...");
  const res = await fetch("http://localhost:3000/api/webpubsub-token", {
    headers: {
      'Accept': 'application/json'
    },
    timeout: 15000 // 15 seconds timeout
  });

  if (!res.ok) {
    const text = await res.text();
    console.error("[HANDSHAKE-TEST] Response not OK:", {
      status: res.status,
      statusText: res.statusText,
      body: text
    });
    process.exit(1);
  }

  const data = await res.json();
  console.log("[HANDSHAKE-TEST] Got response:", JSON.stringify(data, null, 2));

  // Rest of your code...
} catch (error) {
  console.error("[HANDSHAKE-TEST] Detailed error:", {
    name: error.name,
    message: error.message,
    code: error.code,
    type: error.type,
    cause: error.cause,
    stack: error.stack
  });
  process.exit(1);
}