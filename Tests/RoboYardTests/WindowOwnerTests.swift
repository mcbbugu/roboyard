import AppKit
import Testing
@testable import RoboYard

struct WindowOwnerTests {
    let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test
    func convertsCocoaPointsOnPrimaryAndNeighborScreens() {
        #expect(WindowOwner.quartzPoint(cocoa: CGPoint(x: 100, y: 80), primaryFrame: primary)
            == CGPoint(x: 100, y: 1000))
        #expect(WindowOwner.quartzPoint(cocoa: CGPoint(x: 2000, y: 100), primaryFrame: primary)
            == CGPoint(x: 2000, y: 980))
        #expect(WindowOwner.quartzPoint(cocoa: CGPoint(x: 100, y: 1500), primaryFrame: primary)
            == CGPoint(x: 100, y: -420))
    }

    @Test
    func picksFrontmostLayerZeroWindowAndSkipsSelf() {
        let safari = WindowOwner.Record(layer: 0, owner: "Safari", bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let xcode = WindowOwner.Record(layer: 0, owner: "Xcode", bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let selfApp = WindowOwner.Record(layer: 0, owner: "RoboYard", bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let menu = WindowOwner.Record(layer: 25, owner: "Window Server", bounds: CGRect(x: 0, y: 0, width: 1920, height: 24))
        let cocoa = CGPoint(x: 40, y: 800)
        let front = WindowOwner.name(
            atCocoa: cocoa, primaryFrame: primary,
            windows: [selfApp, menu, safari, xcode],
            skip: ["RoboYard"], fallback: "Finder"
        )
        #expect(front == "Safari")
    }

    @Test
    func fallsBackWhenNoWindowContainsThePoint() {
        let window = WindowOwner.Record(layer: 0, owner: "Safari", bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        let name = WindowOwner.name(
            atCocoa: CGPoint(x: 900, y: 500), primaryFrame: primary,
            windows: [window], skip: ["RoboYard"], fallback: "Finder"
        )
        #expect(name == "Finder")
    }
}

struct CritterTalkTests {
    @Test
    func stripsThinkBlocksQuotesAndBannedWords() {
        #expect(CritterTalk.cleaned("<think>nope</think>嘿，让开") == "嘿，让开")
        #expect(CritterTalk.cleaned("「借过」") == "借过")
        #expect(CritterTalk.cleaned("INTJ 走开") == nil)
        #expect(CritterTalk.cleaned("a") == nil)
        #expect(CritterTalk.cleaned("这是一句特别长特别长特别长的台词会被截断", lang: .zh)?.count == 18)
    }

    @Test
    func normalizesOllamaEndpoint() {
        #expect(CritterTalk.normalizedEndpoint(" http://127.0.0.1:11434/ ") == "http://127.0.0.1:11434")
        #expect(CritterTalk.tagsURL(from: "http://127.0.0.1:11434")?.absoluteString == "http://127.0.0.1:11434/api/tags")
        #expect(CritterTalk.extract(["choices": [["message": ["content": "借过"]]]]) == "借过")
        #expect(CritterTalk.extract(["message": ["content": "嘿"]]) == "嘿")
    }

    @Test
    func chatFollowUpThreadsTheOtherLine() {
        #expect(CritterTalk.chatFollowUp(replyTo: nil) == nil)
        #expect(CritterTalk.chatFollowUp(replyTo: " ") == nil)
        let cue = CritterTalk.chatFollowUp(replyTo: "走到边就过不去", lang: .zh)
        #expect(cue?.contains("走到边就过不去") == true)
        #expect(cue?.contains("不要另起") == true)
        let en = CritterTalk.chatFollowUp(replyTo: "hit the wall", lang: .en)
        #expect(en?.contains("hit the wall") == true)
        #expect(en?.contains("change the subject") == true)
    }

    @Test
    func copySwitchesRobotNames() {
        #expect(Copy(lang: .zh).robot(1) == "01 号")
        #expect(Copy(lang: .en).robot(1) == "No. 01")
        #expect(Copy(lang: .en).systemPrompt.contains("English") == true)
    }
}
