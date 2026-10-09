# GPU and network demos

- [Single node](single-node/README.md): Tiny LLM simulation requests a mock AMD
  GPU through DRA and an ERNIC through AMD Network Operator on the same VM worker.
- [Two nodes](two-node/README.md): reserved for a separate RDMA payload/checksum
  transfer demonstration. Not implemented or invoked by the single-node setup.

The [integration guide](../../docs/guides/gpu-network.md) describes the layers,
source revisions, configuration adaptations and setup requirements.
