import Foundation

public enum ByteFormatting {
    public static func bytes(_ value: UInt64) -> String {
        format(Double(value), suffix: "")
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        "\(format(bytesPerSecond, suffix: ""))/s"
    }

    public static func compactRate(_ bytesPerSecond: Double) -> String {
        "\(compactFormat(bytesPerSecond))/s"
    }

    private static func format(_ value: Double, suffix: String) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = value
        var unitIndex = 0

        while amount >= 1024, unitIndex < units.count - 1 {
            amount /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(amount)) \(units[unitIndex])\(suffix)"
        }

        return String(format: "%.1f %@%@", amount, units[unitIndex], suffix)
    }

    private static func compactFormat(_ value: Double) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var amount = value
        var unitIndex = 0

        while amount >= 1024, unitIndex < units.count - 1 {
            amount /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(amount))\(units[unitIndex])"
        }

        if amount >= 100 {
            return "\(Int(amount.rounded()))\(units[unitIndex])"
        }

        return String(format: "%.1f%@", amount, units[unitIndex])
    }
}
