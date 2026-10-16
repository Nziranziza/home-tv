import Foundation
import Testing
@testable import HomeTV

/// Language detection from real add-on stream titles, names, and descriptions.
struct StreamLanguagesTests {

    @Test func torrentioFlagsLine() {
        let title = """
        Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX
        👤 1234 💾 25.1 GB ⚙️ TorrentGalaxy
        Multi Audio / 🇬🇧 / 🇮🇹 / 🇫🇷 / 🇪🇸
        """
        let languages = StreamLanguages.parse(title)
        #expect(languages.audio == ["en", "it", "fr", "es"])
        #expect(languages.isMulti)
        #expect(languages.summary(maxFlags: 2) == "🇬🇧🇮🇹 +2")
        #expect(languages.detail() == "Multi · 🇬🇧🇮🇹🇫🇷🇪🇸")
    }

    @Test func regionalFlagVariants() {
        let languages = StreamLanguages.parse("Coco.2017.1080p.BluRay.x264\nDual Audio / 🇲🇽 / 🇧🇷 / 🇯🇵 / 🇩🇪")
        #expect(languages.audio == ["es-419", "pt-BR", "ja", "de"])
        #expect(languages.isDual)
        #expect(languages.detail() == "Dual · 🇲🇽🇧🇷🇯🇵🇩🇪")
    }

    @Test func flagsKeepTheAddonsCountry() {
        #expect(StreamLanguages.parse("Movie.2020.1080p\n🇺🇸 / 🇩🇪").detail() == "🇺🇸🇩🇪")
        #expect(StreamLanguages.parse("Movie.2020.1080p.ENG.ITA.JPN.KOR.HIN").summary() == "🇬🇧🇮🇹🇯🇵🇰🇷 +1")
    }

    @Test func releaseNameTags() {
        let languages = StreamLanguages.parse(
            "Obsession.2026.2160p.UHD.WEB-DL.DV.HDR10Plus.HEVC.Atmos.TrueHD.7.1.MULTi.ENG.FRA.GER.ITA.SPA.JPN-FLUX 62.4 GB"
        )
        #expect(languages.audio == ["en", "fr", "de", "it", "es", "ja"])
        #expect(languages.isMulti)
    }

    @Test func dualAudioTags() {
        let languages = StreamLanguages.parse("Oppenheimer.2023.1080p.BluRay.x264.DUAL.ITA.ENG-MIRCrew")
        #expect(languages.audio == ["it", "en"])
        #expect(languages.detail() == "Dual · 🇮🇹🇬🇧")
    }

    @Test func frenchAndLatinoTags() {
        #expect(StreamLanguages.parse("Le.Comte.de.Monte-Cristo.2024.FRENCH.1080p.WEB-DL.H264").audio == ["fr"])
        #expect(StreamLanguages.parse("Movie.2023.VFF.2160p.WEB.H265").audio == ["fr"])
        #expect(StreamLanguages.parse("Movie.2023.VFQ.1080p.WEB").audio == ["fr-CA"])
        #expect(StreamLanguages.parse("Obsession.2026.1080p.CAMRip.LAT.ENG.DUB.1XBET.mp4 3.15 GB").audio == ["es-419", "en"])
    }

    @Test func multiWithoutLanguages() {
        let languages = StreamLanguages.parse("Movie.2023.MULTi.1080p.WEB.H264-FW\n👤 12 💾 4.2 GB ⚙️ YggTorrent")
        #expect(languages.audio.isEmpty)
        #expect(languages.summary() == "Multiple languages")
        #expect(languages.detail() == "Multiple languages")
    }

    @Test func nothingDetected() {
        let languages = StreamLanguages.parse("Show.S01E01.1080p.WEB.h264-ETHEL\n👤 42 💾 2.1 GB ⚙️ EZTV")
        #expect(languages == .empty)
        #expect(languages.summary() == nil)
        #expect(languages.detail() == "—")
        #expect(languages.subtitleDetail() == nil)
    }

    @Test func titleWordsBeforeTheYearAreIgnored() {
        #expect(StreamLanguages.parse("The.Italian.Job.2003.1080p.BluRay.x264-GROUP").audio.isEmpty)
        #expect(StreamLanguages.parse("French.Kiss.1080p.WEB-DL").audio.isEmpty)
        #expect(StreamLanguages.parse("The.Italian.Job.WEB-DL.x264").audio.isEmpty)
        #expect(StreamLanguages.parse("The.Italian.Job.WEB-DL.x264.FRENCH").audio == ["fr"])
    }

    @Test func unlabelledProseIsIgnored() {
        #expect(StreamLanguages.parse("A Spanish film about a German family").audio.isEmpty)
        #expect(StreamLanguages.parse("French Kiss").audio.isEmpty)
    }

    @Test func subtitleLineFlagsAreSubtitles() {
        let languages = StreamLanguages.parse("Subtitles: 🇬🇧 / 🇮🇹")
        #expect(languages.audio.isEmpty)
        #expect(languages.subtitles == ["en", "it"])
    }

    @Test func labelledSectionsOnOneLine() {
        let languages = StreamLanguages.parse("Audio: English | Subtitles: Spanish")
        #expect(languages.audio == ["en"])
        #expect(languages.subtitles == ["es"])
    }

    @Test func multiAndDualLabelsWithColons() {
        let multi = StreamLanguages.parse("Multi Audio: English, Spanish")
        #expect(multi.isMulti)
        #expect(multi.audio == ["en", "es"])
        let dual = StreamLanguages.parse("Dual Audio: ENG / ITA")
        #expect(dual.isDual)
        #expect(dual.audio == ["en", "it"])
    }

    @Test func multiInASubtitleSectionIsSubtitles() {
        let multi = StreamLanguages.parse("Audio: English | Subs: Multi")
        #expect(!multi.isMulti)
        #expect(multi.hasMultipleSubtitles)
        #expect(multi.audio == ["en"])
        #expect(!StreamLanguages.parse("Subtitles: Dual").isDual)
    }

    @Test func languagesAfterMultiSubAreSubtitles() {
        for title in ["Movie.2023.1080p.MULTI.SUB.ENG.FRA", "Movie.2023.1080p.MULTISUBS.ENG.FRA"] {
            let languages = StreamLanguages.parse(title)
            #expect(languages.audio.isEmpty)
            #expect(languages.subtitles == ["en", "fr"])
            #expect(languages.hasMultipleSubtitles)
        }
    }

    @Test func audioAndSubtitleFlagsStaySeparate() {
        let languages = StreamLanguages.parse("Audio: 🇺🇸\nSubtitles: 🇬🇧")
        #expect(languages.detail() == "🇺🇸")
        #expect(languages.subtitleDetail() == "🇬🇧")
    }

    @Test func laterFlagSetsTheShownCountry() {
        #expect(StreamLanguages.parse("Movie.2020.1080p.ENG\n🇺🇸").detail() == "🇺🇸")
    }

    @Test func plainTextDescriptions() {
        #expect(StreamLanguages.parse("Audio: English, Spanish").audio == ["en", "es"])
        #expect(StreamLanguages.parse("🗣 ENG | ITA").audio == ["en", "it"])
        #expect(StreamLanguages.parse("\u{1F5E3}\u{FE0F} ENG | ITA").audio == ["en", "it"])
    }

    @Test func subtitleTags() {
        let hindi = StreamLanguages.parse("Pathaan.2023.Hindi.1080p.WEB-DL.DD5.1.x264.ESub")
        #expect(hindi.audio == ["hi"])
        #expect(hindi.subtitles == ["en"])

        let vostfr = StreamLanguages.parse("Film.2022.1080p.WEB.VOSTFR")
        #expect(vostfr.audio.isEmpty)
        #expect(vostfr.subtitles == ["fr"])

        let subIta = StreamLanguages.parse("Movie.2021.1080p.ENG.SUB.ITA")
        #expect(subIta.audio == ["en"])
        #expect(subIta.subtitles == ["it"])

        let multiSubs = StreamLanguages.parse("Movie.2020.1080p.WEB.Multi.Subs")
        #expect(!multiSubs.isMulti)
        #expect(multiSubs.subtitleDetail() == "Multiple languages")

        let line = StreamLanguages.parse("Audio: English\nSubtitles: Spanish, French")
        #expect(line.audio == ["en"])
        #expect(line.subtitles == ["es", "fr"])
    }

    @Test func reportedSubtitleTracks() {
        let languages = StreamLanguages.parse("Movie.2020.1080p", subtitleCodes: ["eng", "ita", "en", "pob", "pt-BR", "fr-CA", "und"])
        #expect(languages.subtitles == ["en", "it", "pt-BR", "fr-CA"])
        #expect(languages.subtitleDetail() == "🇬🇧🇮🇹🇧🇷🇨🇦")
    }

    @Test func chineseScriptsStayApart() {
        let languages = StreamLanguages.parse("Movie.2020.1080p", subtitleCodes: ["zh-Hans", "zh-Hant", "zh-Hans"])
        #expect(languages.subtitles == ["zh-Hans", "zh-Hant"])
        #expect(languages.subtitleDetail() == "🇨🇳🇹🇼")
    }

    @Test func streamMetaCarriesLanguages() {
        let stream = HomeTV.Stream(
            name: "[RD+] Torrentio\n4k DV",
            title: "Dune.Part.Two.2024.2160p.WEB-DL.DV.H.265-FLUX\n👤 1234 💾 25.1 GB\nMulti Audio / 🇬🇧 / 🇮🇹",
            description: nil,
            url: nil,
            ytId: nil,
            infoHash: "abc",
            fileIdx: nil,
            sources: nil,
            behaviorHints: nil,
            subtitles: [StreamSubtitle(id: "1", url: nil, lang: "spa")]
        )
        let meta = StreamMeta.make(from: stream)
        #expect(meta.languages.audio == ["en", "it"])
        #expect(meta.languages.subtitles == ["es"])
        #expect(meta.subtitleDetail != nil)
    }
}
