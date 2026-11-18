import Foundation

/// Display names for catalog values, and the extra words each is searchable by.
enum PlayerTestVocabulary {
    static func codecName(_ value: String) -> String {
        switch value {
        case "hevc", "h265": "HEVC"
        case "h264": "H.264"
        case "h263": "H.263"
        case "h263p": "H.263+"
        case "av1": "AV1"
        case "vp8": "VP8"
        case "vp9": "VP9"
        case "mpeg1video": "MPEG-1"
        case "mpeg2video": "MPEG-2"
        case "mjpeg": "Motion JPEG"
        case "flv": "Sorenson FLV"
        case "wmv1": "WMV 7"
        case "wmv2": "WMV 8"
        case "ac3": "AC-3"
        case "eac3": "E-AC-3"
        default: value.uppercased()
        }
    }

    static func hdrName(_ value: String) -> String {
        switch value {
        case "sdr": "SDR"
        case "hdr10": "HDR10"
        case "hdr10plus": "HDR10+"
        case "hlg": "HLG"
        case "dolbyVision": "Dolby Vision"
        default: value
        }
    }

    /// Words a value is also found by: `dv` finds Dolby Vision, `4k` finds 2160p.
    static func aliases(_ value: String) -> String {
        switch value {
        case "dolbyVision": "Dolby Vision DV DoVi HDR"
        case "hdr10": "HDR10 HDR"
        case "hdr10plus": "HDR10+ HDR"
        case "hlg": "HLG HDR"
        case "2160p", "4K": "4K UHD 2160p"
        case "8K": "8K 4320p"
        case "hevc", "h265": "HEVC H.265 x265"
        case "h264": "H.264 AVC x264"
        case "mpeg2video": "MPEG-2"
        case "mpeg1video": "MPEG-1"
        case "ac3": "AC-3 Dolby Digital"
        case "eac3": "E-AC-3 EAC3 Dolby Digital Plus DD+"
        case "flac", "alac": "Lossless"
        default: ""
        }
    }
}
