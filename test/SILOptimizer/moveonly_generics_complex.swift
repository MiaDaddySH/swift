// RUN: %target-swift-frontend                               \
// RUN:     -emit-sil -verify                                \
// RUN:     %s                                               \
// RUN:     -enable-experimental-feature BuiltinModule       \
// RUN:     -enable-experimental-feature NoncopyableGenerics \
// RUN:     -sil-verify-all

// REQUIRES: asserts

import Builtin

@frozen
enum MyLittleLayout<T : ~Copyable> {
  @_transparent
  static var size: Int {
    return Int(Builtin.sizeof(T.self))
  }
  @_transparent
  static var stride: Int {
    return Int(Builtin.strideof(T.self))
  }
}

@frozen
enum MyLittleResult<Success : ~Copyable, Failure : Error> : ~Copyable {
  case success(Success)
  case failure(Failure)
}

@usableFromInline
@_alwaysEmitIntoClient
@inline(__always)
func _rethrowsViaClosure<R : ~Copyable>(_ fn: () throws -> R) rethrows -> R {
  return try fn()
}

func _withUnprotectedUnsafeTemporaryAllocation<T: ~Copyable, R: ~Copyable>(
  of type: T.Type,
  capacity: Int,
  alignment: Int,
  _ body: (Builtin.RawPointer) throws -> R
) rethrows -> R {
  let result: MyLittleResult<R, Error>
#if $BuiltinUnprotectedStackAlloc
  let stackAddress = Builtin.unprotectedStackAlloc(
    capacity._builtinWordValue,
    MyLittleLayout<T>.stride._builtinWordValue,
    alignment._builtinWordValue
  )
#else
  let stackAddress = Builtin.stackAlloc(
    capacity._builtinWordValue,
    MyLittleLayout<T>.stride._builtinWordValue,
    alignment._builtinWordValue
  )
#endif
  do {
    result = .success(try body(stackAddress))
    Builtin.stackDealloc(stackAddress)
  } catch {
    result = .failure(error)
    Builtin.stackDealloc(stackAddress)
  }
  switch consume result {
  // FIXME: This shouldn't be diagnosed.  But it's better than miscompiling.
  case .success(let success): return success // expected-error{{cannot partially consume 'unknown'}}
  case .failure(let error): return try _rethrowsViaClosure { throw error }
  }
}
