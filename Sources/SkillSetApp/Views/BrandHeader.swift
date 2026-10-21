import SwiftUI

struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("PerchLogo", bundle: .module)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("栖集 Perch"))
                    .font(AppFont.heading)
                    .foregroundStyle(AppColor.ink)
                Text(L10n.tr("栖集工作台"))
                    .font(AppFont.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
