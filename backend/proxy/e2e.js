async function main() {
  const ws = new WebSocket("http://localhost:8080/test");
  ws.addEventListener("message", (ev) => {
    console.log("got message", ev.data);
  });
  while (true) {
    await sleep(1_000);
    ws.send("hello");
  }
}

async function sleep(ms) {
  return new Promise((res) => setTimeout(res, ms));
}

await main();
