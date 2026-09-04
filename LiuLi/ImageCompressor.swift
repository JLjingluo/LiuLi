import UIKit

// MARK: - 图片压缩与 data URL 转换（识图用）

enum ImageCompressor {

    /// 压缩为 JPEG data URL（OpenAI 视觉格式）。
    /// - 长边压到 maxDimension 以内，质量 0.6——兼顾识别效果与上传体积。
    static func compressToDataURL(_ data: Data, maxDimension: CGFloat = 1568, quality: CGFloat = 0.6) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = resize(image, maxDimension: maxDimension)
        guard let jpeg = resized.jpegData(compressionQuality: quality) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// data URL → UIImage（气泡缩略图）
    static func imageFromDataURL(_ dataURL: String) -> UIImage? {
        guard let comma = dataURL.firstIndex(of: ","),
              dataURL.hasPrefix("data:image/") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}
