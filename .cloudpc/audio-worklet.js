class CloudPCPCM extends AudioWorkletProcessor {
  constructor() {
    super();

    this.queue = [];
    this.index = 0;
    this.stored = 0;
    this.playing = false;

    this.port.onmessage = (event) => {
      const data = event.data;

      if (data && data.type === "reset") {
        this.queue = [];
        this.index = 0;
        this.stored = 0;
        this.playing = false;
        return;
      }

      if (!(data instanceof ArrayBuffer)) return;

      const view = new DataView(data);
      const count = Math.floor(data.byteLength / 2);
      const samples = new Float32Array(count);

      for (let i = 0; i < count; i++) {
        samples[i] =
          view.getInt16(i * 2, true) / 32768;
      }

      this.queue.push(samples);
      this.stored += samples.length;

      // Maximum buffer: 350 ms
      const max = Math.floor(sampleRate * 0.35);

      if (this.stored > max) {
        // Drop old audio, keep approximately 120 ms
        let drop = this.stored -
          Math.floor(sampleRate * 0.12);

        while (drop > 0 && this.queue.length) {
          const available =
            this.queue[0].length - this.index;

          const take = Math.min(drop, available);

          this.index += take;
          this.stored -= take;
          drop -= take;

          if (this.index >= this.queue[0].length) {
            this.queue.shift();
            this.index = 0;
          }
        }
      }
    };
  }

  process(inputs, outputs) {
    const out = outputs[0][0];
    out.fill(0);

    // Initial buffer: 80 ms
    if (!this.playing) {
      if (this.stored < sampleRate * 0.08) {
        return true;
      }
      this.playing = true;
    }

    for (let i = 0; i < out.length; i++) {
      if (this.stored <= 0) {
        this.playing = false;
        break;
      }

      out[i] = this.queue[0][this.index++];
      this.stored--;

      if (this.index >= this.queue[0].length) {
        this.queue.shift();
        this.index = 0;
      }
    }

    return true;
  }
}

registerProcessor("cloudpc-pcm", CloudPCPCM);
