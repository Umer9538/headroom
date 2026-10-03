/// What the estimator needs to know about a model: how many bytes a token
/// has to pull through memory.
public struct ModelSpec: Sendable, Hashable, Codable {
    /// KV-cache geometry, from the GGUF keys named on each field.
    public struct KVGeometry: Sendable, Hashable, Codable {
        /// `<arch>.block_count`
        public let layers: Int
        /// `<arch>.attention.head_count_kv`
        public let kvHeads: Int
        /// `<arch>.embedding_length / <arch>.attention.head_count`
        public let headDim: Int
        /// 2 for the f16 cache llama.cpp uses by default.
        public let bytesPerValue: Int

        public init(layers: Int, kvHeads: Int, headDim: Int, bytesPerValue: Int = 2) {
            self.layers = layers
            self.kvHeads = kvHeads
            self.headDim = headDim
            self.bytesPerValue = bytesPerValue
        }

        /// Keys and values, every layer, one token.
        public var bytesPerToken: Int {
            2 * layers * kvHeads * headDim * bytesPerValue
        }
    }

    public let name: String
    /// Bytes of weights read once per decoded token.
    public let tensorBytes: Int
    public let parameters: Int?
    /// Nil when the geometry is not known, in which case the KV cache is not modelled.
    public let kv: KVGeometry?

    public init(name: String, tensorBytes: Int, parameters: Int? = nil, kv: KVGeometry?) {
        precondition(tensorBytes > 0, "a model has weights")
        self.name = name
        self.tensorBytes = tensorBytes
        self.parameters = parameters
        self.kv = kv
    }

    /// A model known only by its file size. The whole file is taken as weights
    /// (GGUF metadata is well under 1% of it) and the KV cache is not modelled.
    public init(name: String, ggufBytes: Int) {
        self.init(name: name, tensorBytes: ggufBytes, parameters: nil, kv: nil)
    }

    public func kvBytes(contextTokens: Int) -> Int {
        (kv?.bytesPerToken ?? 0) * contextTokens
    }

    /// Single-stream decode reads every weight once per token, plus the cache
    /// for every token already in context.
    public func bytesPerToken(contextTokens: Int) -> Int {
        tensorBytes + kvBytes(contextTokens: contextTokens)
    }
}

extension ModelSpec {
    /// TinyLlama-1.1B-1T-OpenOrca Q4_0, the model PocketRoofline measured.
    ///
    /// Every field read from the GGUF header of the file with SHA-256
    /// bd07d1c53b833d422272259b17b393270b8f81c937d14332dfa044fe1b349884:
    /// tensor bytes are the sum of every tensor's on-disk size (201 tensors),
    /// `llama.block_count` 22, `llama.attention.head_count_kv` 4,
    /// `llama.embedding_length` 2048 / `llama.attention.head_count` 32 = 64.
    public static let tinyLlama1_1BQ4_0 = ModelSpec(
        name: "TinyLlama-1.1B Q4_0",
        tensorBytes: 635_990_016,
        parameters: 1_100_048_384,
        kv: KVGeometry(layers: 22, kvHeads: 4, headDim: 64)
    )

    /// Qwen2.5-0.5B-Instruct Q4_K_M, read the same way from the file with SHA-256
    /// 6eb923e7d26e9cea28811e1a8e852009b21242fb157b26149d3b188f3a8c8653:
    /// 290 tensors, `qwen2.block_count` 24, `qwen2.attention.head_count_kv` 2,
    /// `qwen2.embedding_length` 896 / `qwen2.attention.head_count` 14 = 64.
    public static let qwen2_5_0_5BInstructQ4_K_M = ModelSpec(
        name: "Qwen2.5-0.5B-Instruct Q4_K_M",
        tensorBytes: 391_859_712,
        parameters: 494_032_768,
        kv: KVGeometry(layers: 24, kvHeads: 2, headDim: 64)
    )
}
