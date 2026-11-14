import CoreGraphics

enum ThumbnailSizing {
    /// 输出画布跟窗口同比例，避免宽窗口被塞进固定 640×400 后右侧留空。
    static func pixelSize(fitting pointSize: CGSize, maxEdge: CGFloat = 960) -> (width: Int, height: Int) {
        let width = max(pointSize.width, 1)
        let height = max(pointSize.height, 1)
        let scale = min(maxEdge / width, maxEdge / height, 2)
        return (
            width: max(Int((width * scale).rounded()), 1),
            height: max(Int((height * scale).rounded()), 1)
        )
    }
}
