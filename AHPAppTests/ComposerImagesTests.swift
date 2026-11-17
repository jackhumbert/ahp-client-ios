import AgentHostProtocol
import Foundation
import Testing
import UIKit
@testable import AHPApp

@MainActor
struct ComposerImagesTests {
    private func image(width: CGFloat, height: CGFloat, opaque: Bool = true, noisy: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if opaque {
                UIColor.systemTeal.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            guard noisy else { return }
            // Noise compresses badly, which is what pushes a photo past the limit.
            var generator = SystemRandomNumberGenerator()
            let step: CGFloat = 4
            for x in stride(from: 0, to: width, by: step) {
                for y in stride(from: 0, to: height, by: step) {
                    UIColor(
                        red: .random(in: 0...1, using: &generator),
                        green: .random(in: 0...1, using: &generator),
                        blue: .random(in: 0...1, using: &generator),
                        alpha: 1
                    ).setFill()
                    context.fill(CGRect(x: x, y: y, width: step, height: step))
                }
            }
        }
    }

    private func pixelSize(_ data: Data) -> CGSize? {
        UIImage(data: data).map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) }
    }

    @Test func aLargePhotoIsShrunkToTheLongEdgeLimit() throws {
        let data = try #require(ImageEncoding.jpeg(from: image(width: 4032, height: 3024)))
        #expect(pixelSize(data) == CGSize(width: 1568, height: 1176))
    }

    @Test func aSmallImageIsNotEnlarged() throws {
        let data = try #require(ImageEncoding.jpeg(from: image(width: 300, height: 200)))
        #expect(pixelSize(data) == CGSize(width: 300, height: 200))
    }

    @Test func pointSizeIsNotMistakenForPixels() throws {
        let cgImage = try #require(image(width: 600, height: 400).cgImage)
        let retina = UIImage(cgImage: cgImage, scale: 3, orientation: .up)
        let data = try #require(ImageEncoding.jpeg(from: retina))
        #expect(pixelSize(data) == CGSize(width: 600, height: 400))
    }

    @Test func anImageThatCompressesBadlyStillFitsTheByteLimit() throws {
        let data = try #require(ImageEncoding.jpeg(from: image(width: 3000, height: 3000, noisy: true)))
        #expect(data.count <= ImageEncoding.maxBytes)
    }

    @Test func transparencyIsFlattenedOntoWhite() throws {
        let data = try #require(ImageEncoding.jpeg(from: image(width: 8, height: 8, opaque: false)))
        let cgImage = try #require(UIImage(data: data)?.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(pixel[0] > 250 && pixel[1] > 250 && pixel[2] > 250)
    }

    @Test func imagesBecomeEmbeddedJPEGAttachmentsInOrder() throws {
        let images = try [image(width: 20, height: 10), image(width: 10, height: 20)].map {
            try #require(ComposerImage($0))
        }
        let attachments = ComposerImage.attachments(images)
        #expect(attachments.map(\.label) == ["image-1.jpg", "image-2.jpg"])
        for (attachment, image) in zip(attachments, images) {
            let embedded = try #require(attachment.embeddedImage)
            #expect(embedded.type == .embeddedResource)
            #expect(embedded.contentType == "image/jpeg")
            #expect(embedded.displayKind == "image")
            #expect(Data(base64Encoded: embedded.data) == image.data)
        }
    }

    @Test func anAttachmentGoesOnTheWireAsTheSpecNamesIt() throws {
        let image = try #require(ComposerImage(image(width: 4, height: 4)))
        let json = try JSONEncoder().encode(ComposerImage.attachments([image])[0])
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["type"] as? String == "embeddedResource")
        #expect(object["contentType"] as? String == "image/jpeg")
        #expect(object["data"] as? String == image.data.base64EncodedString())
    }

    @Test func onlyEmbeddedImagesAreShownAsPictures() {
        let pdf = MessageAttachment.embeddedResource(MessageEmbeddedResourceAttachment(
            label: "a.pdf", type: .embeddedResource, data: "", contentType: "application/pdf"
        ))
        let file = MessageAttachment.resource(MessageResourceAttachment(label: "a.png", uri: "a.png", type: .resource))
        #expect(pdf.embeddedImage == nil)
        #expect(file.embeddedImage == nil)
    }

    // MARK: Paste

    @Test func pasteIsOfferedWhenThePasteboardHoldsOnlyAnImage() {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        pasteboard.image = image(width: 12, height: 12)

        let view = ImagePastingTextView()
        view.pasteboard = pasteboard
        let paste = #selector(UIResponderStandardEditActions.paste(_:))
        // Without somewhere to put images, it is an ordinary text view.
        #expect(!view.canPerformAction(paste, withSender: nil))
        view.onPasteImages = { _ in }
        #expect(view.canPerformAction(paste, withSender: nil))
    }

    @Test func aPastedImageIsHandedOverAndKeptOutOfTheText() async {
        let view = ImagePastingTextView()
        var pasted: [UIImage] = []
        view.onPasteImages = { pasted += $0 }

        let taken = await withCheckedContinuation { continuation in
            view.takeImage(from: NSItemProvider(object: image(width: 12, height: 12))) {
                continuation.resume(returning: $0)
            }
        }
        #expect(taken)
        #expect(pasted.map(\.size) == [CGSize(width: 12, height: 12)])
    }

    @Test func pastedTextIsLeftToTheTextView() async {
        let view = ImagePastingTextView()
        var pasted: [UIImage] = []
        view.onPasteImages = { pasted += $0 }

        let taken = await withCheckedContinuation { continuation in
            view.takeImage(from: NSItemProvider(object: "words" as NSString)) {
                continuation.resume(returning: $0)
            }
        }
        #expect(!taken)
        #expect(pasted.isEmpty)
    }
}
