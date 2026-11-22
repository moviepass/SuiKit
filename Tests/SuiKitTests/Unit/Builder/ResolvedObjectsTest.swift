import Foundation
import XCTest
@testable import SuiKit

final class ResolvedObjectsTest: XCTestCase {
    private func ref(_ byte: UInt8) -> SuiObjectRef {
        SuiObjectRef(
            objectId: String(repeating: String(format: "%02x", byte), count: 32),
            version: "1",
            digest: ([UInt8](repeating: byte, count: 32)).base58EncodedString
        )
    }

    private func owned(_ index: UInt16, receiving: Bool = false) -> ObjectsToResolve {
        let ref = ref(UInt8(index))
        let arg: ObjectArg = receiving ? .receiving(ReceivingObject(ref: ref)) : .immOrOwned(ImmOrOwned(ref: ref))
        return ObjectsToResolve(
            id: ref.objectId,
            input: TransactionBlockInput(index: index, value: .callArg(Input(type: .object(arg))))
        )
    }

    private func shared(_ index: UInt16, mutable: Bool) -> ObjectsToResolve {
        let id = String(repeating: "ab", count: 32)
        return ObjectsToResolve(
            id: id,
            input: TransactionBlockInput(
                index: index,
                value: .callArg(Input(type: .object(.shared(SharedObjectArg(objectId: id, initialSharedVersion: 1, mutable: mutable)))))
            )
        )
    }

    private func isReceiving(_ object: ObjectsToResolve?) -> Bool {
        guard case .callArg(let input)? = object?.input.value,
              case .object(.receiving) = input.inputType else { return false }
        return true
    }

    /// Inputs that resolve out of order must not overwrite each other.
    func testThatOutOfOrderInputsKeepTheirOwnEntries() {
        var resolved: [UInt16: ObjectsToResolve] = [:]
        TransactionBlock.storeResolvedObject(owned(5, receiving: true), in: &resolved)
        TransactionBlock.storeResolvedObject(owned(3), in: &resolved)
        TransactionBlock.storeResolvedObject(owned(1), in: &resolved)

        XCTAssertEqual(resolved.keys.sorted(), [1, 3, 5])
        XCTAssertTrue(isReceiving(resolved[5]))
        XCTAssertFalse(isReceiving(resolved[3]))
        XCTAssertEqual(resolved[3]?.input.index, 3)
        XCTAssertEqual(resolved[1]?.input.index, 1)
    }

    /// A shared object stays mutable if any use of the same input needs it mutable.
    func testThatSharedObjectStaysMutableAcrossUses() {
        var resolved: [UInt16: ObjectsToResolve] = [:]
        TransactionBlock.storeResolvedObject(shared(2, mutable: true), in: &resolved)
        TransactionBlock.storeResolvedObject(shared(2, mutable: false), in: &resolved)

        guard case .callArg(let input)? = resolved[2]?.input.value else { return XCTFail("missing input 2") }
        XCTAssertTrue(input.isMutableSharedObjectInput())
        XCTAssertEqual(resolved.count, 1)
    }
}
