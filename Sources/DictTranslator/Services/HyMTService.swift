import Foundation
import llama

/// 腾讯混元翻译模型 Hy-MT2 本地推理（llama.cpp，Apple 芯片走 Metal）
/// 提示词、对话模板与采样参数严格按官方模型卡（tencent/Hy-MT2-7B、Hy-MT2-1.8B）：
/// - 无 system prompt，单条 user 消息 + add_generation_prompt
/// - 涉及中文的方向用中文指令（语言名用中文全称），其余用英文指令（语言名用英文全称）
/// - temperature 0.7 / top_p 0.6 / top_k 20 / repetition_penalty 1.05 / max_tokens 4096
enum HyMTService {
    static func translate(_ text: String, from: Lang, to: Lang, model: LocalModel) async throws -> String {
        guard model.isInstalled else {
            throw TranslatorError.unavailable("尚未下载 \(model.displayName) 模型（设置 › 通用 › 句子翻译服务）")
        }
        let prompt = chatPrompt(instruction(for: text, from: from, to: to), model: model)
        let flag = CancelFlag()
        LlamaRunner.markUsed()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                LlamaRunner.shared.queue.async {
                    cont.resume(with: Result { try LlamaRunner.shared.generate(prompt: prompt, model: model, cancel: flag) })
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }

    /// 释放已加载的本地模型（切换到别的翻译服务时调用，内存立即归还）；keep 为仍在使用的模型
    static func unloadAll(except keep: LocalModel? = nil) {
        guard LlamaRunner.isUsed else { return }
        LlamaRunner.shared.queue.async { LlamaRunner.shared.unloadUnless(keep) }
    }

    /// 删除模型文件前释放已加载的模型
    static func unload(_ model: LocalModel) {
        guard LlamaRunner.isUsed else { return }
        LlamaRunner.shared.queue.async { LlamaRunner.shared.unload(only: model) }
    }

    // MARK: - 提示词（官方「Default Translation」模板）

    static func instruction(for text: String, from: Lang, to: Lang) -> String {
        if from == .zh || to == .zh {
            return "将以下文本翻译为\(to.hyChineseName)，注意只需要输出翻译后的结果，不要额外解释：\n\n\(text)"
        }
        return "Translate the following text into \(to.hyEnglishName). Note that you should only output the translated result without any additional explanation:\n\n\(text)"
    }

    /// 与各模型自带的 chat_template.jinja 渲染结果一致（单条 user 消息、无 system、add_generation_prompt=True）。
    /// 两个模型的分词器不同：1.8B 用 <｜hy_…｜> 标记，7B 沿用 Hunyuan-7B 的 <|startoftext|>/<|extra_0|>。
    /// 模板标记与用户内容分开分词：原文里即使出现「<|eos|>」这类字样也只当普通文字
    static func chatPrompt(_ user: String, model: LocalModel) -> ChatPrompt {
        switch model {
        case .hyMT2_1_8B: return ChatPrompt(prefix: "<｜hy_begin▁of▁sentence｜><｜hy_User｜>", user: user, suffix: "<｜hy_Assistant｜>")
        case .hyMT2_7B: return ChatPrompt(prefix: "<|startoftext|>", user: user, suffix: "<|extra_0|>")
        }
    }
}

struct ChatPrompt {
    var prefix: String
    var user: String
    var suffix: String
    var rendered: String { prefix + user + suffix }
}

private extension Lang {
    var hyChineseName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "英语"
        case .ja: return "日语"
        }
    }

    var hyEnglishName: String {
        switch self {
        case .zh: return "Chinese"
        case .en: return "English"
        case .ja: return "Japanese"
        }
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.withLock { value = true } }
    var isCancelled: Bool { lock.withLock { value } }
}

/// 所有 llama.cpp 调用都在同一个串行队列上执行；同一时间只加载一个模型，闲置一段时间后自动释放内存
final class LlamaRunner: @unchecked Sendable {
    static let shared = LlamaRunner()

    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var used = false
    /// 正在进行的推理（退出时中断它）
    private var current: CancelFlag?

    static func markUsed() { stateLock.withLock { used = true } }
    static var isUsed: Bool { stateLock.withLock { used } }

    /// 进程退出时（菜单退出、exit() 等所有途径）中断正在进行的推理并释放模型：模型还在内存里时退出，
    /// llama.cpp 的 Metal 资源会在进程退出时触发断言崩溃。从没用过本地模型时什么都不做，不初始化 llama
    static func shutdownIfUsed() {
        guard isUsed else { return }
        stateLock.withLock { shared.current }?.cancel()
        shared.queue.sync { shared.unloadAll() }
    }

    let queue = DispatchQueue(label: "dict.hymt", qos: .userInitiated)

    /// 官方上限是输入 4K、输出 4K；MachineTranslator 已把长文切成不超过 1000 字的片段，
    /// 一段的原文加译文远小于 4K，上下文开 4K 足够（KV 缓存比 8K 省一半内存）
    private let maxInputTokens = 3072
    private let maxOutputTokens = 4096
    private let contextSize: UInt32 = 4096
    private let batchSize: UInt32 = 2048
    /// 闲置这么久自动释放模型（切换到其他翻译服务时立即释放）
    private let idleUnloadSeconds: TimeInterval = 3 * 60

    private var loaded: LocalModel?
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var lastUsed = Date()
    private var unloadScheduled = false
    private var exitHandlerInstalled = false

    /// generation_config.json 里的 eos_token_id（llama.cpp 未必把它们都标记为结束符，按文本再判一次）
    private func stopPieces(_ model: LocalModel) -> Set<String> {
        switch model {
        case .hyMT2_1_8B: return ["<｜hy_place▁holder▁no▁2｜>", "<｜hy_place▁holder▁no▁8｜>", "<｜hy_User｜>"]
        case .hyMT2_7B: return ["<|eos|>", "<|extra_5|>", "<|startoftext|>", "<|endoftext|>"]
        }
    }

    private init() {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }

    func generate(prompt: ChatPrompt, model target: LocalModel, cancel: CancelFlag) throws -> String {
        dispatchPrecondition(condition: .onQueue(queue))
        Self.stateLock.withLock { current = cancel }
        defer { Self.stateLock.withLock { current = nil } }
        if cancel.isCancelled { throw CancellationError() }
        try load(target)
        guard let model, let context, let vocab = llama_model_get_vocab(model) else {
            throw TranslatorError.unavailable("\(target.displayName) 模型加载失败")
        }
        defer {
            lastUsed = Date()
            scheduleIdleUnload()
        }

        // 模板里已含 BOS，不再自动加；只有模板标记按特殊 token 解析，用户内容按普通文字
        let userTokens = tokenize(prompt.user, vocab: vocab, special: false)
        var tokens = tokenize(prompt.prefix, vocab: vocab, special: true) + userTokens + tokenize(prompt.suffix, vocab: vocab, special: true)
        guard !userTokens.isEmpty else { throw TranslatorError.empty }
        guard tokens.count <= maxInputTokens + 64 else {
            throw TranslatorError.unavailable("文本过长（超过 \(target.displayName) 单次可处理的长度）")
        }

        llama_memory_clear(llama_get_memory(context), true)
        var offset = 0
        while offset < tokens.count {
            if cancel.isCancelled { throw CancellationError() }
            let n = min(Int(batchSize), tokens.count - offset)
            let rc = tokens.withUnsafeMutableBufferPointer { buf in
                llama_decode(context, llama_batch_get_one(buf.baseAddress! + offset, Int32(n)))
            }
            guard rc == 0 else { throw TranslatorError.unavailable("本地模型推理失败（\(rc)）") }
            offset += n
        }

        let sampler = makeSampler(vocab: vocab)
        defer { llama_sampler_free(sampler) }

        var output = Data()
        var piece = [CChar](repeating: 0, count: 256)
        let stops = stopPieces(target)
        // 译文长度与原文相当；远超原文说明模型在重复，及时停下（调用方已按段落切分，正常不会碰到）
        let limit = min(maxOutputTokens, Int(contextSize) - tokens.count, max(256, userTokens.count * 4))
        for _ in 0..<limit {
            if cancel.isCancelled { throw CancellationError() }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            let len = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, true)
            guard len > 0 else { continue }
            let bytes = piece[0..<Int(len)].map { UInt8(bitPattern: $0) }
            let attr = llama_vocab_get_attr(vocab, token).rawValue
            if attr & (LLAMA_TOKEN_ATTR_CONTROL.rawValue | LLAMA_TOKEN_ATTR_USER_DEFINED.rawValue) != 0 {
                if stops.contains(String(decoding: bytes, as: UTF8.self)) { break }
                if attr & LLAMA_TOKEN_ATTR_CONTROL.rawValue != 0 { continue } // 其他控制标记不输出
            }
            output.append(contentsOf: bytes)
            let rc = llama_decode(context, llama_batch_get_one(&token, 1))
            guard rc == 0 else { throw TranslatorError.unavailable("本地模型推理失败（\(rc)）") }
        }
        tokens.removeAll()

        let text = String(decoding: output, as: UTF8.self)
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranslatorError.empty }
        return text
    }

    /// 官方推荐参数：repetition_penalty 1.05 → top_k 20 → top_p 0.6 → temperature 0.7 → 随机采样
    private func makeSampler(vocab: OpaquePointer) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.05, 0, 0))
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(20))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.6, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max - 1)))
        return chain
    }

    private func tokenize(_ text: String, vocab: OpaquePointer, special: Bool) -> [llama_token] {
        guard !text.isEmpty else { return [] }
        let utf8 = Array(text.utf8CString)
        let byteCount = Int32(utf8.count - 1)
        var tokens = [llama_token](repeating: 0, count: Int(byteCount) + 8)
        var n = llama_tokenize(vocab, utf8, byteCount, &tokens, Int32(tokens.count), false, special)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, utf8, byteCount, &tokens, Int32(tokens.count), false, special)
        }
        return n > 0 ? Array(tokens.prefix(Int(n))) : []
    }

    private func load(_ target: LocalModel) throws {
        if loaded == target, model != nil, context != nil { return }
        unloadAll()
        let params = llama_model_default_params()
        guard let m = llama_model_load_from_file(target.fileURL.path, params) else {
            throw TranslatorError.unavailable("\(target.displayName) 模型加载失败，可在设置中删除后重新下载")
        }
        var cparams = llama_context_default_params()
        cparams.n_ctx = contextSize
        cparams.n_batch = batchSize
        guard let c = llama_init_from_model(m, cparams) else {
            llama_model_free(m)
            throw TranslatorError.unavailable("\(target.displayName) 初始化失败（内存不足？）")
        }
        model = m
        context = c
        loaded = target
        // atexit 按注册的逆序执行：llama.cpp 的 Metal 清理在加载模型时才注册，所以在这之后注册，保证先释放模型
        if !exitHandlerInstalled {
            exitHandlerInstalled = true
            atexit { LlamaRunner.shutdownIfUsed() }
        }
    }

    func unloadUnless(_ keep: LocalModel?) {
        dispatchPrecondition(condition: .onQueue(queue))
        if loaded != nil, loaded != keep { unloadAll() }
    }

    func unload(only target: LocalModel) {
        dispatchPrecondition(condition: .onQueue(queue))
        if loaded == target { unloadAll() }
    }

    private func unloadAll() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        loaded = nil
    }

    private func scheduleIdleUnload() {
        guard !unloadScheduled else { return }
        unloadScheduled = true
        queue.asyncAfter(deadline: .now() + idleUnloadSeconds) { [self] in
            unloadScheduled = false
            if Date().timeIntervalSince(lastUsed) >= idleUnloadSeconds - 1 {
                unloadAll()
            } else if loaded != nil {
                scheduleIdleUnload()
            }
        }
    }

    #if DEBUG
    /// 返回 GGUF 内置的对话模板（llama.cpp 的 C 接口无法正确渲染它，所以按官方 jinja 手写，见 chatPrompt）
    func debugEmbeddedTemplate(_ target: LocalModel) -> String {
        queue.sync {
            do { try load(target) } catch { return "加载失败：\(error.localizedDescription)" }
            guard let model, let tmpl = llama_model_chat_template(model, nil) else { return "GGUF 无内置模板" }
            return String(cString: tmpl)
        }
    }
    #endif
}
