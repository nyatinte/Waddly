import Darwin

/// A standalone API positive control, not a Waddly memory-budget measurement.
@main
struct PurgeableQueryProbe {
    private enum Failure: Error {
        case mach(String, kern_return_t), shortReply, unsupportedLayout, controlMismatch(String)
    }

    static func main() {
        do {
            try run()
        } catch {
            fputs("Purgeable query probe failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        let size: mach_vm_size_t = 16 * 1024 * 1024
        var address: mach_vm_address_t = 0
        print("stage,flavor,returned_integer_count,rss_bytes,physical_footprint_bytes," +
            "purgeable_volatile_pmap_bytes,purgeable_volatile_resident_bytes,purgeable_volatile_virtual_bytes," +
            "ledger_purgeable_volatile_bytes")
        try pair("baseline")
        try check(mach_vm_allocate(mach_task_self_, &address, size, VM_FLAGS_ANYWHERE | VM_FLAGS_PURGABLE), "allocate")
        defer {
            if address != 0 {
                let result = mach_vm_deallocate(mach_task_self_, address, size)
                if result != KERN_SUCCESS {
                    fputs("Cleanup failed: \(result)\n", stderr)
                }
            }
        }
        guard let pointer = UnsafeMutableRawPointer(bitPattern: UInt(address)) else { throw Failure.unsupportedLayout }
        memset(pointer, 0xA5, Int(size)) // Commit every page of this process's own allocation.
        try pair("nonvolatile")
        var state = Int32(VM_PURGABLE_VOLATILE)
        try check(mach_vm_purgable_control(mach_task_self_, address, VM_PURGABLE_SET_STATE, &state), "mark-volatile")
        let basic = try snapshot("volatile", flavor: TASK_VM_INFO)
        let queried = try snapshot("volatile", flavor: TASK_VM_INFO_PURGEABLE)
        try require(
            volatileCounters(basic).allSatisfy { $0 == 0 }, "basic flavor unexpectedly populated volatile fields"
        )
        try require(volatileCounters(queried).allSatisfy { $0 >= size }, "volatile positive control not fully observed")
        try require(basic.ledger_purgeable_volatile >= Int64(size), "basic volatile ledger control not observed")
        state = Int32(VM_PURGABLE_NONVOLATILE)
        try check(
            mach_vm_purgable_control(mach_task_self_, address, VM_PURGABLE_SET_STATE, &state), "restore-nonvolatile"
        )
        let restored = try snapshot("restored", flavor: TASK_VM_INFO_PURGEABLE)
        try require(volatileCounters(restored).allSatisfy { $0 == 0 }, "volatile counters did not return to zero")
        try check(mach_vm_deallocate(mach_task_self_, address, size), "deallocate")
        address = 0
        try pair("deallocated")
        fputs("QUERY_CONTRACT_COMPLETED owned_bytes=\(size)\n", stderr)
    }

    private static func pair(_ stage: String) throws {
        _ = try snapshot(stage, flavor: TASK_VM_INFO)
        _ = try snapshot(stage, flavor: TASK_VM_INFO_PURGEABLE)
    }

    private static func volatileCounters(_ info: task_vm_info_data_t) -> [mach_vm_size_t] {
        [info.purgeable_volatile_pmap, info.purgeable_volatile_resident, info.purgeable_volatile_virtual]
    }

    private static func snapshot(_ stage: String, flavor: Int32) throws -> task_vm_info_data_t {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(flavor), $0, &count)
            }
        }
        try check(result, "task_info")
        // This is the last emitted struct field; do not accept a truncated reply.
        guard let offset = MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_purgeable_volatile) else {
            throw Failure.unsupportedLayout
        }
        let requiredBytes = offset + MemoryLayout.size(ofValue: info.ledger_purgeable_volatile)
        guard Int(count) * MemoryLayout<integer_t>.size >= requiredBytes else {
            throw Failure.shortReply
        }
        let name = flavor == TASK_VM_INFO ? "TASK_VM_INFO" : "TASK_VM_INFO_PURGEABLE"
        print("\(stage),\(name),\(count),\(info.resident_size),\(info.phys_footprint)," +
            "\(info.purgeable_volatile_pmap),\(info.purgeable_volatile_resident),\(info.purgeable_volatile_virtual)," +
            "\(info.ledger_purgeable_volatile)")
        fflush(stdout)
        return info
    }

    private static func check(_ result: kern_return_t, _ operation: String) throws {
        guard result == KERN_SUCCESS else { throw Failure.mach(operation, result) }
    }

    private static func require(_ condition: Bool, _ detail: String) throws {
        guard condition else { throw Failure.controlMismatch(detail) }
    }
}
