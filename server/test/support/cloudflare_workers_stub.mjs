// Versión mínima de la clase base DurableObject de Cloudflare, solo para las pruebas.
export class DurableObject {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }
}
