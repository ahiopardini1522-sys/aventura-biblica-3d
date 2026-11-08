// Permite importar src/worker.js en Node: "cloudflare:workers" solo existe dentro de Cloudflare,
// así que aquí se redirige a una versión mínima de prueba.
export async function resolve(specifier, context, nextResolve) {
  if (specifier === "cloudflare:workers") {
    return { url: new URL("./cloudflare_workers_stub.mjs", import.meta.url).href, shortCircuit: true };
  }
  return nextResolve(specifier, context);
}
