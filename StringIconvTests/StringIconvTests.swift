//
//  StringIconvTests.swift
//  StringIconvTests
//
//  Created by sonson on 2017/12/18.
//  Copyright © 2017年 sonson. All rights reserved.
//

import XCTest
@testable import StringIconv

class StringIconvTests: XCTestCase {
    let bundle: Bundle = Bundle(for: StringIconvTests.self)
    
    /**
     Character encoding test using infinity symbol.
     Original code is produced by `MaddTheSane`.
     https://github.com/MaddTheSane/SwiftIconV
     */
    func testInfinitySymbol() {
        let infinity = "∞"
        let macOSRoman: [Int8] = [-80]
        let sjis: [Int8] = [-127, -121]
        let euc_JP: [Int8] = [-95, -25]
        let utf8: [Int8] = [-30, -120, -98]
        let ISO2022JP: [Int8] = [27, 36, 66, 33, 103, 27, 40, 66]
        let strsAndEnc: [(encodingName: String, cStr: [Int8])] = [("MACROMAN", macOSRoman),
                                                                  ("SJIS", sjis),
                                                                  ("EUC-JP", euc_JP),
                                                                  ("UTF-8", utf8),
                                                                  ("ISO-2022-JP", ISO2022JP)]
        for (enc, cStr) in strsAndEnc {
            do {
                let data: Data = cStr.withUnsafeBufferPointer({ (p) -> Data in return Data(buffer: p) })
                let maybeInfinity = try String.decode(data: data, fromCode: enc)
                XCTAssertEqual(infinity, maybeInfinity)
            } catch {
                XCTAssert(false, String(describing: error))
            }
        }
    }
    
    /**
     Japanese character encoding test.
     Original code is produced by `MaddTheSane`.
     https://github.com/MaddTheSane/SwiftIconV
     */
    func testJapaneseDecoding() {
        let sjisEnc: [Int8] = [-124, 112, -127, 105, -127, 125, -124, 112, -125, 116]
        let eucEnc: [Int8] = [-89, -47, -95, -54, -95, -34, -89, -47, -91, -43]
        let groundTruthString = "а（±а\u{30D5}"
        
        let sjisEncData: Data = sjisEnc.withUnsafeBufferPointer({ (p) -> Data in
            return Data(buffer: p)
        })
        let eucEncData: Data = eucEnc.withUnsafeBufferPointer({ (p) -> Data in
            return Data(buffer: p)
        })
        
        func compare(lhs: Data, rhs: Data) -> Bool {
            guard lhs.count == rhs.count else { return false }
            let pairs = Array(zip(lhs, rhs))
            for i in 0..<pairs.count {
                guard pairs[i].0 == pairs[i].1 else { return false }
            }
            return true
        }
        
        do {
            let eucConverted: Data = try String.decode(data: sjisEncData, toCode: "EUC-JP", fromCode: "SJIS")
            XCTAssert(compare(lhs: eucConverted, rhs: eucEncData))
        } catch {
            XCTFail(error.localizedDescription)
        }
        
        do {
            let str = try String.decode(data: sjisEncData, fromCode: "SJIS")
            print(str.utf16.count)
            print(groundTruthString.utf16.count)
            str.forEach({
                print($0)
            })
            groundTruthString.forEach({
                print($0)
            })
            
            XCTAssert(str == groundTruthString)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testExample() {
        /// Data set
        let array: [(String, String, String, String)] = [
            ("euc.txt", "EUC-JP", "shiftjis.txt", "SHIFT_JISX0213"),
            ("euc.txt", "EUC-JP", "utf8.txt", "UTF-8"),
            ("utf8.txt", "UTF-8", "euc.txt", "EUC-JP"),
            ("utf8.txt", "UTF-8", "shiftjis.txt", "SHIFT_JISX0213"),
            ("shiftjis.txt", "SHIFT_JISX0213", "euc.txt", "EUC-JP"),
            ("shiftjis.txt", "SHIFT_JISX0213", "utf8.txt", "UTF-8"),
        ]
        
        /**
         Test code to compare binary which is obtained by `iconv` with one that is loaded from ground truth file.
         */
        func test(sourceFile: String,  fromCode: String, targetFile: String, toCode: String) {
            do {
                guard let urlSourceFile = bundle.url(forResource: sourceFile, withExtension: nil) else {
                    XCTFail()
                    fatalError()
                }
                guard let urlTargetFile = bundle.url(forResource: targetFile, withExtension: nil) else {
                    XCTFail()
                    fatalError()
                }
                
                let data = try Data(contentsOf: urlSourceFile)
                let decoded: Data = try String.decode(data: data, toCode: toCode, fromCode: fromCode)
                let groundTruth = try Data(contentsOf: urlTargetFile)

                /// confirm decoded size
                XCTAssert(decoded.count == groundTruth.count)
                
                /// confirm each element of the decoded binaries
                zip(decoded, groundTruth).forEach({
                    XCTAssert($0.0 == $0.1)
                })
                
            } catch {
                print(error.localizedDescription)
            }
        }
        
        array.forEach({
            test(sourceFile: $0.0, fromCode: $0.1, targetFile: $0.2, toCode: $0.3)
        })
    }

    /**
     Performance test for comparing this framework with Foundation.
     */
    func testPerformance_of_StringIconv() {
        self.measure {
            do {
                guard let url = bundle.url(forResource: "shiftjis_large", withExtension: "txt") else {
                    XCTFail()
                    fatalError()
                }
                let data = try Data(contentsOf: url)
                _ = try String.decode(data: data, fromCode: "SHIFT-JIS", discardIllegalSequence: true, transliterate: false)
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    /**
     Performance test for comparing this framework with Foundation.
     */
    func testPerformance_of_Foundation() {
        self.measure {
            do {
                guard let url = bundle.url(forResource: "shiftjis_large", withExtension: "txt") else {
                    XCTFail()
                    fatalError()
                }
                let data = try Data(contentsOf: url)
                _ = String(data: data, encoding: .shiftJIS)
            } catch {
                print(error.localizedDescription)
            }
        }
    }
}
