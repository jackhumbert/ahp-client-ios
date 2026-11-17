import AgentHostProtocol
import SwiftUI
import UIKit

// MARK: - ComposerImage

/// An image waiting in the message box, already encoded as it will be sent.
nonisolated struct ComposerImage: Identifiable, Sendable {
    let id = UUID()
    /// JPEG bytes, sized by ``ImageEncoding``.
    let data: Data
    let thumbnail: UIImage

    /// Encodes `image` for sending; nil when it cannot be drawn.
    init?(_ image: UIImage) {
        guard let data = ImageEncoding.jpeg(from: image),
              let thumbnail = UIImage(data: data) else { return nil }
        self.data = data
        self.thumbnail = thumbnail
    }

    /// The images as a message's attachments: embedded, base64, in order.
    static func attachments(_ images: [ComposerImage]) -> [MessageAttachment] {
        images.enumerated().map { index, image in
            .embeddedResource(MessageEmbeddedResourceAttachment(
                label: "image-\(index + 1).jpg",
                displayKind: "image",
                type: .embeddedResource,
                data: image.data.base64EncodedString(),
                contentType: ImageEncoding.contentType
            ))
        }
    }
}

// MARK: - ImageEncoding

/// Shrinks an image to what a model reads anyway, so a 12-megapixel photo
/// doesn't travel as megabytes of base64 inside one protocol message.
nonisolated enum ImageEncoding {
    static let contentType = "image/jpeg"
    /// Longest edge, in pixels. Vision models downscale beyond roughly this.
    static let maxLongEdge: CGFloat = 1568
    /// Ceiling for one encoded image, before base64 adds a third.
    static let maxBytes = 500_000

    /// `image` as JPEG within ``maxLongEdge`` and ``maxBytes``, upright and
    /// flattened onto white (JPEG has no alpha). Never upscales.
    static func jpeg(from image: UIImage) -> Data? {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard pixels.width >= 1, pixels.height >= 1 else { return nil }
        var edge = min(maxLongEdge, max(pixels.width, pixels.height))
        // Lower the quality first, then the size, until it fits.
        while true {
            let drawn = draw(image, pixels: pixels, longEdge: edge)
            var smallest: Data?
            for quality in [0.8, 0.6, 0.4] as [CGFloat] {
                guard let data = drawn.jpegData(compressionQuality: quality) else { return nil }
                if data.count <= maxBytes { return data }
                smallest = data
            }
            // Small enough that the limit cannot be what is wrong.
            if edge <= 256 { return smallest }
            edge = max(256, edge * 0.75)
        }
    }

    private static func draw(_ image: UIImage, pixels: CGSize, longEdge: CGFloat) -> UIImage {
        let ratio = longEdge / max(pixels.width, pixels.height)
        let size = CGSize(
            width: max(1, (pixels.width * ratio).rounded()),
            height: max(1, (pixels.height * ratio).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - ComposerImageStrip

/// The images waiting in the message box, each with a button to drop it.
struct ComposerImageStrip: View {
    @Binding var images: [ComposerImage]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { image in
                    Image(uiImage: image.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                images.removeAll { $0.id == image.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove image")
                        }
                        .accessibilityLabel("Attached image")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
    }
}

// MARK: - ComposerTextView

/// A `UITextView` whose Paste also takes images.
///
/// A stock text view only offers Paste for text. This one offers it whenever
/// the pasteboard holds an image, and hands the images over instead of
/// inserting anything.
final class ImagePastingTextView: UITextView, UITextPasteDelegate {
    /// Only asked whether it holds an image; a test swaps in its own.
    var pasteboard: UIPasteboard = .general
    var onPasteImages: (([UIImage]) -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        // Images are taken through the text view's own paste, which hands
        // each pasted item to the delegate below. Reading `UIPasteboard`
        // directly is refused for what another app copied (Photos, say).
        let accepted = UIPasteConfiguration(forAccepting: UIImage.self)
        accepted.addTypeIdentifiers(forAccepting: NSString.self)
        pasteConfiguration = accepted
        pasteDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), onPasteImages != nil, pasteboard.hasImages {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    func textPasteConfigurationSupporting(
        _ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
        transform item: any UITextPasteItem
    ) {
        takeImage(from: item.itemProvider) { taken in
            if taken {
                item.setNoResult()
            } else {
                item.setDefaultResult()
            }
        }
    }

    /// Hands a pasted image to `onPasteImages`; `done(false)` when the item
    /// is not an image, so the text view pastes it as usual.
    func takeImage(from provider: NSItemProvider, done: @escaping (Bool) -> Void) {
        guard let onPasteImages, provider.canLoadObject(ofClass: UIImage.self) else {
            done(false)
            return
        }
        _ = provider.loadObject(ofClass: UIImage.self) { @Sendable object, _ in
            let image = object as? UIImage
            DispatchQueue.main.async {
                if let image {
                    onPasteImages([image])
                }
                done(image != nil)
            }
        }
    }
}

/// The message box's text: grows from one line to `maxLines`, then scrolls.
///
/// A `UITextView` rather than SwiftUI's `TextField`, which has no way to
/// accept a pasted image.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var maxLines = 8
    var onPasteImages: ([UIImage]) -> Void

    func makeUIView(context: Context) -> ImagePastingTextView {
        let view = ImagePastingTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.isScrollEnabled = false
        view.accessibilityLabel = "Message"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: ImagePastingTextView, context: Context) {
        context.coordinator.parent = self
        view.onPasteImages = onPasteImages
        if view.text != text {
            view.text = text
            view.invalidateIntrinsicContentSize()
        }
        // Focus is applied after the update: becoming first responder calls
        // back into the delegate, which writes the binding.
        if isFocused != view.isFirstResponder {
            let wanted = isFocused
            DispatchQueue.main.async {
                guard wanted != view.isFirstResponder, view.window != nil else { return }
                if wanted {
                    view.becomeFirstResponder()
                } else {
                    view.resignFirstResponder()
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ImagePastingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let line = (uiView.font ?? .preferredFont(forTextStyle: .body)).lineHeight
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let tallest = ceil(line * CGFloat(maxLines))
        let scrolls = fitting > tallest
        if uiView.isScrollEnabled != scrolls {
            uiView.isScrollEnabled = scrolls
        }
        return CGSize(width: width, height: min(max(fitting, ceil(line)), tallest))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}

// MARK: - AttachedImage

/// A sent message's embedded image, decoded off the main thread and kept.
struct AttachedImage: View {
    let attachment: MessageEmbeddedResourceAttachment

    @State private var image: UIImage?
    @State private var showFull = false

    private static let cache = NSCache<NSString, UIImage>()

    /// Cheap to compute and distinct enough: base64 of different images
    /// differs in length or at the ends.
    private var cacheKey: String {
        "\(attachment.data.count):\(attachment.data.prefix(48)):\(attachment.data.suffix(48))"
    }

    var body: some View {
        Group {
            if let image {
                Button {
                    showFull = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        // Clipped before the frame, so the corners are the picture's.
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(maxWidth: 220, maxHeight: 160)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(attachment.label)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 120, height: 90)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .task(id: cacheKey) {
            let key = cacheKey as NSString
            if let cached = Self.cache.object(forKey: key) {
                image = cached
                return
            }
            let base64 = attachment.data
            let decoded = await Task.detached {
                Data(base64Encoded: base64).flatMap(UIImage.init(data:))
            }.value
            if let decoded {
                Self.cache.setObject(decoded, forKey: key)
            }
            image = decoded
        }
        .sheet(isPresented: $showFull) {
            if let image {
                NavigationStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle(attachment.label)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showFull = false }
                            }
                        }
                }
            }
        }
    }
}

extension MessageAttachment {
    /// The attachment, when it is an image embedded in the message.
    var embeddedImage: MessageEmbeddedResourceAttachment? {
        guard case .embeddedResource(let resource) = self,
              resource.contentType.hasPrefix("image/") else { return nil }
        return resource
    }
}
