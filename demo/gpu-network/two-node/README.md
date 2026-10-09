# Two-node RDMA transfer — planned

This is separate from the [single-node GPU/NIC allocation demo](../single-node/README.md).
No transfer scripts or passing results are claimed here yet.

The intended demonstration is two workers, each with a mock GPU and emulated
NIC, plus a CPU-buffer payload transfer and checksum comparison over RDMA.
An LLM is optional presentation context; it is not required to validate RDMA.
Mock GPU allocation does not execute inference or provide GPU-direct DMA.

The current ERNIC documentation lists guest-to-guest rdma_cm/rping as unsupported.
Choose a supported manual-QP/verbs transfer path when implementing this demo,
and prove received bytes with a checksum rather than inferring transfer from
resource allocation or interface counters.
