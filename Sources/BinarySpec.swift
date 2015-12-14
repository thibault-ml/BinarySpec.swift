/*

Copyright 2015 HiHex Ltd.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in
compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is
distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied. See the License for the specific language governing permissions and limitations under the
License.

*/

import Dispatch

// MARK: - Partial

public struct IncompleteError: ErrorType {
    public let requestedCount: Int

    public func asPartial<T>() -> Partial<T> {
        return .Incomplete(requesting: requestedCount)
    }
}

/// Represents the result of reading from a partial data stream.
public enum Partial<T: Equatable>: Equatable {
    /// Reading is succesful. The associated member contains the reading result.
    case Ok(T)

    /// Not enough data to read. The associated member provides at least how many more bytes are
    /// needed to complete the read.
    case Incomplete(requesting: Int)

    /// Returns the wrapped object if it is `.Done`. Throws `IncompleteError` if it is `.Incomplete`.
    public func unwrap() throws -> T {
        switch self {
        case let .Ok(a):
            return a
        case let .Incomplete(n):
            throw IncompleteError(requestedCount: n)
        }
    }
}

public func ==<T>(left: Partial<T>, right: Partial<T>) -> Bool {
    switch (left, right) {
    case let (.Ok(l), .Ok(r)):
        return l == r
    case let (.Incomplete(l), .Incomplete(r)):
        return l == r
    default:
        return false
    }
}

// MARK: - dispatch_data_t

/// Creates a "destructor" that retains the object in the function. This allows the raw pointers 
/// supplied by the object be valid before the destructor is called.
private func retaining<T>(obj: T?) -> dispatch_block_t {
    var retained = obj
    return { _ in
        _ = retained // silence the warning
        retained = nil
    }
}

/// Extends an array slice to the end of the dispatch data.
public func +=(inout data: dispatch_data_t, slice: ArraySlice<UInt8>) {
    let newData = slice.withUnsafeBufferPointer { buffer in
        dispatch_data_create(buffer.baseAddress, buffer.count, dispatch_get_main_queue(), retaining(slice))
    }
    data = dispatch_data_create_concat(data, newData)
}

/// Extends another dispatch data to the end of this data. Equivalent to calling
/// `dispatch_data_create_concat`.
public func +=(inout data: dispatch_data_t, other: dispatch_data_t) {
    data = dispatch_data_create_concat(data, other)
}

extension dispatch_data_t {
    /// Gets the byte length of this data.
    public var count: Int {
        return dispatch_data_get_size(self)
    }

    public var isEmpty: Bool {
        return dispatch_data_get_size(self) == 0
    }

    /// Splits the data into two parts. The first data has exactly *n* bytes.
    ///
    /// - Throws:
    ///   IncompleteError if `n > count`
    public func splitAt(n: Int) throws -> (dispatch_data_t, dispatch_data_t) {
        let suffixLength = count - n
        guard suffixLength >= 0 else { throw IncompleteError(requestedCount: -suffixLength) }

        let prefix = dispatch_data_create_subrange(self, 0, n)
        let suffix = dispatch_data_create_subrange(self, n, suffixLength)
        return (prefix, suffix)
    }

    public func resized(n: Int) -> dispatch_data_t {
        switch count {
        case 0 ..< n:
            let zeros = createDataWithZeros(n - count)
            return dispatch_data_create_concat(self, zeros)
        case n:
            return self
        default:
            return dispatch_data_create_subrange(self, 0, n)
        }
    }
}

/// Linearizes this dispatch data. If the data was originally discontinuous, a new piece of 
/// contiguous data will be created by copying all parts together.
///
/// - Returns:
///   An unsafe buffer pointing to the raw data. This is only valid while the data itself is alive.
public func linearize(inout data: dispatch_data_t) -> UnsafeBufferPointer<UInt8> {
    var ptr: UnsafePointer<Void> = nil
    var size: Int = 0
    data = dispatch_data_create_map(data, &ptr, &size)
    return UnsafeBufferPointer(start: UnsafePointer(ptr), count: size)
}

/// Creates a piece of data filled with zeros.
public func createDataWithZeros(n: Int) -> dispatch_data_t {
    return createData([UInt8](count: n, repeatedValue: 0))
}

/// Creates a piece of data from an array.
public func createData(array: [UInt8]) -> dispatch_data_t {
    return array.withUnsafeBufferPointer { buffer in
        dispatch_data_create(buffer.baseAddress, buffer.count, dispatch_get_main_queue(), retaining(array))
    }
}


/// Extends an array from some dispatch data.
///
/// - Complexity:
///   O("2N"). The data will be copied *twice*.
public func +=(inout left: [UInt8], right: dispatch_data_t) {
    var right = right
    let buffer = linearize(&right)
    left.appendContentsOf(buffer)
    // ^ is this efficient enough?
}

extension SequenceType where Generator.Element: dispatch_data_t {
    public func concat() -> dispatch_data_t {
        return reduce(dispatch_data_empty) { dispatch_data_create_concat($0, $1) }
    }
}

// MARK: - IntSpec

private let DISPATCH_DATA_DESTRUCTOR_DEFAULT: dispatch_block_t? = nil

/** Specification for an integer type. This structure defines how an integer is encoded in binary. */
public struct IntSpec: Equatable {
    /** Length of integer. Normally should be 1, 2, 4 or 8. */
    public let length: Int

    /** Endian of the integer when encoded. */
    public let endian: CFByteOrder

    /** Specification of a byte (8-bit unsigned integer). */
    public static let Byte = IntSpec(length: 1, endian: NSHostByteOrder())
    /** Specification of a big-endian 16-bit unsigned integer. */
    public static let UInt16BE = IntSpec(length: 2, endian: NS_BigEndian)
    /** Specification of a little-endian 16-bit unsigned integer. */
    public static let UInt16LE = IntSpec(length: 2, endian: NS_LittleEndian)
    /** Specification of a big-endian 24-bit unsigned integer. */
    public static let UInt24BE = IntSpec(length: 3, endian: NS_BigEndian)
    /** Specification of a little-endian 24-bit unsigned integer. */
    public static let UInt24LE = IntSpec(length: 3, endian: NS_LittleEndian)
    /** Specification of a big-endian 32-bit unsigned integer. */
    public static let UInt32BE = IntSpec(length: 4, endian: NS_BigEndian)
    /** Specification of a little-endian 32-bit unsigned integer. */
    public static let UInt32LE = IntSpec(length: 4, endian: NS_LittleEndian)
    /** Specification of a big-endian 64-bit unsigned integer. */
    public static let UInt64BE = IntSpec(length: 8, endian: NS_BigEndian)
    /** Specification of a little-endian 64-bit unsigned integer. */
    public static let UInt64LE = IntSpec(length: 8, endian: NS_LittleEndian)

    /// Encodes an integer into a data.
    public func encode(integer: UIntMax) -> dispatch_data_t {
        var prepared: UIntMax
        switch endian {
        case NS_BigEndian:
            let bitShift = (sizeof(UIntMax) - length) * 8
            prepared = (integer << UIntMax(bitShift)).bigEndian
            break
        default:
            prepared = integer.littleEndian
            break
        }
        return withUnsafePointer(&prepared) {
            return dispatch_data_create(UnsafePointer($0), length, dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT)
        }
    }
}

public func ==(left: IntSpec, right: IntSpec) -> Bool {
    return left.length == right.length && left.endian == right.endian
}

extension dispatch_data_t {
    /// Decodes the content of this queue as integer using the given specification.
    ///
    /// - Precondition:
    ///   self.count * sizeof(Generator.Element) >= spec.length
    public func toUIntMax(spec: IntSpec) -> UIntMax {
        assert(count >= spec.length)

        var result: UIntMax = 0

        var subrange: dispatch_data_t = dispatch_data_create_subrange(self, 0, spec.length)
        let buffer = linearize(&subrange)

        memcpy(&result, buffer.baseAddress, spec.length)

        switch spec.endian {
        case NS_BigEndian:
            let bitShift = (sizeof(UIntMax) - spec.length) * 8
            return UIntMax(bigEndian: result) >> UIntMax(bitShift)
        default:
            return UIntMax(littleEndian: result)
        }
    }
}

// MARK: - BinaryData

/// The parsed binary data.
public indirect enum BinaryData: Equatable {
    /// No data.
    case Empty

    /// An error value that indicates parsing has been stopped at the outermost level. The whole
    /// structure would become invalid since the future length information would be corrupted. The
    /// `.Stop` data is silently hidden inside an `.Until` spec.
    ///
    /// - Parameters:
    ///   - 0: The specification that caused the error.
    ///   - 1: The value in the data stream, if any, which caused the specification to reject it.
    case Stop(BinarySpec, UIntMax)

    /// A parsed integer.
    case Integer(UIntMax)

    /// Raw bytes.
    case Bytes(dispatch_data_t)

    /// Sequence of more data.
    case Seq([BinaryData])

    /// Whether this is a "stop" data.
    public var isStop: Bool {
        if case .Stop = self {
            return true
        } else {
            return false
        }
    }

    /// Access to an indexed item in the data, assuming it is a sequence.
    public subscript(index: Int) -> BinaryData {
        return seq[index]
    }

    public var integer: UIntMax {
        guard case let .Integer(a) = self else { fatalError() }
        return a
    }

    public var bytes: dispatch_data_t {
        guard case let .Bytes(a) = self else { fatalError() }
        return a
    }

    public var seq: [BinaryData] {
        guard case let .Seq(a) = self else { fatalError() }
        return a
    }
}

public func ==(left: BinaryData, right: BinaryData) -> Bool {
    switch (left, right) {
    case (.Empty, .Empty):
        return true
    case let (.Integer(a), .Integer(b)):
        return a == b
    case let (.Bytes(a), .Bytes(b)):
        var a = a
        var b = b
        let ab = linearize(&a)
        let bb = linearize(&b)
        return ab.count == bb.count && memcmp(ab.baseAddress, bb.baseAddress, ab.count) == 0
        // ^ TODO: Don't copy when comparing.
    case let (.Seq(a), .Seq(b)):
        return a == b
    case let (.Stop(a, c), .Stop(b, d)):
        return a == b && c == d
    default:
        return false
    }
}

// MARK: - BinarySpec

/// Type of a variable name.
public typealias VariableName = String

/// An intermediate error thrown when a `.Stop` spec is encountered.
private struct StopParsingError: ErrorType {
    let spec: BinarySpec
    let value: UIntMax

    func toBinaryData() -> BinaryData {
        return .Stop(spec, value)
    }
}

/// A specification of how a raw binary data stream should be parsed.
public indirect enum BinarySpec: Equatable {
    /// Reads _n_ bytes and ignore the result. Decodes to `BinaryData.Empty`. When encoded, this
    /// field will generate zeros.
    case Skip(Int)

    /// Immediately stop reading this data stream. This will propagate until an `.Until` 
    /// specification.
    case Stop

    /// Integer. Decodes to `BinaryData.Integer`.
    case Integer(IntSpec)

    /// Integer variable. The variable name should be used to define the length of some dynamic
    /// structures later. Decodes to `BinaryData.Integer`.
    ///
    /// - Warning: 
    ///   Refering to a variable before it is defined will cause `fatalError`.
    case Variable(IntSpec, VariableName)

    /// Dynamic bytes. Uses the content of a variable as the length, then reads the corresponding
    /// number of bytes. Decodes to `BinaryData.Bytes`.
    case Bytes(VariableName)

    /// Sequence of sub-specifications. Decodes to `BinaryData.Seq`.
    case Seq([BinarySpec])

    /// Repeated data with a given length. Uses the content of a variable as the length of data,
    /// then repeats the sub-specification until the length runs out. Decodes to `BinaryData.Seq`.
    case Until(VariableName, BinarySpec)

    /// Repeated data with a given count. Then repeats the sub-specification exactly *n* times, 
    /// where *n* is given by the variable. Decodes to `BinaryData.Seq`.
    case Repeat(VariableName, BinarySpec)

    /// Enumerated cases.
    ///
    /// - Parameters:
    ///   - selector: 
    ///     The variable that introduces the case to select.
    ///   - cases:
    ///     How to react according to different selectors. 
    ///   - default:
    ///     The default case when none of the cases match. Supply `.Stop` here if no default case
    ///     is expected.
    case Switch(selector: VariableName, cases: [UIntMax: BinarySpec], `default`: BinarySpec)

    /// Parses a format string into a specification. The format language is as following:
    ///
    /// <table>
    /// <tr><th>Character<th>Meaning
    /// <tr><td>&gt;<td>Switch to big-endian for all following integer types
    /// <tr><td>&lt;<td>Switch to little-endian for all following integer types
    /// <tr><td>B<td>Reads a byte
    /// <tr><td>H<td>Reads a 16-bit (2-byte) integer
    /// <tr><td>T<td>Reads a 24-bit (3-byte) integer
    /// <tr><td>I<td>Reads a 32-bit (4-byte) integer
    /// <tr><td>Q<td>Reads a 64-bit (8-byte) integer
    /// <tr><td><var>6</var><var>Q</var><td>Repeats the integer <var>Q</var> for <var>6</var> times.
    /// <tr><td><var>24</var>x<td>Skips <var>24</var> bytes
    /// <tr><td>%<var>Q</var><td>Defines a variable for integer type <var>Q</var>
    /// <tr><td>s<td>Reads a <tt>.Bytes</tt>. The first unused variable will be used for the length.
    /// <tr><td>(…)<td>Reads an <tt>.Until</tt>
    /// <tr><td>{ 0xff=…, 0x100=…, *=… }<td>Reads a <tt>.Switch</tt>
    /// </table>
    ///
    /// For instance, the ADB packet can be represented as
    ///
    ///     "<3I%I2Is"
    ///
    /// while the HTTP/2 frame can be written as
    ///
    ///     ">%TBBIs"
    ///
    /// All integers can be decimal (`123`) or hexadecimal (`0x7fe`). The format string is
    /// case-insensitive. Whitespaces will be ignored.
    public init(parse string: String, variablePrefix: String = "") {
        let parser = BinarySpecParser(variablePrefix: variablePrefix)
        parser.parse(string)
        self = parser.spec
    }
}

public func ==(left: BinarySpec, right: BinarySpec) -> Bool {
    switch (left, right) {
    case let (.Skip(a), .Skip(b)):
        return a == b
    case (.Stop, .Stop):
        return true
    case let (.Integer(a), .Integer(b)):
        return a == b
    case let (.Variable(a, c), .Variable(b, d)):
        return a == b && c == d
    case let (.Bytes(a), .Bytes(b)):
        return a == b
    case let (.Seq(a), .Seq(b)):
        return a == b
    case let (.Until(a, c), .Until(b, d)):
        return a == b && c == d
    case let (.Repeat(a, c), .Repeat(b, d)):
        return a == b && c == d
    case let (.Switch(a, c, e), .Switch(b, d, f)):
        return a == b && c == d && e == f
    default:
        return false
    }
}

// MARK: - IncompleteBinaryData

/// An intermediate state when a BinarySpec is being parsed into BinaryData.
private indirect enum IncompleteBinaryData {
    /// Reading not started yet.
    case Prepared(BinarySpec)

    /// Everything has been read.
    case Done(BinaryData)

    /// Partial sequence.
    case PartialSeq(done: [BinaryData], remaining: ArraySlice<BinarySpec>)

    /// Partial specification repetition.
    case PartialRepeat(done: [BinaryData], remaining: UIntMax, spec: BinarySpec)

    /// Append a data to a partial sequence. Fails if this is not `.Partial*`.
    func fillHole(data: BinaryData) -> IncompleteBinaryData {
        switch self {
        case let .PartialSeq(done, remaining):
            var newDone = done
            newDone.append(data)
            return .PartialSeq(done: newDone, remaining: remaining)

        case let .PartialRepeat(done, remaining, spec):
            var newDone = done
            newDone.append(data)
            return .PartialRepeat(done: newDone, remaining: remaining, spec: spec)

        default:
            fatalError("Should not fill in \(data) into \(self)")
        }
    }

    /// Obtains the data in stored in this structure, even if not all of them are complete.
    var data: BinaryData {
        switch self {
        case .Prepared:
            return .Empty
        case let .Done(b):
            return b
        case let .PartialSeq(done, _):
            return .Seq(done)
        case let .PartialRepeat(done, _, _):
            return .Seq(done)
        }
    }
}

// MARK: - BinaryParser

private enum BinaryParserNextAction {
    case Continue
    case Done
}

/// A parser that reads a byte stream, and decodes into BinaryData, according to the rules in a 
/// provided BinarySpec.
@objc public class BinaryParser: NSObject {
    private let initialSpec: BinarySpec
    private var incompleteDataStack: [IncompleteBinaryData] = []
    private var variables: [VariableName: UIntMax] = [:]
    private var data = dispatch_data_empty

    /// Initialize the parser using a specification.
    public init(_ spec: BinarySpec) {
        initialSpec = spec
        super.init()
        resetStates()
    }

    /// Provide more data to the parser.
    public func supply(data: dispatch_data_t) {
        self.data += data
    }

    /// Provide more data to the parser.
    public func supply(data: ArraySlice<UInt8>) {
        self.data += data
    }

    /// Provide more data to the parser.
    public func supply(data: [UInt8]) {
        self.data += ArraySlice(data)
    }

    /// Obtains the remaining bytes not yet parsed.
    public var remaining: dispatch_data_t {
        return data
    }

    /// Performs a parsing step using as many bytes available as possible.
    ///
    /// - Returns:
    ///   On succeed, returns `.Ok` containing the parsed data. If there is not enough bytes
    ///   available, returns `.Incomplete` indicating at least how much bytes are needed to proceed
    ///   to the next step.
    @warn_unused_result
    public func next() -> Partial<BinaryData> {
        while true {
            do {
                switch try step() {
                case .Ok(.Done):
                    assert(incompleteDataStack.count == 1)
                    return .Ok(incompleteDataStack.last!.data)
                case .Ok(.Continue):
                    continue
                case let .Incomplete(count):
                    return .Incomplete(requesting: count)
                }
            } catch let e as StopParsingError {
                let errorData = e.toBinaryData()
                incompleteDataStack = [.Done(errorData)]
                return .Ok(errorData)
            } catch {
                fatalError("Unexepected error being thrown")
            }
        }
    }

    /// Resets the parsing states. This allows the parser to accept more data or parse the remaining
    /// bytes using the initial specification again.
    public func resetStates() {
        incompleteDataStack = [.Prepared(initialSpec)]
        variables = [:]
    }

    /// Parses all the bytes available. If the bytes are long enough to provide multiple BinaryData,
    /// all of them will be returned from this method.
    public func parseAll() -> [BinaryData] {
        var result: [BinaryData] = []
        while case let .Ok(data) = next() where !data.isStop {
            result.append(data)
            resetStates()
        }
        return result
    }

    /// Performs an atomic parsing step.
    @warn_unused_result
    private func step() throws -> Partial<BinaryParserNextAction> {
        let lastState = incompleteDataStack.removeLast()

        do {
            switch lastState {
            case .Done:
                assert(incompleteDataStack.isEmpty)
                incompleteDataStack.append(lastState)
                return .Ok(.Done)

            case let .Prepared(.Skip(n)):
                try read(n)
                return .Ok(pushState(.Empty))

            case let .Prepared(.Integer(spec)):
                let data = try read(spec.length)
                let integer = data.toUIntMax(spec)
                return .Ok(pushState(.Integer(integer)))

            case let .Prepared(.Variable(spec, name)):
                let data = try read(spec.length)
                let integer = data.toUIntMax(spec)
                variables[name] = integer
                return .Ok(pushState(.Integer(integer)))

            case let .Prepared(.Bytes(name)):
                let length = Int(variables[name]!)
                let data = try read(length)
                return .Ok(pushState(.Bytes(data)))

            case let .Prepared(.Seq(specs)):
                if let firstSpec = specs.first {
                    let remainingSpecs = specs.suffixFrom(specs.startIndex.successor())
                    incompleteDataStack.append(.PartialSeq(done: [], remaining: remainingSpecs))
                    incompleteDataStack.append(.Prepared(firstSpec))
                    return .Ok(.Continue)
                } else {
                    return .Ok(pushState(.Seq([])))
                }

            case let .PartialSeq(done, remaining):
                if let firstSpec = remaining.first {
                    let remainingSpecs = remaining.suffixFrom(remaining.startIndex.successor())
                    incompleteDataStack.append(.PartialSeq(done: done, remaining: remainingSpecs))
                    incompleteDataStack.append(.Prepared(firstSpec))
                    return .Ok(.Continue)
                } else {
                    return .Ok(pushState(.Seq(done)))
                }

            case let .Prepared(.Repeat(name, spec)):
                let count = variables[name]!
                incompleteDataStack.append(.PartialRepeat(done: [], remaining: count, spec: spec))
                incompleteDataStack.append(.Prepared(spec))
                return .Ok(.Continue)

            case let .PartialRepeat(done, remaining, spec):
                if remaining > 0 {
                    incompleteDataStack.append(.PartialRepeat(done: done, remaining: remaining - 1, spec: spec))
                    incompleteDataStack.append(.Prepared(spec))
                    return .Ok(.Continue)
                } else {
                    return .Ok(pushState(.Seq(done)))
                }

            case let .Prepared(.Switch(name, cases, def)):
                let selector = variables[name]!
                let chosen = cases[selector] ?? def
                if case .Stop = chosen {
                    let spec = BinarySpec.Switch(selector: name, cases: cases, `default`: def)
                    throw StopParsingError(spec: spec, value: selector)
                } else {
                    incompleteDataStack.append(.Prepared(chosen))
                    return .Ok(.Continue)
                }

            case let .Prepared(.Until(name, spec)):
                let length = Int(variables[name]!)
                let data = try read(length)
                let subparser = BinaryParser(spec)
                subparser.supply(data)
                let result = subparser.parseAll()
                return .Ok(pushState(.Seq(result)))

            case .Prepared(.Stop):
                // No need to restore the stack, we will abandon everything anyway.
                throw StopParsingError(spec: .Stop, value: 0)
            }
        } catch let e as IncompleteError {
            incompleteDataStack.append(lastState)
            return e.asPartial()
        }
    }

    /// Fill in any completed "BinaryData" hole in the partial state.
    private func pushState(data: BinaryData) -> BinaryParserNextAction {
        if incompleteDataStack.isEmpty {
            incompleteDataStack.append(.Done(data))
            return .Done
        } else {
            let lastIndex = incompleteDataStack.endIndex.predecessor()
            let lastItem = incompleteDataStack[lastIndex]
            let filledItem = lastItem.fillHole(data)
            incompleteDataStack[lastIndex] = filledItem
            return .Continue
        }
    }

    private func read(n: Int) throws -> dispatch_data_t {
        let (prefix, suffix) = try data.splitAt(n)
        data = suffix
        return prefix
    }
}

// MARK: - BinaryEncoder

@objc public class BinaryEncoder: NSObject {
    private let spec: BinarySpec
    private var variables: [VariableName: UIntMax] = [:]

    public init(_ spec: BinarySpec) {
        self.spec = spec
    }

    public func encode(data: BinaryData) -> dispatch_data_t {
        variables = [:]
        return encodeRecursively(spec, data)
    }

    private func encodeRecursively(spec: BinarySpec, _ data: BinaryData) -> dispatch_data_t {
        switch (spec, data) {
        case let (.Skip(n), .Empty):
            return createDataWithZeros(n)

        case let (.Integer(spec), .Integer(val)):
            return spec.encode(val)

        case let (.Variable(spec, name), .Integer(val)):
            variables[name] = val
            return spec.encode(val)

        case let (.Bytes(name), .Bytes(q)):
            let expectedCount = Int(variables[name]!)
            if expectedCount != q.count {
                fatalError("Expecting to encode \(expectedCount) bytes, but the provided data is \(q.count) bytes long")
            }
            return q

        case let (.Seq(specs), .Seq(datas)) where specs.count == datas.count:
            return zip(specs, datas).lazy.map(encodeRecursively).concat()

        case let (.Until(name, subspec), .Seq(datas)):
            let length = Int(variables[name]!)
            return datas.lazy.map { self.encodeRecursively(subspec, $0) }.concat().resized(length)

        case let (.Repeat(name, subspec), .Seq(datas)):
            let count = Int(variables[name]!)
            if count != datas.count {
                fatalError("Expecting exactly \(count) items to encode \(spec), got \(datas.count) items in \(data) instead.")
            }
            return datas.lazy.map { self.encodeRecursively(subspec, $0) }.concat()

        case let (.Switch(name, cases, def), _):
            let selector = variables[name]!
            let chosen = cases[selector] ?? def
            return encodeRecursively(chosen, data)

        default:
            fatalError("Cannot use \(spec) to encode \(data)")
        }
    }
}
