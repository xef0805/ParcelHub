export class ModalNavigation {
  #pages = [];
  get depth() { return this.#pages.length; }
  get current() { return this.#pages.at(-1); }
  start(render) { this.#pages = [{ render, scrollTop: 0 }]; }
  push(render, scrollTop = 0) {
    if (!this.current) throw new Error('No parent settings page');
    this.current.scrollTop = scrollTop;
    this.#pages.push({ render, scrollTop: 0 });
  }
  back() { if (this.depth > 1) this.#pages.pop(); return this.current; }
  clear() { this.#pages = []; }
}
