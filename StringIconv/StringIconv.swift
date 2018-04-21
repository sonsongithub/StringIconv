//
//  StringIconv.swift
//  StringIconv
//
//  Created by Yuichi Yoshida on 2017/12/16.
//  Copyright © 2017年 Yuichi Yoshida. All rights reserved.
//

import Swift

#if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
    import Darwin.POSIX.iconv
    import Foundation
#elseif os(Linux)
    import Glibc
    import SwiftGlibc.POSIX.iconv
    import SwiftGlibc.C.errno
#endif

/// Buffer length of the bytes array to be passed to iconv.
private let iconvBufferLength = 2048
/// The name of encodings of bytes array to be passed to `String`.
private let defaultEncodingName = "UTF-16"

/**
 Error by StringIconv
 */
public enum IconvError: Error {
    /// `iconv_open` failed because an invalid encoding name has been passed.
    case invalidEncodingName
    /// `iconv` failed because an invalid multi byte sequence was found at location.
    case invalidMultiByteSequence(location: Int)
    /// `iconv` failed because an incomplete multi byte sequence was found at location.
    case incompleteMultiByteSequence(location: Int)
    /// Unknown error and ecode.
    case unknownError(code: Int32)
    /// Decoding error. This error is not caused by `iconv`.
    case decodeError
}

public enum IconvInternlEncoding {
    case utf16
    case utf16BigEndian
    case utf16LittleEndian
    
    var stringEncoding: String.Encoding {
        switch self {
        case .utf16:
            return String.Encoding.utf16
        case .utf16BigEndian:
            return String.Encoding.utf16BigEndian
        case .utf16LittleEndian:
            return String.Encoding.utf16LittleEndian
        }
    }
}

extension IconvError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidEncodingName:
            return "Can not open iconv handle. An invalid encoding name has been passed."
        case .invalidMultiByteSequence(let location):
            return "An invalid multibyte sequence has been encountered at \(location)-th code among the input."
        case .incompleteMultiByteSequence(let location):
            return "An incomplete multibyte sequence has been encountered at \(location)-th code among the input."
        case .unknownError(let code):
            return "Unknown error: code \(code)."
        case .decodeError:
            return "String class can not decode a binary data which is encoded by iconv. StringIconv.framework is not responsible for this error?"
        }
    }
}

/* Listing of locale independent encodings. */
/**
 This method is called back by `iconvlist`.
 Third argument must be the pointer to an array of `String`.
 This method adds the encoding name which is passed from `iconvlist` to the array.
 */
private func process_iconvlist(namescount: UInt32, names: UnsafePointer<UnsafePointer<Int8>?>?, data: UnsafeMutableRawPointer?) -> Int32 {
    let array = data!.assumingMemoryBound(to: [String].self)
    guard let names = names else { return -1 }
    for i in 0..<namescount {
        guard let namePointer = names[Int(i)] else { return -1 }
        guard let name = String(validatingUTF8:namePointer) else { return -1 }
        array.pointee.append(name)
    }
    return 0
}

/**
 This method is called back by `iconvlist`.
 Third argument must be the pointer to an array of `String`.
 This method adds the canonical encoding name which is passed from `iconvlist` to the array.
 */
private func process_canonical_iconvlist(namescount: UInt32, names: UnsafePointer<UnsafePointer<Int8>?>?, data: UnsafeMutableRawPointer?) -> Int32 {
    let array = data!.assumingMemoryBound(to: [String].self)
    guard let names = names else { return -1 }
    for i in 0..<namescount {
        guard let namePointer = names[Int(i)] else { return -1 }
        guard let canonicalNamePointer = iconv_canonicalize(namePointer) else { return -1 }
        guard let canonicalName = String(validatingUTF8:canonicalNamePointer) else { return -1 }
        array.pointee.append(canonicalName)
    }
    return 0
}

extension String {

    /**
     Listing of locale independent encodings as an array of `String`.
     */
    public static var iconvlist: [String] {
        var list: [String] = []
        let array = withUnsafeMutablePointer(to: &list.self) {
            return UnsafeMutableRawPointer($0)
        }
        Darwin.iconvlist(process_iconvlist, array)
        return list
    }
    
    /**
     Listing of canonical name of the locale independent encodings as an array of `String`.
     */
    public static var canonicalIconvlist: [String] {
        var list: [String] = []
        let array = withUnsafeMutablePointer(to: &list.self) {
            return UnsafeMutableRawPointer($0)
        }
        Darwin.iconvlist(process_canonical_iconvlist, array)
        return Array(Set(list))
    }
    
    /**
     Decode `Data` object to `String` using iconv directly.
     
     - parameter data: `Data` object to be decoded.
     - parameter toCode: The character encoding of String to be output.
     - parameter fromCode: The character encoding of bytes array to be decoded.
     - parameter discardIllegalSequence: Enables transliteration.
     - parameter transliterate: Determines if illegal sequences are discarded or not.
     - returns: Data which includes bytes array.
     */
    public static func decode(pointer: UnsafePointer<Int8>, count: Int, toCode: String, fromCode: String, discardIllegalSequence: Bool = false, transliterate: Bool = false) throws -> Data {
        let conversionDescriptor: iconv_t = iconv_open(toCode, fromCode)
        
        /// Check whether iconv could open a conversion descriptor.
        guard Int(bitPattern: conversionDescriptor) != -1 else { throw IconvError.invalidEncodingName }
        
        if transliterate {
            var value = 1
            iconvctl(conversionDescriptor, ICONV_SET_TRANSLITERATE, &value)
        }
        if discardIllegalSequence {
            var value = 1
            iconvctl(conversionDescriptor, ICONV_SET_DISCARD_ILSEQ, &value)
        }
        
        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: iconvBufferLength)
        defer { buffer.deallocate() }
        
        var inBytesLeft = Int(count)
        var inBuf: UnsafeMutablePointer<Int8>? = UnsafeMutablePointer<Int8>(mutating: pointer)
        
        var outputData = Data()
        
        repeat {
            var outBuf: UnsafeMutablePointer<Int8>? = buffer
            var outBytesLeft = iconvBufferLength
            
            /* Converts, using conversion descriptor `cd', at most `*inbytesleft' bytes
             starting at `*inbuf', writing at most `*outbytesleft' bytes starting at
             `*outbuf'.
             Decrements `*inbytesleft' and increments `*inbuf' by the same amount.
             Decrements `*outbytesleft' and increments `*outbuf' by the same amount. */
            let iconvStatus = iconv(conversionDescriptor, &inBuf, &inBytesLeft, &outBuf, &outBytesLeft)
            let errorLocation = outputData.count + (iconvBufferLength - outBytesLeft)
            //failed
            if iconvStatus == -1 {
                switch errno {
                case EILSEQ:
                    throw IconvError.invalidMultiByteSequence(location: errorLocation)
                case E2BIG:
                    do {}
                case EINVAL:
                    throw IconvError.incompleteMultiByteSequence(location: errorLocation)
                default:
                    throw IconvError.unknownError(code: errno)
                }
            }
            let pp: UnsafeMutablePointer<UInt8> = buffer.withMemoryRebound(to: UInt8.self, capacity: (iconvBufferLength - outBytesLeft), {
                return $0
            })
            outputData.append(pp, count: iconvBufferLength - outBytesLeft)
        } while inBytesLeft > 0
        
        iconv_close(conversionDescriptor)
        
        return outputData
    }
    
    /**
     Decode a byte array to `String` using iconv directly.
     If you want to control whether `String` has BOM, change value of `internalEncoding`.
     
     - parameter pointer: Pointer to bytes array to be decoded.
     - parameter count: Count of the bytes array to be decoded.
     - parameter internalEncoding: The character encoding as `String.Encoding` which is used to convert bytes array to `String` object. Default value is .utf16.
     - parameter fromCode: The character encoding of bytes array to be decoded.
     - parameter discardIllegalSequence: Enables transliteration.
     - parameter transliterate: Determines if illegal sequences are discarded or not.
     - returns: String.
     */
    public static func decode(pointer: UnsafePointer<Int8>, count: Int, internalEncoding: IconvInternlEncoding = .utf16, fromCode: String, discardIllegalSequence: Bool = false, transliterate: Bool = false) throws -> String {
        let outputData: Data = try String.decode(pointer: pointer, count: count, toCode: defaultEncodingName, fromCode: fromCode, discardIllegalSequence: discardIllegalSequence, transliterate: transliterate)
        guard let decoded = String(data: outputData, encoding: internalEncoding.stringEncoding) else { throw IconvError.decodeError }
        return decoded
    }
    
    /**
     Decode `Data` object to `String` using iconv directly.
     
     - parameter data: `Data` object to be decoded.
     - parameter fromCode: The character encoding of bytes array to be decoded.
     - parameter discardIllegalSequence: Enables transliteration.
     - parameter transliterate: Determines if illegal sequences are discarded or not.
     - returns: Data.
     */
    static func decode(data: Data, toCode: String, fromCode: String, discardIllegalSequence: Bool = false, transliterate: Bool = false) throws -> Data {
        return try data.withUnsafeBytes({ (pointer: UnsafePointer<Int8>) throws -> Data in
            return try String.decode(pointer: pointer, count: data.count, toCode: toCode, fromCode: fromCode, discardIllegalSequence: discardIllegalSequence, transliterate: transliterate)
        })
    }
    
    /**
     Decode `Data` object to `String` using iconv directly.
     If you want to control whether `String` has BOM, change value of `internalEncoding`.
     
     - parameter data: `Data` object to be decoded.
     - parameter internalEncoding: The character encoding as `String.Encoding` which is used to convert bytes array to `String` object. Default value is .utf16.
     - parameter fromCode: The character encoding of bytes array to be decoded.
     - parameter discardIllegalSequence: Enables transliteration.
     - parameter transliterate: Determines if illegal sequences are discarded or not.
     - returns: String.
     */
    static func decode(data: Data, internalEncoding: IconvInternlEncoding = .utf16, fromCode: String, discardIllegalSequence: Bool = false, transliterate: Bool = false) throws -> String {
        return try data.withUnsafeBytes({ (pointer: UnsafePointer<Int8>) throws -> String in
            return try decode(pointer: pointer, count: data.count, internalEncoding: internalEncoding, fromCode: fromCode, discardIllegalSequence: discardIllegalSequence, transliterate: transliterate)
        })
    }
}

