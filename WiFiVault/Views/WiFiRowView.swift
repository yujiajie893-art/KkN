import SwiftUI
import UIKit

struct WiFiRowView: View {
    let record: WiFiRecord
    let password: String
    let showPassword: Bool
    let onEdit: () -> Void

    @State private var didCopy = false

    private var displayedPassword: String {
        if password.isEmpty {
            return "未设置密码"
        }

        if showPassword {
            return password
        }

        return String(repeating: "•", count: min(max(password.count, 8), 16))
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.blue.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: "wifi")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(record.ssid)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Image(systemName: showPassword ? "lock.open.fill" : "lock.fill")
                        .font(.caption)

                    Text(displayedPassword)
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)

                if !record.note.isEmpty {
                    Text(record.note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if showPassword && !password.isEmpty {
                Button {
                    UIPasteboard.general.string = password
                    didCopy = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.body.weight(.medium))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(didCopy ? .green : .blue)
                .accessibilityLabel(didCopy ? "已复制" : "复制密码")
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .onTapGesture(perform: onEdit)
    }
}
