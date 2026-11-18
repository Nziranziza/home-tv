#if canImport(KSPlayer)
import CoreGraphics
import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Libswscale
import Synchronization

/// Decodes one keyframe per request over its own connection to the stream, the way Infuse previews
/// without trickplay files. Runs on its own thread, since FFmpeg's reads block.
actor FFmpegThumbnailer: PlaybackThumbnailer {
    private let queue = DispatchSerialQueue(label: "HomeTV.thumbnails", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let url: URL
    /// `url` after its redirects; FFmpeg would follow them again on every seek.
    private var openURL: URL?
    private let headers: [String: String]
    private let interrupt = InterruptFlag()
    private var format: UnsafeMutablePointer<AVFormatContext>?
    private var decoder: UnsafeMutablePointer<AVCodecContext>?
    private var scaler: UnsafeMutablePointer<SwsContext>?
    private var streamIndex: Int32 = -1
    private var hasFailed = false
    private let packet = av_packet_alloc()
    private let decoded = av_frame_alloc()

    init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }

    deinit {
        var packet = packet
        var decoded = decoded
        av_packet_free(&packet)
        av_frame_free(&decoded)
        sws_freeContext(scaler)
        avcodec_free_context(&decoder)
        avformat_close_input(&format)
    }

    nonisolated func close() {
        interrupt.isSet.store(true, ordering: .relaxed)
    }

    func frame(at time: TimeInterval, maxPixelWidth: Int) async -> CGImage? {
        if openURL == nil { openURL = await StreamRedirect.finalURL(of: url, headers: headers) }
        guard !interrupt.isSet.load(ordering: .relaxed), open(),
              let format, let decoder, let packet, let decoded,
              let stream = format.pointee.streams[Int(streamIndex)] else { return nil }
        let timeBase = av_q2d(stream.pointee.time_base)
        let start = stream.pointee.start_time == Int64.min ? 0 : stream.pointee.start_time
        let target = start + Int64(time / timeBase)
        guard av_seek_frame(format, streamIndex, target, AVSEEK_FLAG_BACKWARD) >= 0 else { return nil }
        avcodec_flush_buffers(decoder)
        // The first keyframe after the seek. Draining right after it skips the decoder's reorder delay.
        var packetsRead = 0
        while packetsRead < 300, av_read_frame(format, packet) >= 0 {
            defer { av_packet_unref(packet) }
            guard packet.pointee.stream_index == streamIndex else { continue }
            packetsRead += 1
            guard packet.pointee.flags & AV_PKT_FLAG_KEY != 0, avcodec_send_packet(decoder, packet) >= 0 else { continue }
            avcodec_send_packet(decoder, nil)
            guard avcodec_receive_frame(decoder, decoded) >= 0 else { return nil }
            defer { av_frame_unref(decoded) }
            return image(from: decoded, maxPixelWidth: maxPixelWidth)
        }
        return nil
    }

    /// Opens the stream and its video decoder once; a failure isn't retried.
    private func open() -> Bool {
        if decoder != nil { return true }
        guard !hasFailed, let openURL else { return false }
        hasFailed = true
        var context = avformat_alloc_context()
        context?.pointee.interrupt_callback = AVIOInterruptCB(
            callback: { opaque in
                guard let opaque else { return 0 }
                return Unmanaged<InterruptFlag>.fromOpaque(opaque).takeUnretainedValue()
                    .isSet.load(ordering: .relaxed) ? 1 : 0
            },
            opaque: Unmanaged.passUnretained(interrupt).toOpaque()
        )
        var options: OpaquePointer?
        if !headers.isEmpty {
            av_dict_set(&options, "headers", headers.map { "\($0): \($1)\r\n" }.joined(), 0)
        }
        // Microseconds: a stalled read gives up rather than holding the thread.
        av_dict_set(&options, "rw_timeout", "10000000", 0)
        let opened = avformat_open_input(&context, openURL.absoluteString, nil, &options)
        av_dict_free(&options)
        guard opened >= 0, let context else { return false }
        format = context
        let index = av_find_best_stream(context, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        guard index >= 0, let stream = context.pointee.streams[Int(index)],
              let codec = avcodec_find_decoder(stream.pointee.codecpar.pointee.codec_id),
              let codecContext = avcodec_alloc_context3(codec) else { return false }
        codecContext.pointee.skip_frame = AVDISCARD_NONKEY
        codecContext.pointee.thread_type = FF_THREAD_SLICE
        guard avcodec_parameters_to_context(codecContext, stream.pointee.codecpar) >= 0,
              avcodec_open2(codecContext, codec, nil) >= 0 else {
            var partial: UnsafeMutablePointer<AVCodecContext>? = codecContext
            avcodec_free_context(&partial)
            return false
        }
        // Reads skip the other streams' packets.
        for other in 0..<Int(context.pointee.nb_streams) where other != Int(index) {
            context.pointee.streams[other]?.pointee.discard = AVDISCARD_ALL
        }
        // Published together, only once the decoder is open: `frame` reads both.
        streamIndex = index
        decoder = codecContext
        hasFailed = false
        return true
    }

    private func image(from frame: UnsafeMutablePointer<AVFrame>, maxPixelWidth: Int) -> CGImage? {
        let sourceWidth = frame.pointee.width
        let sourceHeight = frame.pointee.height
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        var aspect = Double(sourceWidth) / Double(sourceHeight)
        let pixelAspect = frame.pointee.sample_aspect_ratio
        if pixelAspect.num > 0, pixelAspect.den > 0 { aspect *= av_q2d(pixelAspect) }
        let width = min(maxPixelWidth, Int(Double(sourceHeight) * aspect))
        let height = max(1, Int(Double(width) / aspect))
        scaler = sws_getCachedContext(
            scaler, sourceWidth, sourceHeight, AVPixelFormat(frame.pointee.format),
            Int32(width), Int32(height), AV_PIX_FMT_BGRA, Int32(SWS_BILINEAR.rawValue), nil, nil, nil
        )
        guard let scaler else { return nil }
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        let scaled = pixels.withUnsafeMutableBytes { buffer -> Int32 in
            var destination: [UnsafeMutablePointer<UInt8>?] = [buffer.bindMemory(to: UInt8.self).baseAddress, nil, nil, nil]
            var destinationStrides: [Int32] = [Int32(bytesPerRow), 0, 0, 0]
            return withUnsafePointer(to: frame.pointee.data) { data in
                data.withMemoryRebound(to: UnsafePointer<UInt8>?.self, capacity: 8) { source in
                    withUnsafePointer(to: frame.pointee.linesize) { linesize in
                        linesize.withMemoryRebound(to: Int32.self, capacity: 8) { strides in
                            sws_scale(scaler, source, strides, 0, sourceHeight, &destination, &destinationStrides)
                        }
                    }
                }
            }
        }
        guard scaled > 0, let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

/// Set by `close`; FFmpeg's interrupt callback reads it from inside a blocking read.
private final class InterruptFlag: Sendable {
    let isSet = Atomic(false)
}
#endif
