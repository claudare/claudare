const baseUrl = `ws://localhost:${process.env.PORT ?? "7000"}`;

console.log("connecting to", baseUrl);

async function runClient(thisActor, peerActor, data) {
  const ws = new WebSocket(`${baseUrl}/${thisActor}`);
  ws.addEventListener("message", (ev) => {
    const json = JSON.parse(ev.data);
    console.log("got message from", json.actor, "with data", json.data);
  });
  while (true) {
    await sleep(3_000);
    ws.send(JSON.stringify({ actor: peerActor, data }));
  }
}

async function main() {
  await Promise.all([
    runClient("a", "b", "Wazzap B"),
    runClient("b", "a", "Nothin"),
  ]);
}

async function sleep(ms) {
  return new Promise((res) => setTimeout(res, ms));
}

await main();
