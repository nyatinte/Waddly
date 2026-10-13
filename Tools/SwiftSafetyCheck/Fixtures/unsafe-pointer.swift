func use(_ pointer: Swift.UnsafePointer<Int>) {}
let allocated = UnsafeMutablePointer<Int>.allocate(capacity: 1)
