func use(_ pointer: Swift.UnsafePointer<Int>) {}
let allocated = UnsafeMutablePointer<Int>.allocate(capacity: 1)

final class Box {}
let retained = Unmanaged.passRetained(Box())
