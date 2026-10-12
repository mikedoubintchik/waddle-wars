
      // QA-only scalar observer; no history, forcing GC, or heap contents.
      window.__wwMemorySample = () => {
        const heap = engine.rtenv && engine.rtenv.HEAPU8;
        const js = performance.memory;
        const canvas = document.getElementById("canvas");
        const resources = performance.getEntriesByType("resource");
        const packRequests = [];
        for (const entry of resources) {
          const url = new URL(entry.name, location.href);
          if (url.origin !== location.origin || !/\.(pck|wasm)$/.test(url.pathname)) continue;
          if (packRequests.length >= 8) break;
          packRequests.push({name:url.pathname.split("/").pop(),start_ms:entry.startTime,
            duration_ms:entry.duration,transfer_bytes:entry.transferSize,
            encoded_body_bytes:entry.encodedBodySize,decoded_body_bytes:entry.decodedBodySize});
        }
        return {schema_version:1,ms:performance.now(),visible:!document.hidden,
          focused:document.hasFocus(),wasm_heap_capacity_bytes:heap ? heap.byteLength : null,
          wasm_scope:"Linear-memory capacity, not live allocator bytes or total process memory",
          js_used_bytes:js ? js.usedJSHeapSize : null,js_total_bytes:js ? js.totalJSHeapSize : null,
          js_limit_bytes:js ? js.jsHeapSizeLimit : null,
          js_scope:"Chromium performance.memory estimate; excludes other processes and may omit WASM/native buffers",
          canvas_backing:canvas ? [canvas.width,canvas.height] : null,
          canvas_css:canvas ? [canvas.clientWidth,canvas.clientHeight] : null,
          window_css:[innerWidth,innerHeight],device_pixel_ratio:devicePixelRatio,
          resource_entries:resources.length,pack_requests:packRequests};
      };
