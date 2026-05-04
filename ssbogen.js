const sizes = [1048576, 2097152, 4194304, 8388608, 16777216, 33554432];

for (const N of sizes) {
   const buffers = {
      "bufferObject.0": 4 + 32 * N,
      "bufferObject.3": 4 * N,
      "bufferObject.4": 4 * N,
      "bufferObject.5": 4 * N,
      "bufferObject.6": 64 * (N - 1),
      "bufferObject.7": 9 * N,
      "bufferObject.10": 48 * N,
   };

   const total = Object.values(buffers).reduce((a, b) => a + b, 0);
   const totalMB = (total / 1024 / 1024).toFixed(2);

   console.log(`#elif MAX_QUAD_COUNT == ${N}  // Total VRAM: ${totalMB} MB`);
   for (const [key, val] of Object.entries(buffers)) {
      console.log(`${key.padEnd(16)}= ${val}`);
   }
}
