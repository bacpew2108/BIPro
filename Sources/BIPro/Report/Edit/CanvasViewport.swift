import CoreGraphics

/// Vùng của trang đang nhìn thấy trong canvas (toạ độ trang), để đặt visual mới ở giữa phần đang nhìn
/// (`specs/004-d3-them-visual-doi-loai/research.md` R6).
enum CanvasViewport {
    /// - Parameters:
    ///   - offset: vị trí cuộn của ScrollView (`contentOffset`).
    ///   - container: kích thước phần nhìn thấy của ScrollView.
    ///   - pageSize: cỡ trang (toạ độ trang).
    ///   - scale: tỷ lệ thu phóng hiện tại.
    ///   - margin: lề quanh trang trong nội dung cuộn.
    /// - Returns: hình chữ nhật trong toạ độ trang, đã giao với trang; cả trang nếu không tính được.
    static func visibleRect(offset: CGPoint, container: CGSize, pageSize: CGSize, scale: Double, margin: Double) -> CGRect {
        let whole = CGRect(origin: .zero, size: pageSize)
        guard scale > 0, container.width > 0, container.height > 0 else { return whole }
        // Nội dung cuộn: trang (đã nhân tỷ lệ) cộng lề hai phía, tối thiểu bằng phần nhìn thấy; trang nằm giữa nếu nội dung rộng hơn.
        let pageWidth = pageSize.width * scale, pageHeight = pageSize.height * scale
        let contentWidth = max(container.width, pageWidth + margin * 2)
        let contentHeight = max(container.height, pageHeight + margin * 2)
        let originX = max(margin, (contentWidth - pageWidth) / 2)
        let originY = max(margin, (contentHeight - pageHeight) / 2)
        let rect = CGRect(x: (offset.x - originX) / scale, y: (offset.y - originY) / scale,
                          width: container.width / scale, height: container.height / scale)
        let clipped = rect.intersection(whole)
        return clipped.isNull || clipped.width < 1 || clipped.height < 1 ? whole : clipped
    }
}
