import Darwin
import Foundation

struct InterfaceCounterSampler: Sendable {
    func sample() -> [String: BytePair] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0

        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0,
              length > 0 else {
            return [:]
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            return [:]
        }

        return buffer.withUnsafeBytes { rawBuffer in
            var result: [String: BytePair] = [:]
            var offset = 0

            while offset + MemoryLayout<if_msghdr2>.size <= length {
                let header = rawBuffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }

                if header.ifm_type == UInt8(RTM_IFINFO2),
                   let name = interfaceName(index: header.ifm_index),
                   isRelevant(name) {
                    result[name] = BytePair(
                        downloaded: header.ifm_data.ifi_ibytes,
                        uploaded: header.ifm_data.ifi_obytes
                    )
                }

                offset += messageLength
            }

            return result
        }
    }

    private func interfaceName(index: UInt16) -> String? {
        var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        guard if_indextoname(UInt32(index), &name) != nil else { return nil }
        return String(cString: name)
    }

    private func isRelevant(_ name: String) -> Bool {
        name == "lo0" || Self.isPhysical(name)
    }

    static func isPhysical(_ name: String) -> Bool {
        let value = name.lowercased()
        if value.hasPrefix("pdp_ip") { return true }
        guard value.hasPrefix("en") else { return false }
        return Int(value.dropFirst(2)) != nil
    }
}
