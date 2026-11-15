import Foundation
import Testing
@testable import BarnOwl

struct SensitiveTextTests {
    private func kinds(_ text: String) -> [SensitiveTextFinder.Kind] {
        SensitiveTextFinder.classify(text).map(\.1)
    }

    private func found(_ text: String) -> [String] {
        SensitiveTextFinder.classify(text).map { String(text[$0.0]) }
    }

    @Test(arguments: [
        "Open task-management-dashboard-v2 in Xcode",
        "risk-assessment-framework.md",
        "AppIcon@2x.png and logo@3x.jpg",
        "git@github.com:owner/repo.git",
        "Created 1729543200000 ms",
        "https://www.google.com/search?q=swift+regex",
        "https://youtube.com/watch?v=dQw4w9WgXcQ",
        "Version 1.2.3.4 build",
        "listening on 127.0.0.1:8080 and 192.168.1.20",
        "0000 0000 0000 0000",
        "Dato 21.10.2026 kl 23:34",
        "2026-10-21 23:34:12",
        "Commit 7440fdf Find sensitive text",
        "Fødselsnummer 01019012345",
        "7440fdf2c9b1e6a3f0d4c8b2a1e9f7d6c5b4a3e2",
    ])
    func leavesOrdinaryTextAlone(text: String) {
        #expect(kinds(text).isEmpty, "\(text): \(found(text))")
    }

    @Test func findsKeysAndTokens() {
        #expect(kinds("ghp_1234567890abcdefABCDEF1234567890") == [.key])
        // OCR often drops the underscore.
        #expect(kinds("ghp 1234567890abcdefABCDEF1234567890") == [.key])
        #expect(kinds("sk_live_51HxYzAbCdEf0123456789") == [.key])
        #expect(kinds("https://hooks.slack.com/services/T0000/B0000/XXXXXXXXXXXXXXXXXXXXXXXX") == [.key])
        #expect(kinds("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U") == [.key])
        #expect(kinds("token a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7") == [.key])
    }

    @Test func hidesOnlyTheValueOfALabelledSecret() {
        #expect(found("PASSWORD=Sup3rS3cret!") == ["Sup3rS3cret!"])
        // Named by the label: a password, or a key or token.
        #expect(kinds("PASSWORD=Sup3rS3cret!") == [.password])
        #expect(kinds("DEPLOY_TOKEN=Zq8vR2mK9xL4") == [.key])
        #expect(kinds("api_key: Zq8vR2mK9xL4") == [.key])
        #expect(found("aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY") == ["wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"])
        #expect(found("Authorization: Bearer abc123def456ghi789jkl012mno345") == ["abc123def456ghi789jkl012mno345"])
        let env = SensitiveTextFinder.classify("OPENAI_API_KEY=sk-proj-AbCdEf0123456789XyZaBcDeF")
        #expect(env.count == 1 && env[0].1.tier == .secret)
        // A long value is still only the value: the label isn't part of the key.
        #expect(found("OPENAI_API_KEY=sk-proj-AbCdEf0123456789XyZaBcDeF") == ["sk-proj-AbCdEf0123456789XyZaBcDeF"])
        #expect(found("aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY") == ["wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"])
        #expect(found("DEPLOY=a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7") == ["a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7"])
        // The padding that ends base64 belongs to it.
        #expect(found("blob QWxhZGRpbjpvcGVuIHNlc2FtZTEyMzQ1Njc4OTAxMjM0NTY3OA== end") == ["QWxhZGRpbjpvcGVuIHNlc2FtZTEyMzQ1Njc4OTAxMjM0NTY3OA=="])
    }

    @Test func cutsAWordOnlyAtAGapBetweenItsLetters() {
        // Letters five columns wide and a column apart, as monospaced type; `joined` letters run into the next.
        func ink(letters: Int, joined: Set<Int> = []) -> [Bool] {
            var columns = [Bool](repeating: false, count: 2)
            for letter in 0..<letters {
                columns += [Bool](repeating: true, count: 5)
                columns.append(joined.contains(letter))
            }
            return columns + [false, false]
        }
        let word = "password=abc"
        // Before the "a": its first column of ink, to hide from there on.
        #expect(SensitiveTextFinder.cut(before: 9, in: word, ink: ink(letters: 12), hidingRight: true) == 2 + 9 * 6)
        // Hiding up to there instead: the column after the "=".
        #expect(SensitiveTextFinder.cut(before: 9, in: word, ink: ink(letters: 12), hidingRight: false) == 2 + 9 * 6 - 1)
        // "=" and "a" run together: the cut moves out, a letter too many rather than one too few.
        #expect(SensitiveTextFinder.cut(before: 9, in: word, ink: ink(letters: 12, joined: [8]), hidingRight: true) == 2 + 8 * 6)
        #expect(SensitiveTextFinder.cut(before: 9, in: word, ink: ink(letters: 12, joined: [8]), hidingRight: false) == 2 + 10 * 6 - 1)
        // Nothing to go by: letters that all run together, or ink that isn't this word's.
        #expect(SensitiveTextFinder.cut(before: 9, in: word, ink: ink(letters: 12, joined: Set(0..<12)), hidingRight: true) == nil)
        #expect(SensitiveTextFinder.cut(before: 9, in: word, ink: ink(letters: 17), hidingRight: true) == nil)
        #expect(SensitiveTextFinder.cut(before: 0, in: word, ink: ink(letters: 12), hidingRight: true) == nil)
    }

    @Test func coversPasswordsInLinks() {
        let text = "postgres://admin:hunter2@db.example.com:5432/app"
        let result = SensitiveTextFinder.classify(text)
        #expect(result.count == 1 && result[0].1 == .credentialLink)
        #expect(String(text[result[0].0]).hasPrefix("admin:hunter2"))
    }

    @Test func findsCardNumbersEvenWithTheCodeAfterThem() {
        #expect(found("4111 1111 1111 1111") == ["4111 1111 1111 1111"])
        #expect(found("4111111111111111 123") == ["4111111111111111"])
        #expect(found("4242 4242 4242 4242 12 2030") == ["4242 4242 4242 4242"])
        #expect(!SensitiveTextFinder.isCard("1234 5678 9012 3456"))
    }

    @Test func findsPersonalDetails() {
        #expect(kinds("Contact: kari.nordmann @ firma.no") == [.email])
        #expect(kinds("Mail me at ola@example.com") == [.email])
        #expect(kinds("IBAN NO93 8601 1117 947") == [.iban])
        #expect(kinds("Fødselsnummer 01019012480") == [.nationalID])
        #expect(found("/Users/kari/code/priv") == ["kari"])
        #expect(kinds("Call +47 412 34 567") == [.phone])
        #expect(kinds("Server at 8.8.8.8") == [.ipAddress])
    }

    @Test func checksums() {
        #expect(SensitiveTextFinder.luhn([4, 2, 4, 2, 4, 2, 4, 2, 4, 2, 4, 2, 4, 2, 4, 2]))
        #expect(SensitiveTextFinder.isIBAN("GB82 WEST 1234 5698 7654 32"))
        #expect(!SensitiveTextFinder.isIBAN("GB82 WEST 1234 5698 7654 33"))
        #expect(SensitiveTextFinder.isNorwegianID("01019012480"))
        #expect(!SensitiveTextFinder.isNorwegianID("01019012345"))
    }

    @Test func groupsLinesIntoBlocks() {
        let lines = [CGRect(x: 10, y: 10, width: 200, height: 20), CGRect(x: 10, y: 34, width: 180, height: 20),
                     CGRect(x: 400, y: 10, width: 100, height: 20)]
        let blocks = SensitiveTextFinder.blocks(of: lines)
        #expect(blocks.count == 2)
        #expect(blocks.contains(CGRect(x: 10, y: 10, width: 200, height: 44)))
    }

    @Test func readsTextInReadingOrder() {
        func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 100) -> CaptureText.Line {
            CaptureText.Line(rect: CGRect(x: x, y: y, width: width, height: 20), text: text, words: [])
        }
        // A form: short labels and values on the same rows read across.
        var form = CaptureText()
        form.lines = [line("Sam", x: 300, y: 12), line("Name", x: 10, y: 10), line("Role", x: 10, y: 50),
                      line("Owner", x: 300, y: 51)]
        #expect(form.plainText() == "Name\tSam\nRole\tOwner")
        // A sidebar beside a page: each column on its own, never interleaved.
        var mail = CaptureText()
        mail.lines = [line("Inbox", x: 10, y: 10, width: 80), line("Dear Anna, thanks for the notes.", x: 150, y: 10, width: 500),
                      line("Please send the slides.", x: 150, y: 35, width: 420), line("Sent", x: 10, y: 50, width: 60),
                      line("See you Friday.", x: 150, y: 60, width: 300), line("Drafts", x: 10, y: 90, width: 70)]
        #expect(mail.plainText() == "Inbox\nSent\nDrafts\n\nDear Anna, thanks for the notes.\nPlease send the slides.\nSee you Friday.")
        #expect(mail.plainText(within: CGRect(x: 140, y: 0, width: 600, height: 100)).hasPrefix("Dear Anna"))
    }

    @Test func leavesOutWhatIsHidden() {
        let words = [CaptureText.Word(rect: CGRect(x: 10, y: 10, width: 60, height: 20), text: "Token:"),
                     CaptureText.Word(rect: CGRect(x: 80, y: 10, width: 200, height: 20), text: "ghp_secret")]
        var text = CaptureText()
        text.lines = [CaptureText.Line(rect: CGRect(x: 10, y: 10, width: 270, height: 20), text: "Token: ghp_secret", words: words)]
        #expect(text.plainText(excluding: [CGRect(x: 75, y: 5, width: 210, height: 30)]) == "Token:")
        #expect(text.plainText(excluding: [CGRect(x: 0, y: 0, width: 400, height: 40)]).isEmpty)
    }

    @Test func leavesOutAWordWhoseSecretPartIsHidden() {
        // Only the value is covered, and the word's middle is on the label's side.
        let words = [CaptureText.Word(rect: CGRect(x: 10, y: 10, width: 160, height: 20), text: "password=hunter2"),
                     CaptureText.Word(rect: CGRect(x: 180, y: 10, width: 40, height: 20), text: "next")]
        var text = CaptureText()
        text.lines = [CaptureText.Line(rect: CGRect(x: 10, y: 10, width: 210, height: 20),
                                       text: "password=hunter2 next", words: words)]
        // The cover's padding just grazes the next word, which stays.
        #expect(text.plainText(excluding: [CGRect(x: 100, y: 5, width: 85, height: 30)]) == "next")
    }

    @Test func leavesOutALongWordWhoseShortSecretIsHidden() {
        // A user name in a path: its cover is an eighth of the word, and all of it is on the word.
        let words = [CaptureText.Word(rect: CGRect(x: 10, y: 10, width: 400, height: 20), text: "/Users/kari/code/priv/notes.txt"),
                     CaptureText.Word(rect: CGRect(x: 420, y: 10, width: 60, height: 20), text: "opened")]
        var text = CaptureText()
        text.lines = [CaptureText.Line(rect: CGRect(x: 10, y: 10, width: 470, height: 20),
                                       text: "/Users/kari/code/priv/notes.txt opened", words: words)]
        #expect(text.plainText(excluding: [CGRect(x: 80, y: 5, width: 50, height: 30)]) == "opened")
        // A cover that only reaches a corner of the word doesn't take it out.
        #expect(text.plainText(excluding: [CGRect(x: 0, y: 0, width: 50, height: 14)]) == "/Users/kari/code/priv/notes.txt opened")
    }

    @Test func padsToTheWholeLine() {
        let word = CGRect(x: 100, y: 12, width: 40, height: 14)
        let line = CGRect(x: 0, y: 10, width: 300, height: 20)
        // The line's height, and a quarter of it again on every side.
        #expect(SensitiveTextFinder.padded(word, line: line) == CGRect(x: 95, y: 5, width: 50, height: 30))
    }
}
