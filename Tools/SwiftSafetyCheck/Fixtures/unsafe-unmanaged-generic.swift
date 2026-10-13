final class Box {}
let retained = Unmanaged<Box>.passRetained(Box())
